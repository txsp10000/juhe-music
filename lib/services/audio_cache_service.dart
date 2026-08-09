import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../utils/retry_helper.dart';
import 'settings_service.dart';

class AudioCacheService {
  static final AudioCacheService _instance = AudioCacheService._();
  factory AudioCacheService() => _instance;
  AudioCacheService._();

  static final _client = http.Client();
  Directory? _cacheDir;

  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${docDir.path}/audio_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  Future<void> cleanupIncomplete() async {
    try {
      final dir = await _getCacheDir();
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.tmp')) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  Future<int> getCacheSizeBytes() async {
    try {
      final dir = await _getCacheDir();
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearCache() async {
    try {
      final dir = await _getCacheDir();
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    } catch (_) {}
  }

  Future<void> migrateOldFiles() async {
    try {
      final dir = await _getCacheDir();
      if (!await dir.exists()) return;
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && !entity.path.endsWith('.tmp')) {
          files.add(entity);
        }
      }
      for (final file in files) {
        final name = file.path.split('/').last.split('\\').last;
        if (!RegExp(r'_\d+\.[a-z0-9]+$').hasMatch(name)) {
          final dotIdx = name.lastIndexOf('.');
          if (dotIdx > 0) {
            final baseName = name.substring(0, dotIdx);
            final ext = name.substring(dotIdx);
            await file
                .rename(file.path.replaceAll(name, '${baseName}_999$ext'));
          }
        }
      }
    } catch (_) {}
  }

  Future<String> getFilePath(String songId, String url, int br) async {
    final dir = await _getCacheDir();
    final ext = _extractExt(url);
    return '${dir.path}/${songId}_$br.$ext';
  }

  Future<String?> findCachedFile(String songId, {int? requestedBr}) async {
    final dir = await _getCacheDir();
    if (!await dir.exists()) return null;
    final prefix = '${songId}_';
    final br = requestedBr ?? SettingsService().quality.br;

    String? bestPath;
    var bestBitrate = -1;

    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.split('/').last.split('\\').last;
        if (name.endsWith('.tmp') || !name.startsWith(prefix)) continue;
        if (await entity.length() <= 0) continue;
        final afterPrefix = name.substring(prefix.length);
        final dotIdx = afterPrefix.indexOf('.');
        if (dotIdx <= 0) continue;
        final fileBr = int.tryParse(afterPrefix.substring(0, dotIdx)) ?? 0;
        if (fileBr >= br && (bestBitrate < br || fileBr < bestBitrate)) {
          bestBitrate = fileBr;
          bestPath = entity.path;
        }
      }
    } catch (_) {}

    if (bestPath != null) return bestPath;
    return null;
  }

  /// Returns the best complete local copy without waiting for any network API.
  Future<String?> findBestCachedFile(String songId) async {
    final dir = await _getCacheDir();
    if (!await dir.exists()) return null;
    final prefix = '${songId}_';
    String? bestPath;
    var bestBitrate = -1;
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.split('/').last.split('\\').last;
        if (name.endsWith('.tmp') || !name.startsWith(prefix)) continue;
        if (await entity.length() <= 0) continue;
        final suffix = name.substring(prefix.length);
        final dotIndex = suffix.indexOf('.');
        if (dotIndex <= 0) continue;
        final bitrate = int.tryParse(suffix.substring(0, dotIndex)) ?? 0;
        if (bitrate > bestBitrate) {
          bestBitrate = bitrate;
          bestPath = entity.path;
        }
      }
    } catch (_) {}
    return bestPath;
  }

  Future<void> _deleteAllForSong(String songId, {String? exceptPath}) async {
    final dir = await _getCacheDir();
    if (!await dir.exists()) return;
    final prefix = '${songId}_';
    final normalizedExceptPath =
        exceptPath == null ? null : _normalizePath(exceptPath);
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.path.split('/').last.split('\\').last;
          final isExceptedFile = normalizedExceptPath != null &&
              _normalizePath(entity.path) == normalizedExceptPath;
          if (name.startsWith(prefix) &&
              !name.endsWith('.tmp') &&
              !isExceptedFile) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  String _normalizePath(String path) =>
      File(path).absolute.path.replaceAll('\\', '/').toLowerCase();

  Future<void> commitDownloadedFile(
    String songId,
    String temporaryPath,
    String finalPath,
  ) async {
    final temporaryFile = File(temporaryPath);
    if (!await temporaryFile.exists() || await temporaryFile.length() <= 0) {
      throw const FileSystemException('Downloaded audio file is empty');
    }
    final finalFile = File(finalPath);
    if (await finalFile.exists()) await finalFile.delete();
    await temporaryFile.rename(finalPath);
    await _deleteAllForSong(songId, exceptPath: finalPath);
  }

  String _extractExt(String? url) {
    if (url == null || url.isEmpty) return 'mp3';
    final uri = Uri.tryParse(url);
    if (uri == null) return 'mp3';
    final path = uri.path.toLowerCase();
    if (path.endsWith('.flac')) return 'flac';
    if (path.endsWith('.m4a')) return 'm4a';
    if (path.endsWith('.aac')) return 'aac';
    if (path.endsWith('.wav')) return 'wav';
    if (path.endsWith('.ogg')) return 'ogg';
    return 'mp3';
  }

  Future<String?> download(
    String songId,
    String url, {
    void Function(double progress)? onProgress,
    int? br,
  }) async {
    final quality = br ?? SettingsService().quality.br;
    String path;
    File tmpFile;

    try {
      path = await getFilePath(songId, url, quality);
      final file = File(path);
      if (await file.exists() && await file.length() > 0) {
        onProgress?.call(1.0);
        return path;
      }
      tmpFile = File('$path.tmp');
    } catch (_) {
      return null;
    }

    try {
      return await RetryHelper.run(() async {
        if (await tmpFile.exists()) await tmpFile.delete();

        final request = http.Request('GET', Uri.parse(url));
        request.headers['User-Agent'] = 'Mozilla/5.0';
        final response = await _client.send(request);
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }

        final totalBytes = response.contentLength ?? 0;
        var receivedBytes = 0;
        final sink = tmpFile.openWrite();
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            receivedBytes += chunk.length;
            if (totalBytes > 0) {
              onProgress?.call((receivedBytes / totalBytes).clamp(0.0, 1.0));
            }
          }
        } finally {
          await sink.close();
        }

        if (await tmpFile.length() <= 0) throw Exception('下载文件为空');
        if (totalBytes > 0 && receivedBytes < totalBytes) {
          throw Exception('下载未完成');
        }

        await tmpFile.rename(path);
        await _deleteAllForSong(songId, exceptPath: path);
        onProgress?.call(1.0);
        return path;
      });
    } catch (_) {
      try {
        if (await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {}
      return null;
    }
  }
}
