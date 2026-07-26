import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

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

  Future<String> getFilePath(String songId, [String? url]) async {
    final dir = await _getCacheDir();
    final ext = _extractExt(url);
    return '${dir.path}/$songId.$ext';
  }

  /// Find any cached audio file for this songId regardless of extension
  /// Only returns files that are fully downloaded (not .tmp files)
  Future<String?> findCachedFile(String songId) async {
    final dir = await _getCacheDir();
    if (!await dir.exists()) return null;
    final prefix = '$songId.';
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.path.split('/').last.split('\\').last;
          // Skip temporary download files
          if (name.endsWith('.tmp')) continue;
          if (name.startsWith(prefix)) {
            if (await entity.length() > 0) {
              return entity.path;
            }
          }
        }
      }
    } catch (_) {}
    return null;
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

  Future<bool> isCached(String songId, [String? url]) async {
    final path = await getFilePath(songId, url);
    return File(path).exists();
  }

  /// Download with progress callback. Returns local file path on success.
  /// Uses a temporary file during download; only renames to final path on complete.
  Future<String?> download(
    String songId,
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final path = await getFilePath(songId, url);
      final file = File(path);

      // Already fully cached
      if (await file.exists() && await file.length() > 0) {
        onProgress?.call(1.0);
        return path;
      }

      final dir = await _getCacheDir();
      final oldMp3 = File('${dir.path}/$songId.mp3');
      if (!path.endsWith('.mp3') && await oldMp3.exists()) {
        await oldMp3.delete();
      }

      // Download to a temporary file first
      final tmpPath = '$path.tmp';
      final tmpFile = File(tmpPath);

      // Clean up any previous incomplete download
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }

      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = 'Mozilla/5.0';
      final response = await _client.send(request);

      if (response.statusCode == 200) {
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

        // Only rename to final path if download completed fully
        if (await tmpFile.length() > 0) {
          // If totalBytes was known, verify we got everything
          if (totalBytes > 0 && receivedBytes < totalBytes) {
            // Incomplete download, delete tmp
            await tmpFile.delete();
            return null;
          }
          await tmpFile.rename(path);
          onProgress?.call(1.0);
          return path;
        }
        await tmpFile.delete();
      }
    } catch (_) {
      // Clean up tmp file on any error
      try {
        final path = await getFilePath(songId, url);
        final tmpFile = File('$path.tmp');
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
    }
    return null;
  }
}