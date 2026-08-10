import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qishui_music/services/progressive_audio_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;

  setUpAll(() async {
    HttpOverrides.global = null;
    documents = await Directory.systemTemp.createTemp(
      'qishui_progressive_cache_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return documents.path;
      }
      return null;
    });
  });

  tearDown(() => ProgressiveAudioCacheService().dispose());

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    await documents.delete(recursive: true);
  });

  test('streams and caches audio with one upstream request', () async {
    final sourceBytes = List<int>.generate(256 * 1024, (index) => index % 251);
    var upstreamRequests = 0;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamSubscription = upstream.listen((request) async {
      upstreamRequests++;
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.contentLength = sourceBytes.length;
      for (var offset = 0; offset < sourceBytes.length; offset += 16 * 1024) {
        final end = (offset + 16 * 1024).clamp(0, sourceBytes.length);
        request.response.add(sourceBytes.sublist(offset, end));
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await request.response.close();
    });

    final completed = Completer<String>();
    final service = ProgressiveAudioCacheService();
    final playbackUrl = await service.start(
      songId: 'single_stream_song',
      sourceUrl: 'http://127.0.0.1:${upstream.port}/audio.mp3',
      quality: 320,
      onComplete: completed.complete,
    );
    expect(playbackUrl, isNotNull);

    final client = HttpClient();
    final playbackRequest = await client.getUrl(Uri.parse(playbackUrl!));
    final playbackResponse = await playbackRequest.close();
    final playedBytes = await playbackResponse.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    final cachedPath =
        await completed.future.timeout(const Duration(seconds: 5));

    expect(upstreamRequests, 1);
    expect(playedBytes, sourceBytes);
    expect(await File(cachedPath).readAsBytes(), sourceBytes);

    final rangeRequest = await client.getUrl(Uri.parse(playbackUrl));
    rangeRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=1024-2047');
    final rangeResponse = await rangeRequest.close();
    final rangeBytes = await rangeResponse.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    expect(rangeResponse.statusCode, HttpStatus.partialContent);
    expect(rangeBytes, sourceBytes.sublist(1024, 2048));
    expect(upstreamRequests, 1);

    client.close(force: true);
    await upstreamSubscription.cancel();
    await upstream.close(force: true);
  });

  test('uses the API M4A extension when the stream URL has no suffix',
      () async {
    final sourceBytes = List<int>.generate(4096, (index) => index % 251);
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamSubscription = upstream.listen((request) async {
      request.response.headers.contentType = ContentType('audio', 'mp4');
      request.response.contentLength = sourceBytes.length;
      request.response.add(sourceBytes);
      await request.response.close();
    });

    final completed = Completer<String>();
    final service = ProgressiveAudioCacheService();
    await service.start(
      songId: 'm4a_stream_song',
      sourceUrl: 'http://127.0.0.1:${upstream.port}/stream/123?quality=highest',
      quality: 260,
      onComplete: completed.complete,
    );
    final cachedPath =
        await completed.future.timeout(const Duration(seconds: 5));

    expect(cachedPath.toLowerCase(), endsWith('.m4a'));
    await upstreamSubscription.cancel();
    await upstream.close(force: true);
  });

  test('resumes an interrupted upstream stream without redownloading bytes',
      () async {
    final sourceBytes = List<int>.generate(192 * 1024, (index) => index % 239);
    const cutoff = 64 * 1024;
    var upstreamRequests = 0;
    final receivedRanges = <String?>[];
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamSubscription = upstream.listen((request) async {
      upstreamRequests++;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      receivedRanges.add(range);
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      if (upstreamRequests == 1) {
        request.response.contentLength = sourceBytes.length;
        request.response.add(sourceBytes.sublist(0, cutoff));
        await request.response.flush();
        try {
          await request.response.close();
        } catch (_) {
          // Intentionally terminate before the advertised content length.
        }
        return;
      }

      expect(range, 'bytes=$cutoff-');
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $cutoff-${sourceBytes.length - 1}/${sourceBytes.length}',
      );
      request.response.contentLength = sourceBytes.length - cutoff;
      request.response.add(sourceBytes.sublist(cutoff));
      await request.response.close();
    });

    final completed = Completer<String>();
    final failed = Completer<Object>();
    final service = ProgressiveAudioCacheService();
    final playbackUrl = await service.start(
      songId: 'resumed_stream_song',
      sourceUrl: 'http://127.0.0.1:${upstream.port}/audio.mp3',
      quality: 320,
      onComplete: completed.complete,
      onError: failed.complete,
    );
    expect(playbackUrl, isNotNull);

    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(playbackUrl!));
    final response = await request.close();
    final playedBytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    final cachedPath =
        await completed.future.timeout(const Duration(seconds: 5));

    expect(failed.isCompleted, isFalse);
    expect(upstreamRequests, 2);
    expect(receivedRanges, [null, 'bytes=$cutoff-']);
    expect(playedBytes, sourceBytes);
    expect(await File(cachedPath).readAsBytes(), sourceBytes);

    client.close(force: true);
    await upstreamSubscription.cancel();
    await upstream.close(force: true);
  });
}
