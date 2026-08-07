import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'audio_cache_service.dart';

/// Downloads an audio stream exactly once, writes it to the persistent cache,
/// and exposes the growing file through a loopback HTTP server for playback.
class ProgressiveAudioCacheService {
  static final ProgressiveAudioCacheService _instance =
      ProgressiveAudioCacheService._();

  factory ProgressiveAudioCacheService() => _instance;

  ProgressiveAudioCacheService._();

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _serverSubscription;
  final Map<String, _ProgressiveAudioSession> _sessions = {};
  _ProgressiveAudioSession? _activeSession;
  int _nextToken = 0;

  Future<String?> start({
    required String songId,
    required String sourceUrl,
    required int quality,
    void Function(double progress)? onProgress,
    void Function(String path)? onComplete,
    void Function(Object error)? onError,
  }) async {
    await cancelActive();

    try {
      await _ensureServer();
      final finalPath = await AudioCacheService().getFilePath(
        songId,
        sourceUrl,
        quality,
      );
      final token = '${DateTime.now().microsecondsSinceEpoch}_${_nextToken++}';
      final session = _ProgressiveAudioSession(
        songId: songId,
        sourceUrl: sourceUrl,
        finalPath: finalPath,
        onProgress: onProgress,
        onComplete: onComplete,
        onError: onError,
      );
      _sessions[token] = session;
      _activeSession = session;
      session.start();

      if (!await session.waitUntilReady()) {
        _sessions.remove(token);
        if (identical(_activeSession, session)) _activeSession = null;
        await session.cancel();
        return null;
      }

      return 'http://127.0.0.1:${_server!.port}/audio/$token';
    } catch (_) {
      await cancelActive();
      return null;
    }
  }

  Future<void> cancelActive() async {
    final session = _activeSession;
    if (session == null) return;
    _activeSession = null;
    _sessions.removeWhere((_, value) => identical(value, session));
    await session.cancel();
  }

  Future<void> _ensureServer() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _serverSubscription = server.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (segments.length != 2 || segments.first != 'audio') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final session = _sessions[segments.last];
    if (session == null) {
      request.response.statusCode = HttpStatus.gone;
      await request.response.close();
      return;
    }
    await session.serve(request);
  }

  Future<void> dispose() async {
    await cancelActive();
    await _serverSubscription?.cancel();
    await _server?.close(force: true);
    _serverSubscription = null;
    _server = null;
    _sessions.clear();
  }
}

class _ProgressiveAudioSession {
  final String songId;
  final String sourceUrl;
  final String finalPath;
  final void Function(double progress)? onProgress;
  final void Function(String path)? onComplete;
  final void Function(Object error)? onError;

  final http.Client _client = http.Client();
  final Completer<bool> _ready = Completer<bool>();
  final Completer<void> _done = Completer<void>();
  Completer<void>? _dataAvailable;
  RandomAccessFile? _writer;

  late final String temporaryPath = '$finalPath.stream.tmp';
  int _downloadedBytes = 0;
  int? _totalBytes;
  String? _contentType;
  bool _finished = false;
  bool _cancelled = false;

  _ProgressiveAudioSession({
    required this.songId,
    required this.sourceUrl,
    required this.finalPath,
    this.onProgress,
    this.onComplete,
    this.onError,
  });

  void start() {
    unawaited(_download());
  }

  Future<bool> waitUntilReady() => _ready.future;

  Future<void> _download() async {
    final temporaryFile = File(temporaryPath);
    try {
      if (await temporaryFile.exists()) await temporaryFile.delete();
      _writer = await temporaryFile.open(mode: FileMode.write);

      const maxAttempts = 3;
      Object? lastError;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          final request = http.Request('GET', Uri.parse(sourceUrl));
          request.headers['User-Agent'] = 'Mozilla/5.0';
          if (_downloadedBytes > 0) {
            request.headers[HttpHeaders.rangeHeader] =
                'bytes=$_downloadedBytes-';
          }

          final response =
              await _client.send(request).timeout(const Duration(seconds: 10));
          if (_downloadedBytes == 0) {
            if (response.statusCode != HttpStatus.ok) {
              throw HttpException('HTTP ${response.statusCode}');
            }
            _totalBytes = response.contentLength;
            if (_totalBytes != null && _totalBytes! <= 0) {
              _totalBytes = null;
            }
            _contentType = response.headers['content-type'];
            if (!_ready.isCompleted) _ready.complete(true);
          } else {
            if (response.statusCode != HttpStatus.partialContent) {
              throw const HttpException(
                'Audio server does not support resuming a partial stream',
              );
            }
            final resumedRange = _parseContentRange(
              response.headers[HttpHeaders.contentRangeHeader],
            );
            if (resumedRange == null || resumedRange.$1 != _downloadedBytes) {
              throw const HttpException('Audio resume range is invalid');
            }
            _totalBytes = resumedRange.$2;
          }

          await for (final chunk
              in response.stream.timeout(const Duration(seconds: 15))) {
            if (_cancelled) break;
            await _writer!.writeFrom(chunk);
            _downloadedBytes += chunk.length;
            final total = _totalBytes;
            if (total != null && total > 0) {
              onProgress?.call(
                (_downloadedBytes / total).clamp(0.0, 1.0),
              );
            }
            _signalDataAvailable();
          }

          if (_cancelled) return;
          final total = _totalBytes;
          if (total != null && _downloadedBytes < total) {
            throw const FileSystemException('Audio download was incomplete');
          }
          lastError = null;
          break;
        } catch (error) {
          lastError = error;
          if (_cancelled) return;
          if (attempt >= maxAttempts) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      }

      if (lastError != null) throw lastError;

      await _writer?.close();
      _writer = null;
      if (_cancelled) return;
      if (_downloadedBytes <= 0) {
        throw const FileSystemException('Downloaded audio file is empty');
      }
      await AudioCacheService().commitDownloadedFile(
        songId,
        temporaryPath,
        finalPath,
      );
      onProgress?.call(1.0);
      onComplete?.call(finalPath);
    } catch (error) {
      if (!_ready.isCompleted) _ready.complete(false);
      try {
        await _writer?.close();
      } catch (_) {}
      _writer = null;
      try {
        if (await temporaryFile.exists()) await temporaryFile.delete();
      } catch (_) {}
      if (!_cancelled) onError?.call(error);
    } finally {
      _finished = true;
      _client.close();
      _signalDataAvailable();
      if (!_ready.isCompleted) _ready.complete(false);
      if (!_done.isCompleted) _done.complete();
    }
  }

  (int, int)? _parseContentRange(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^bytes\s+(\d+)-\d+/(\d+)$').firstMatch(value.trim());
    if (match == null) return null;
    final start = int.tryParse(match.group(1)!);
    final total = int.tryParse(match.group(2)!);
    return start == null || total == null ? null : (start, total);
  }

  Future<void> serve(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }
      if (!await waitUntilReady()) {
        response.statusCode = HttpStatus.badGateway;
        await response.close();
        return;
      }

      final range = _parseRange(request.headers.value(HttpHeaders.rangeHeader));
      final total = _totalBytes;
      var start = range?.$1 ?? 0;
      int? end = range?.$2;
      if (total != null) {
        if (start >= total) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers
              .set(HttpHeaders.contentRangeHeader, 'bytes */$total');
          await response.close();
          return;
        }
        end = math.min(end ?? total - 1, total - 1);
      } else if (range != null) {
        start = 0;
        end = null;
      }

      response.bufferOutput = false;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (_contentType != null) {
        response.headers.set(HttpHeaders.contentTypeHeader, _contentType!);
      }
      if (range != null && total != null) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$total',
        );
      } else {
        response.statusCode = HttpStatus.ok;
      }
      if (end != null) response.contentLength = end - start + 1;

      if (request.method == 'HEAD') {
        await response.close();
        return;
      }

      await _waitForOffset(start);
      final reader = await _openCacheForReading();
      try {
        await reader.setPosition(start);
        var offset = start;
        while (!_cancelled) {
          final available = _downloadedBytes;
          final lastExclusive =
              end == null ? available : math.min(available, end + 1);
          if (offset < lastExclusive) {
            final count = math.min(64 * 1024, lastExclusive - offset);
            final bytes = await reader.read(count);
            if (bytes.isEmpty) {
              await _waitForOffset(offset);
              continue;
            }
            response.add(bytes);
            offset += bytes.length;
            continue;
          }
          if (end != null && offset > end) break;
          if (_finished) break;
          await _waitForOffset(offset);
        }
      } finally {
        await reader.close();
      }
      await response.close();
    } catch (_) {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  (int, int?)? _parseRange(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(value.trim());
    if (match == null) return null;
    final start = int.tryParse(match.group(1)!);
    final endText = match.group(2)!;
    final end = endText.isEmpty ? null : int.tryParse(endText);
    if (start == null || (end != null && end < start)) return null;
    return (start, end);
  }

  Future<RandomAccessFile> _openCacheForReading() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      for (final path in [finalPath, temporaryPath]) {
        try {
          final file = File(path);
          if (await file.exists()) return file.open(mode: FileMode.read);
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw const FileSystemException('Progressive audio cache is unavailable');
  }

  Future<void> _waitForOffset(int offset) async {
    while (!_cancelled && !_finished && _downloadedBytes <= offset) {
      final waiter = _dataAvailable ??= Completer<void>();
      await waiter.future;
    }
  }

  void _signalDataAvailable() {
    final waiter = _dataAvailable;
    _dataAvailable = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<void> cancel() async {
    if (_finished) return;
    _cancelled = true;
    _client.close();
    _signalDataAvailable();
    await _done.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
    try {
      final temporaryFile = File(temporaryPath);
      if (await temporaryFile.exists()) await temporaryFile.delete();
    } catch (_) {}
  }
}
