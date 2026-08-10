import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class CencM4aDecryptor {
  static Uint8List decrypt(Uint8List encrypted, String aesKeyHex) {
    final key = _decodeHex(aesKeyHex);
    if (key.length != 16) {
      throw const FormatException('CENC AES-128 key must be 16 bytes');
    }

    final bytes = Uint8List.fromList(encrypted);
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

    _decryptSamples(
      bytes,
      key,
      ivs,
      sampleSizes,
      chunkOffsets,
      samplesPerChunk,
    );
    if (enca != null) {
      _writeType(bytes, enca.offset + 4, 'mp4a');
    }

    final removable = [senc, saio, saiz].whereType<_Mp4Box>().toList();
    if (removable.isEmpty) return bytes;
    final removeStart = removable.map((box) => box.offset).reduce(_min);
    final removeEnd = removable.map((box) => box.end).reduce(_max);
    final removedBytes = removeEnd - removeStart;
    if (removedBytes <= 0) return bytes;

    final result = Uint8List(bytes.length - removedBytes);
    result.setRange(0, removeStart, bytes);
    result.setRange(removeStart, result.length, bytes, removeEnd);
    for (final parent in [stbl, minf, mdia, trak, moov]) {
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
    List<Uint8List> ivs,
    List<int> sampleSizes,
    List<int> chunkOffsets,
    List<int> samplesPerChunk,
  ) {
    var sampleIndex = 0;
    for (var chunkIndex = 0; chunkIndex < chunkOffsets.length; chunkIndex++) {
      var offset = chunkOffsets[chunkIndex];
      for (var entry = 0;
          entry < samplesPerChunk[chunkIndex] && sampleIndex < ivs.length;
          entry++) {
        final length = sampleSizes[sampleIndex];
        if (offset < 0 || length < 0 || offset + length > bytes.length) {
          throw const FormatException('Invalid CENC sample offset');
        }
        final iv = Uint8List(16)
          ..setRange(0, ivs[sampleIndex].length, ivs[sampleIndex]);
        final cipher = SICStreamCipher(AESEngine())
          ..init(true, ParametersWithIV(KeyParameter(key), iv));
        final decrypted = cipher.process(Uint8List.fromList(
          bytes.sublist(offset, offset + length),
        ));
        bytes.setRange(offset, offset + length, decrypted);
        offset += length;
        sampleIndex++;
      }
    }
    if (sampleIndex != ivs.length) {
      throw const FormatException(
          'CENC chunk table did not cover every sample');
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
