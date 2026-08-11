import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class CencM4aDecryptor {
  static Uint8List decrypt(Uint8List encrypted, String aesKeyHex) {
    return _decrypt(Uint8List.fromList(encrypted), aesKeyHex);
  }

  /// Decrypts a buffer owned by the caller and may reuse it for the result.
  static Uint8List decryptOwned(Uint8List encrypted, String aesKeyHex) {
    return _decrypt(encrypted, aesKeyHex);
  }

  static CencNativeDecryptPlan prepareOwnedForNative(Uint8List encrypted) {
    final layout = _readLayout(encrypted);
    final samples = _collectSamples(layout);
    final repaired = _repair(encrypted, layout);
    final table = ByteData(samples.length * 24);
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index];
      final repairedOffset = sample.offset - layout.removedBytes;
      if (repairedOffset < 0 ||
          repairedOffset + sample.length > repaired.length) {
        throw const FormatException('Invalid repaired CENC sample offset');
      }
      final recordOffset = index * 24;
      table.setUint32(recordOffset, repairedOffset, Endian.big);
      table.setUint32(recordOffset + 4, sample.length, Endian.big);
      table.buffer.asUint8List(recordOffset + 8, 16)
        ..fillRange(0, 16, 0)
        ..setRange(0, sample.iv.length, sample.iv);
    }
    return CencNativeDecryptPlan(repaired, table.buffer.asUint8List());
  }

  static Uint8List _decrypt(Uint8List bytes, String aesKeyHex) {
    final key = _decodeHex(aesKeyHex);
    if (key.length != 16) {
      throw const FormatException('CENC AES-128 key must be 16 bytes');
    }

    final layout = _readLayout(bytes);
    final samples = _collectSamples(layout);
    _decryptSamples(bytes, key, samples);
    return _repair(bytes, layout);
  }

  static _CencLayout _readLayout(Uint8List bytes) {
    final top = _walk(bytes, 0, bytes.length);
    final moov = _required(_find(top, 'moov'), 'moov');
    final trak = _required(_find(_children(bytes, moov), 'trak'), 'trak');
    final mdia = _required(_find(_children(bytes, trak), 'mdia'), 'mdia');
    final minf = _required(_find(_children(bytes, mdia), 'minf'), 'minf');
    final stbl = _required(_find(_children(bytes, minf), 'stbl'), 'stbl');
    final stblChildren = _children(bytes, stbl);

    final senc = _required(_find(stblChildren, 'senc'), 'senc');
    final stsz = _required(_find(stblChildren, 'stsz'), 'stsz');
    final stco = _required(_find(stblChildren, 'stco'), 'stco');
    final stsc = _required(_find(stblChildren, 'stsc'), 'stsc');
    final stsd = _required(_find(stblChildren, 'stsd'), 'stsd');
    final saio = _find(stblChildren, 'saio');
    final saiz = _find(stblChildren, 'saiz');

    final enca = _findEnca(bytes, stsd);
    final ivSize = enca == null ? 8 : _readIvSize(bytes, enca);
    final ivs = _readSampleIvs(bytes, senc, ivSize);
    final sampleSizes = _readSampleSizes(bytes, stsz, ivs.length);
    final chunkOffsets = _readChunkOffsets(bytes, stco);
    final samplesPerChunk =
        _readSamplesPerChunk(bytes, stsc, chunkOffsets.length);

    final removable = [senc, saio, saiz].whereType<_Mp4Box>().toList();
    final removeStart =
        removable.isEmpty ? 0 : removable.map((box) => box.offset).reduce(_min);
    final removeEnd =
        removable.isEmpty ? 0 : removable.map((box) => box.end).reduce(_max);
    return _CencLayout(
      bytes,
      moov,
      trak,
      mdia,
      minf,
      stbl,
      enca,
      ivs,
      sampleSizes,
      chunkOffsets,
      samplesPerChunk,
      removeStart,
      removeEnd,
    );
  }

  static List<_CencSample> _collectSamples(_CencLayout layout) {
    final samples = <_CencSample>[];
    var sampleIndex = 0;
    for (var chunkIndex = 0;
        chunkIndex < layout.chunkOffsets.length;
        chunkIndex++) {
      var offset = layout.chunkOffsets[chunkIndex];
      for (var entry = 0;
          entry < layout.samplesPerChunk[chunkIndex] &&
              sampleIndex < layout.ivs.length;
          entry++) {
        final length = layout.sampleSizes[sampleIndex];
        if (offset < 0 || length < 0 || offset + length > layout.bytes.length) {
          throw const FormatException('Invalid CENC sample offset');
        }
        samples.add(_CencSample(offset, length, layout.ivs[sampleIndex]));
        offset += length;
        sampleIndex++;
      }
    }
    if (sampleIndex != layout.ivs.length) {
      throw const FormatException(
          'CENC chunk table did not cover every sample');
    }
    return samples;
  }

  static Uint8List _repair(Uint8List bytes, _CencLayout layout) {
    final enca = layout.enca;
    if (enca != null) {
      _writeType(bytes, enca.offset + 4, 'mp4a');
    }

    final removeStart = layout.removeStart;
    final removeEnd = layout.removeEnd;
    final removedBytes = layout.removedBytes;
    if (removedBytes <= 0) return bytes;

    final resultLength = bytes.length - removedBytes;
    bytes.setRange(removeStart, resultLength, bytes, removeEnd);
    final result = Uint8List.sublistView(bytes, 0, resultLength);
    for (final parent in [
      layout.stbl,
      layout.minf,
      layout.mdia,
      layout.trak,
      layout.moov,
    ]) {
      _writeUint32(result, parent.offset, parent.size - removedBytes);
    }
    _fixChunkOffsets(result, removedBytes);
    return result;
  }

  static _Mp4Box _required(_Mp4Box? box, String type) {
    if (box == null) throw FormatException('CENC M4A missing $type box');
    return box;
  }

  static List<_Mp4Box> _children(Uint8List bytes, _Mp4Box box) =>
      _walk(bytes, box.offset + box.headerSize, box.end);

  static List<_Mp4Box> _walk(Uint8List bytes, int start, int end) {
    final boxes = <_Mp4Box>[];
    var position = start;
    while (position + 8 <= end) {
      var size = _readUint32(bytes, position);
      const headerSize = 8;
      if (size == 0) size = end - position;
      if (size < headerSize || position + size > end) {
        throw const FormatException('Invalid MP4 box size');
      }
      boxes.add(_Mp4Box(
        position,
        size,
        _readType(bytes, position + 4),
        headerSize,
      ));
      position += size;
    }
    if (position != end) {
      throw const FormatException('Invalid MP4 box boundary');
    }
    return boxes;
  }

  static _Mp4Box? _find(List<_Mp4Box> boxes, String type) {
    for (final box in boxes) {
      if (box.type == type) return box;
    }
    return null;
  }

  static _Mp4Box? _findEnca(Uint8List bytes, _Mp4Box stsd) {
    final firstEntry = stsd.offset + 16; // box header + full box + entry count
    if (firstEntry + 8 > stsd.end) return null;
    final size = _readUint32(bytes, firstEntry);
    if (size < 36 || firstEntry + size > stsd.end) {
      throw const FormatException('Invalid stsd sample entry');
    }
    return _readType(bytes, firstEntry + 4) == 'enca'
        ? _Mp4Box(firstEntry, size, 'enca', 8)
        : null;
  }

  static int _readIvSize(Uint8List bytes, _Mp4Box enca) {
    final sampleEntryChildren = _walk(bytes, enca.offset + 36, enca.end);
    final sinf = _find(sampleEntryChildren, 'sinf');
    if (sinf == null) return 8;
    final schi = _find(_children(bytes, sinf), 'schi');
    if (schi == null) return 8;
    final tenc = _find(_children(bytes, schi), 'tenc');
    if (tenc == null || tenc.offset + 15 >= tenc.end) return 8;
    final ivSize = bytes[tenc.offset + tenc.headerSize + 7];
    if (ivSize <= 0 || ivSize > 16) {
      throw const FormatException('Invalid CENC IV size');
    }
    return ivSize;
  }

  static List<Uint8List> _readSampleIvs(
    Uint8List bytes,
    _Mp4Box senc,
    int ivSize,
  ) {
    if (senc.offset + 16 > senc.end) {
      throw const FormatException('Invalid senc box');
    }
    final flags = _readUint32(bytes, senc.offset + 8) & 0x00ffffff;
    final sampleCount = _readUint32(bytes, senc.offset + 12);
    final hasSubsamples = flags & 0x02 != 0;
    final ivs = <Uint8List>[];
    var position = senc.offset + 16;
    for (var index = 0; index < sampleCount; index++) {
      if (position + ivSize > senc.end) {
        throw const FormatException('Invalid CENC IV data');
      }
      ivs.add(Uint8List.fromList(bytes.sublist(position, position + ivSize)));
      position += ivSize;
      if (hasSubsamples) {
        if (position + 2 > senc.end) {
          throw const FormatException('Invalid CENC subsample data');
        }
        final count = _readUint16(bytes, position);
        position += 2 + count * 6;
        if (position > senc.end) {
          throw const FormatException('Invalid CENC subsample data');
        }
      }
    }
    return ivs;
  }

  static List<int> _readSampleSizes(
    Uint8List bytes,
    _Mp4Box stsz,
    int expectedCount,
  ) {
    if (stsz.offset + 20 > stsz.end) {
      throw const FormatException('Invalid stsz box');
    }
    final constantSize = _readUint32(bytes, stsz.offset + 12);
    final count = _readUint32(bytes, stsz.offset + 16);
    if (count != expectedCount) {
      throw const FormatException('CENC sample count does not match stsz');
    }
    if (constantSize != 0) return List<int>.filled(count, constantSize);
    if (stsz.offset + 20 + count * 4 > stsz.end) {
      throw const FormatException('Invalid stsz sample data');
    }
    return List<int>.generate(
      count,
      (index) => _readUint32(bytes, stsz.offset + 20 + index * 4),
    );
  }

  static List<int> _readChunkOffsets(Uint8List bytes, _Mp4Box stco) {
    if (stco.offset + 16 > stco.end) {
      throw const FormatException('Invalid stco box');
    }
    final count = _readUint32(bytes, stco.offset + 12);
    if (stco.offset + 16 + count * 4 > stco.end) {
      throw const FormatException('Invalid stco offset data');
    }
    return List<int>.generate(
      count,
      (index) => _readUint32(bytes, stco.offset + 16 + index * 4),
    );
  }

  static List<int> _readSamplesPerChunk(
    Uint8List bytes,
    _Mp4Box stsc,
    int chunkCount,
  ) {
    if (stsc.offset + 16 > stsc.end) {
      throw const FormatException('Invalid stsc box');
    }
    final count = _readUint32(bytes, stsc.offset + 12);
    if (count == 0 || stsc.offset + 16 + count * 12 > stsc.end) {
      throw const FormatException('Invalid stsc entries');
    }
    final entries = List<_StscEntry>.generate(count, (index) {
      final offset = stsc.offset + 16 + index * 12;
      return _StscEntry(
          _readUint32(bytes, offset), _readUint32(bytes, offset + 4));
    });
    return List<int>.generate(chunkCount, (index) {
      final chunk = index + 1;
      var samples = entries.first.samplesPerChunk;
      for (final entry in entries) {
        if (chunk >= entry.firstChunk) samples = entry.samplesPerChunk;
      }
      return samples;
    });
  }

  static void _decryptSamples(
    Uint8List bytes,
    Uint8List key,
    List<_CencSample> samples,
  ) {
    final decryptor = _AesCtrSampleDecryptor(key);
    for (final sample in samples) {
      decryptor.decrypt(bytes, sample.offset, sample.length, sample.iv);
    }
  }

  static void _fixChunkOffsets(Uint8List bytes, int removedBytes) {
    final stco = _find(_walk(bytes, 0, bytes.length), 'stco') ??
        _findNested(bytes, 'stco');
    if (stco == null) throw const FormatException('Repaired M4A missing stco');
    final count = _readUint32(bytes, stco.offset + 12);
    for (var index = 0; index < count; index++) {
      final offset = stco.offset + 16 + index * 4;
      final value = _readUint32(bytes, offset);
      if (value < removedBytes) {
        throw const FormatException('Invalid repaired M4A chunk offset');
      }
      _writeUint32(bytes, offset, value - removedBytes);
    }
  }

  static _Mp4Box? _findNested(Uint8List bytes, String wantedType) {
    _Mp4Box? visit(List<_Mp4Box> boxes) {
      for (final box in boxes) {
        if (box.type == wantedType) return box;
        if (const {'moov', 'trak', 'mdia', 'minf', 'stbl'}.contains(box.type)) {
          final found = visit(_children(bytes, box));
          if (found != null) return found;
        }
      }
      return null;
    }

    return visit(_walk(bytes, 0, bytes.length));
  }

  static Uint8List _decodeHex(String value) {
    if (value.length.isOdd) throw const FormatException('Invalid AES key hex');
    return Uint8List.fromList(List<int>.generate(
      value.length ~/ 2,
      (index) =>
          int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
    ));
  }

  static int _readUint16(Uint8List bytes, int offset) =>
      (bytes[offset] << 8) | bytes[offset + 1];

  static int _readUint32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  static void _writeUint32(Uint8List bytes, int offset, int value) {
    if (value < 0 || value > 0xffffffff) {
      throw const FormatException('Invalid MP4 box value');
    }
    bytes[offset] = value >> 24;
    bytes[offset + 1] = value >> 16;
    bytes[offset + 2] = value >> 8;
    bytes[offset + 3] = value;
  }

  static String _readType(Uint8List bytes, int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));

  static void _writeType(Uint8List bytes, int offset, String type) {
    bytes.setRange(offset, offset + 4, type.codeUnits);
  }

  static int _min(int a, int b) => a < b ? a : b;
  static int _max(int a, int b) => a > b ? a : b;
}

class CencNativeDecryptPlan {
  final Uint8List repairedEncrypted;
  final Uint8List sampleTable;

  const CencNativeDecryptPlan(this.repairedEncrypted, this.sampleTable);
}

class _CencLayout {
  final Uint8List bytes;
  final _Mp4Box moov;
  final _Mp4Box trak;
  final _Mp4Box mdia;
  final _Mp4Box minf;
  final _Mp4Box stbl;
  final _Mp4Box? enca;
  final List<Uint8List> ivs;
  final List<int> sampleSizes;
  final List<int> chunkOffsets;
  final List<int> samplesPerChunk;
  final int removeStart;
  final int removeEnd;

  const _CencLayout(
    this.bytes,
    this.moov,
    this.trak,
    this.mdia,
    this.minf,
    this.stbl,
    this.enca,
    this.ivs,
    this.sampleSizes,
    this.chunkOffsets,
    this.samplesPerChunk,
    this.removeStart,
    this.removeEnd,
  );

  int get removedBytes => removeEnd - removeStart;
}

class _CencSample {
  final int offset;
  final int length;
  final Uint8List iv;

  const _CencSample(this.offset, this.length, this.iv);
}

class _AesCtrSampleDecryptor {
  final AESEngine _aes = AESEngine();
  final Uint8List _counter = Uint8List(16);
  final Uint8List _keyStream = Uint8List(16);

  _AesCtrSampleDecryptor(Uint8List key) {
    _aes.init(true, KeyParameter(key));
  }

  void decrypt(Uint8List bytes, int offset, int length, Uint8List iv) {
    _counter.fillRange(0, _counter.length, 0);
    _counter.setRange(0, iv.length, iv);
    var position = offset;
    final end = offset + length;
    while (position < end) {
      _aes.processBlock(_counter, 0, _keyStream, 0);
      final blockEnd = position + 16 < end ? position + 16 : end;
      for (var index = position; index < blockEnd; index++) {
        bytes[index] ^= _keyStream[index - position];
      }
      _incrementCounter();
      position = blockEnd;
    }
  }

  void _incrementCounter() {
    for (var index = _counter.length - 1; index >= 0; index--) {
      _counter[index] = (_counter[index] + 1) & 0xff;
      if (_counter[index] != 0) return;
    }
  }
}

class _Mp4Box {
  final int offset;
  final int size;
  final String type;
  final int headerSize;

  const _Mp4Box(this.offset, this.size, this.type, this.headerSize);

  int get end => offset + size;
}

class _StscEntry {
  final int firstChunk;
  final int samplesPerChunk;

  const _StscEntry(this.firstChunk, this.samplesPerChunk);
}
