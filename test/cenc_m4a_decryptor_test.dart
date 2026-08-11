import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:qishui_music/services/cenc_m4a_decryptor.dart';

void main() {
  test('decrypts and repairs a CENC M4A sample table', () {
    final key = Uint8List.fromList(List<int>.generate(16, (index) => index));
    final iv = Uint8List.fromList(List<int>.generate(8, (index) => index + 16));
    final plainSample = Uint8List.fromList([21, 34, 55, 89, 144, 233, 3, 5]);
    final encryptedSample = _aesCtr(key, iv, plainSample);
    final file = _buildEncryptedM4a(encryptedSample, iv);

    final decrypted = CencM4aDecryptor.decrypt(
      file,
      '000102030405060708090a0b0c0d0e0f',
    );

    expect(_containsType(decrypted, 'enca'), isFalse);
    expect(_containsType(decrypted, 'mp4a'), isTrue);
    expect(_containsType(decrypted, 'senc'), isFalse);
    expect(_containsType(decrypted, 'saio'), isFalse);
    expect(_containsType(decrypted, 'saiz'), isFalse);
    final mdat = _findBox(decrypted, 0, decrypted.length, 'mdat')!;
    expect(
      decrypted.sublist(mdat.offset + 8, mdat.end),
      plainSample,
    );
    final stco = _findNested(decrypted, 'stco')!;
    expect(_readUint32(decrypted, stco.offset + 16), mdat.offset + 8);

    final plan = CencM4aDecryptor.prepareOwnedForNative(
      Uint8List.fromList(file),
    );
    final nativeEquivalent = Uint8List.fromList(plan.repairedEncrypted);
    final table = ByteData.sublistView(plan.sampleTable);
    for (var offset = 0; offset < plan.sampleTable.length; offset += 24) {
      final sampleOffset = table.getUint32(offset, Endian.big);
      final sampleLength = table.getUint32(offset + 4, Endian.big);
      final sampleIv = plan.sampleTable.sublist(offset + 8, offset + 24);
      final clear = _aesCtr(
        key,
        sampleIv,
        Uint8List.sublistView(
          nativeEquivalent,
          sampleOffset,
          sampleOffset + sampleLength,
        ),
      );
      nativeEquivalent.setRange(
        sampleOffset,
        sampleOffset + sampleLength,
        clear,
      );
    }
    expect(nativeEquivalent, decrypted);
  });
}

Uint8List _aesCtr(Uint8List key, Uint8List iv, Uint8List input) {
  final iv16 = Uint8List(16)..setRange(0, iv.length, iv);
  final cipher = SICStreamCipher(AESEngine())
    ..init(true, ParametersWithIV(KeyParameter(key), iv16));
  return cipher.process(input);
}

Uint8List _buildEncryptedM4a(Uint8List sample, Uint8List iv) {
  final tenc = _box(
      'tenc',
      Uint8List.fromList([
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        8,
      ]));
  final schi = _box('schi', tenc);
  final sinf = _box('sinf', schi);
  final enca = _box(
    'enca',
    Uint8List.fromList([
      ...List<int>.filled(28, 0),
      ...sinf,
    ]),
  );
  final stsd = _box(
      'stsd',
      Uint8List.fromList([
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        ...enca,
      ]));
  final stsz = _box(
      'stsz',
      Uint8List.fromList([
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        sample.length,
      ]));
  final stsc = _box(
      'stsc',
      Uint8List.fromList([
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
      ]));
  final senc = _box(
      'senc',
      Uint8List.fromList([
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        ...iv,
      ]));
  final saio = _box('saio', Uint8List(0));
  final saiz = _box('saiz', Uint8List(0));
  final placeholderStco = _box(
      'stco',
      Uint8List.fromList([
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
      ]));
  final stbl = _box(
      'stbl',
      Uint8List.fromList([
        ...stsd,
        ...stsz,
        ...stsc,
        ...placeholderStco,
        ...senc,
        ...saio,
        ...saiz,
      ]));
  final minf = _box('minf', stbl);
  final mdia = _box('mdia', minf);
  final trak = _box('trak', mdia);
  final moov = _box('moov', trak);
  final mdat = _box('mdat', sample);
  final file = Uint8List.fromList([...moov, ...mdat]);
  final stco = _findNested(file, 'stco')!;
  _writeUint32(file, stco.offset + 16, moov.length + 8);
  return file;
}

Uint8List _box(String type, Uint8List payload) {
  final box = Uint8List(8 + payload.length);
  _writeUint32(box, 0, box.length);
  box.setRange(4, 8, type.codeUnits);
  box.setRange(8, box.length, payload);
  return box;
}

bool _containsType(Uint8List bytes, String type) =>
    String.fromCharCodes(bytes).contains(type);

_Box? _findNested(Uint8List bytes, String type) {
  _Box? visit(int start, int end) {
    var position = start;
    while (position + 8 <= end) {
      final size = _readUint32(bytes, position);
      final box = _Box(position, size,
          String.fromCharCodes(bytes.sublist(position + 4, position + 8)));
      if (box.type == type) return box;
      if (const {'moov', 'trak', 'mdia', 'minf', 'stbl'}.contains(box.type)) {
        final found = visit(position + 8, position + size);
        if (found != null) return found;
      }
      position += size;
    }
    return null;
  }

  return visit(0, bytes.length);
}

_Box? _findBox(Uint8List bytes, int start, int end, String type) {
  var position = start;
  while (position + 8 <= end) {
    final size = _readUint32(bytes, position);
    final box = _Box(position, size,
        String.fromCharCodes(bytes.sublist(position + 4, position + 8)));
    if (box.type == type) return box;
    position += size;
  }
  return null;
}

int _readUint32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

void _writeUint32(Uint8List bytes, int offset, int value) {
  bytes[offset] = value >> 24;
  bytes[offset + 1] = value >> 16;
  bytes[offset + 2] = value >> 8;
  bytes[offset + 3] = value;
}

class _Box {
  final int offset;
  final int size;
  final String type;

  const _Box(this.offset, this.size, this.type);

  int get end => offset + size;
}
