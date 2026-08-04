import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../utils/retry_helper.dart';
import 'settings_service.dart';

/// Quality tiers ordered from lowest to highest
const List<int> _qualityOrder = [128, 192, 320, 740, 999];

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

  /// Clean up any leftover .tmp files from interrupted downloads
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

  /// Migrate old-format files (songId.ext) to new format (songId_999.ext)
  /// Call once on startup
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
        // Old format: songId.ext (no underscore+number before ext)
        // New format: songId_br.ext
        if (!RegExp(r'_\d+\.[a-z0-9]+$').hasMatch(name)) {
          // It's old format, rename to _999 (assume old downloads were lossless)
          final dotIdx = name.lastIndexOf('.');
          if (dotIdx > 0) {
            final baseName = name.substring(0, dotIdx);
            final ext = name.substring(dotIdx);
            final newName = '${baseName}_999$ext';
            final newPath = file.path.replaceAll(name, newName);
            await file.rename(newPath);
          }
        }
      }
    } catch (_) {}
  }

  /// Build file path with quality: songId_br.ext
  Future<String> getFilePath(String songId, String url, int br) async {
    final dir = await _getCacheDir();
    final ext = _extractExt(url);
    return '${dir.path}/${songId}_$br.$ext';
  }

  /// Find the best cached file for this songId.
  /// Returns the path if a cached file exists with quality >= requested quality.
  /// If only lower quality exists, returns null (caller should re-download).
  Future<String?> findCachedFile(String songId, {int? requestedBr}) async {
    final dir = await _getCacheDir();
    if (!await dir.exists()) return null;
    final prefix = '${songId}_';
    final br = requestedBr ?? SettingsService().quality.br;

    String? bestPath;
    int bestBr = -1;

    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.path.split('/').last.split('\\').last;
          if (name.endsWith('.tmp')) continue;
          if (name.startsWith(prefix)) {
            if (await entity.length() > 0) {
              // Extract br from filename: songId_br.ext
              final afterPrefix = name.substring(prefix.length);
              final dotIdx = afterPrefix.indexOf('.');
              if (dotIdx > 0) {
                final brStr = afterPrefix.substring(0, dotIdx);
                final fileBr = int.tryParse(brStr) ?? 0;
                if (fileBr > bestBr) {
                  bestBr = fileBr;
                  bestPath = entity.path;
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    // If we have a file with quality >= requested, use it
    if (bestPath != null && bestBr >= br) {
      return bestPath;
    }

    // If we have a lower quality file and user wants higher, return null
    // (caller will download higher quality and we'll delete the old one)
    return null;
  }

  /// Delete all cached files for a songId (all qualities)
  Future<void> _deleteAllForSong(String songId, {String? exceptPath}) async {
    final dir = await _getCacheDir();
    if (!await dir.exists()) return;
    final prefix = '${songId}_';
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.path.split('/').last.split('\\').last;
          if (name.startsWith(prefix) &&
              !name.endsWith('.tmp') &&
              entity.path != exceptPath) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
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

  /// Download with progress callback. Returns local file path on success.
  /// Uses a temporary file during download; only renames to final path on complete.
  /// Deletes any existing lower-quality cache for this song.
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

      // Already fully cached at this quality
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
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }

        final request = http.Request('GET', Uri.parse(url));
        request.headers['User-Agent'] = 'Mozilla/5.0';
        final response = await _client.send(request);

        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }

        final totalBytes = response.contentLength ?? 0;
        int receivedBytes = 0;

        final sink = tmpFile.openWrite();
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            final progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
            onProgress?.call(progress);
          } else {
            final mbReceived = receivedBytes / (1024 * 1024);
            final estimatedProgress = (mbReceived / 15.0).clamp(0.0, 0.95);
            onProgress?.call(estimatedProgress);
          }
        }
        await sink.close();

        if (await tmpFile.length() <= 0) {
          throw Exception('下载文件为空');
        }
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
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
      return null;
    }
  }
}
