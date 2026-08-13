import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/services/audio_cache_service.dart';
import 'package:music/services/cover_cache_service.dart';
import 'package:music/services/lyric_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUpAll(() async {
    HttpOverrides.global = null;
    documents = await Directory.systemTemp.createTemp(
      'qishui_local_cache_delivery_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return documents.path;
      }
      return null;
    });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    await documents.delete(recursive: true);
  });

  test('lyrics are returned only after being persisted locally', () async {
    const lyricId = 'local_lyric';
    const lyric = '[00:01.00]cached lyric';

    final delivered = await LyricCacheService().saveAndLoad(lyricId, lyric);
    final file = File('${documents.path}/lyric_cache/$lyricId.lrc');

    expect(delivered, lyric);
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), lyric);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('audio cache path always uses the encrypted M4A format', () async {
    final path = await AudioCacheService().getFilePath('strict_song', 260);

    expect(path, endsWith('strict_song_260.encrypted.m4a'));
  });

  test('unsupported and keyless audio files are never cache hits', () async {
    final cacheDir = Directory('${documents.path}/audio_cache');
    await cacheDir.create(recursive: true);
    final unsupportedMp3 = File('${cacheDir.path}/strict_lookup_320.mp3');
    final unsupportedM4a = File('${cacheDir.path}/strict_lookup_320.m4a');
    final keyless = File('${cacheDir.path}/strict_lookup_320.encrypted.m4a');
    await unsupportedMp3.writeAsBytes([1, 2, 3]);
    await unsupportedM4a.writeAsBytes([1, 2, 3]);
    await keyless.writeAsBytes([1, 2, 3]);

    expect(
        await AudioCacheService().findBestCachedFile('strict_lookup'), isNull);
    expect(
      await AudioCacheService()
          .findCachedFile('strict_lookup', requestedBr: 320),
      isNull,
    );

    await File('${keyless.path}.key').writeAsString('0011223344556677');
    final cached =
        await AudioCacheService().findBestCachedFile('strict_lookup');

    expect(cached, isNotNull);
    String normalizedPath(String path) =>
        File(path).absolute.path.replaceAll('\\', '/').toLowerCase();
    expect(normalizedPath(cached!.path), normalizedPath(keyless.path));
    expect(cached.decryptionKey, '0011223344556677');
    expect(await unsupportedMp3.exists(), isTrue);
    expect(await unsupportedM4a.exists(), isTrue);
  });

  test('cover bytes are returned from the completed local cache file',
      () async {
    final sourceBytes = pngBytes;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.contentLength = sourceBytes.length;
      request.response.add(sourceBytes);
      await request.response.close();
    });

    try {
      final delivered = await CoverCacheService().download(
        'local_cover',
        'http://127.0.0.1:${server.port}/cover.jpg',
      );
      final localPath = await CoverCacheService().getLocalPath('local_cover');

      expect(localPath, isNotNull);
      expect(delivered, sourceBytes);
      expect(await File(localPath!).readAsBytes(), sourceBytes);
      expect(await File('$localPath.tmp').exists(), isFalse);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('local file covers are persisted before being returned', () async {
    final source = File('${documents.path}/source-cover.png');
    await source.writeAsBytes(pngBytes, flush: true);

    final delivered = await CoverCacheService().resolve(
      'local_file_cover',
      source.uri.toString(),
    );
    final localPath =
        await CoverCacheService().getLocalPath('local_file_cover');

    expect(delivered, pngBytes);
    expect(localPath, isNotNull);
    expect(localPath, isNot(source.path));
    expect(await File(localPath!).readAsBytes(), pngBytes);
  });

  test('invalid cover responses never become cache hits', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html>temporary CDN error</html>');
      await request.response.close();
    });

    try {
      final delivered = await CoverCacheService().download(
        'invalid_cover',
        'http://127.0.0.1:${server.port}/cover.jpg',
      );

      expect(delivered, isNull);
      expect(await CoverCacheService().getLocalPath('invalid_cover'), isNull);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('invalid existing cover cache is removed and redownloaded', () async {
    final cacheDir = Directory('${documents.path}/cover_cache');
    await cacheDir.create(recursive: true);
    final cachedFile = File('${cacheDir.path}/recovered_cover.jpg');
    await cachedFile.writeAsString('<html>stale error</html>', flush: true);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.add(pngBytes);
      await request.response.close();
    });

    try {
      final delivered = await CoverCacheService().download(
        'recovered_cover',
        'http://127.0.0.1:${server.port}/cover.png',
      );

      expect(delivered, pngBytes);
      expect(await cachedFile.readAsBytes(), pngBytes);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
