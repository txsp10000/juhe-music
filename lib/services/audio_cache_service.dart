import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../utils/retry_helper.dart';
import 'app_environment.dart';
import 'settings_service.dart';

enum AudioCacheFailureStage { setup, download, cacheWrite }

class AudioCacheCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const _AudioCacheCancelledException();
  }
}

class AudioCacheResult {
  final String? path;
  final String? decryptionKey;
  final AudioCacheFailureStage? failureStage;
  final bool cancelled;

  const AudioCacheResult.success(this.path, {this.decryptionKey})
      : failureStage = null,
        cancelled = false;
  const AudioCacheResult.failure(this.failureStage)
      : path = null,
        decryptionKey = null,
        cancelled = false;
  const AudioCacheResult.cancelled()
      : path = null,
        decryptionKey = null,
        failureStage = null,
        cancelled = true;
}

class CachedAudioFile {
  final String path;
  final String decryptionKey;

  const CachedAudioFile(this.path, {required this.decryptionKey});
}

class AudioCacheService {
  static final AudioCacheService _instance = AudioCacheService._();
  factory AudioCacheService() => _instance;
  AudioCacheService._();

  static int _taskSequence = 0;
  static Future<void> _commitTail = Future<void>.value();
  final Map<AudioCacheCancellationToken, Completer<void>> _activeTasks = {};
  Future<void>? _clearFuture;
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
    if (isTvApp) return;
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

  Future<void> clearCache() {
    final activeClear = _clearFuture;
    if (activeClear != null) return activeClear;
    final completer = Completer<void>();
    _clearFuture = completer.future;
    unawaited(() async {
      try {
        final activeTasks = Map.of(_activeTasks);
        for (final token in activeTasks.keys) {
          token.cancel();
        }
        await Future.wait(activeTasks.values.map((task) => task.future));
        await _withCommitLock(() async {
          final dir = await _getCacheDir();
          if (await dir.exists()) await dir.delete(recursive: true);
          await dir.create(recursive: true);
        });
      } catch (_) {
      } finally {
        _clearFuture = null;
        completer.complete();
      }
    }());
    return completer.future;
  }

  Future<String> getFilePath(String songId, int br) async {
    final dir = await _getCacheDir();
    return '${dir.path}/${songId}_$br.encrypted.m4a';
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
        if (!_isEncryptedCacheName(name, prefix)) continue;
        if (await entity.length() <= 0) continue;
        if (await _readDecryptionKey(entity.path) == null) continue;
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
  Future<CachedAudioFile?> findBestCachedFile(String songId) async {
    final dir = await _getCacheDir();
    if (!await dir.exists()) return null;
    final prefix = '${songId}_';
    String? bestPath;
    String? bestKey;
    var bestBitrate = -1;
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.split('/').last.split('\\').last;
        if (!_isEncryptedCacheName(name, prefix)) continue;
        if (await entity.length() <= 0) continue;
        final decryptionKey = await _readDecryptionKey(entity.path);
        if (decryptionKey == null) continue;
        final suffix = name.substring(prefix.length);
        final dotIndex = suffix.indexOf('.');
        if (dotIndex <= 0) continue;
        final bitrate = int.tryParse(suffix.substring(0, dotIndex)) ?? 0;
        if (bitrate > bestBitrate) {
          bestBitrate = bitrate;
          bestPath = entity.path;
          bestKey = decryptionKey;
        }
      }
    } catch (_) {}
    if (bestPath == null || bestKey == null) return null;
    return CachedAudioFile(bestPath, decryptionKey: bestKey);
  }

  bool _isEncryptedCacheName(String name, String prefix) =>
      name.startsWith(prefix) &&
      RegExp(r'_\d+\.encrypted\.m4a$', caseSensitive: false).hasMatch(name);

  Future<String?> _readDecryptionKey(String path) async {
    try {
      final keyFile = File('$path.key');
      if (!await keyFile.exists()) return null;
      final key = (await keyFile.readAsString()).trim();
      return key.isEmpty ? null : key;
    } catch (_) {
      return null;
    }
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
          final normalizedPath = _normalizePath(entity.path);
          final isExceptedFile = normalizedExceptPath != null &&
              (normalizedPath == normalizedExceptPath ||
                  normalizedPath == '$normalizedExceptPath.key');
          final cacheName = name.endsWith('.key')
              ? name.substring(0, name.length - '.key'.length)
              : name;
          if (_isEncryptedCacheName(cacheName, prefix) &&
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

  Future<AudioCacheResult> download(
    String songId,
    String downloadUrl, {
    void Function(double progress)? onProgress,
    void Function()? onPreparing,
    int? br,
    String? backupUrl,
    String? aesKeyHex,
    AudioCacheCancellationToken? cancellationToken,
  }) async {
    final activeClear = _clearFuture;
    if (activeClear != null) await activeClear;
    final taskCancellation = AudioCacheCancellationToken();
    final taskDone = Completer<void>();
    _activeTasks[taskCancellation] = taskDone;
    if (cancellationToken != null) {
      unawaited(cancellationToken.whenCancelled.then((_) {
        taskCancellation.cancel();
      }));
    }
    try {
      return await _download(
        songId,
        downloadUrl,
        onProgress: onProgress,
        onPreparing: onPreparing,
        br: br,
        backupUrl: backupUrl,
        aesKeyHex: aesKeyHex,
        cancellationToken: taskCancellation,
      );
    } finally {
      _activeTasks.remove(taskCancellation);
      if (!taskDone.isCompleted) taskDone.complete();
    }
  }

  Future<AudioCacheResult> _download(
    String songId,
    String downloadUrl, {
    void Function(double progress)? onProgress,
    void Function()? onPreparing,
    int? br,
    String? backupUrl,
    String? aesKeyHex,
    required AudioCacheCancellationToken cancellationToken,
  }) async {
    final quality = br ?? SettingsService().quality.br;
    String path;
    File? encryptedFile;
    File? keyFile;

    try {
      cancellationToken.throwIfCancelled();
      path = await getFilePath(songId, quality);
      final file = File(path);
      final existingKey = await _readDecryptionKey(path);
      if (await file.exists() &&
          await file.length() > 0 &&
          existingKey != null) {
        onProgress?.call(1.0);
        return AudioCacheResult.success(path, decryptionKey: existingKey);
      }
      final taskId = ++_taskSequence;
      encryptedFile = File('$path.$taskId.tmp');
      keyFile = File('$path.$taskId.key.tmp');
    } on _AudioCacheCancelledException {
      return const AudioCacheResult.cancelled();
    } catch (_) {
      return const AudioCacheResult.failure(AudioCacheFailureStage.setup);
    }

    try {
      final key = aesKeyHex?.trim() ?? '';
      if (key.isEmpty) {
        return const AudioCacheResult.failure(AudioCacheFailureStage.setup);
      }
      final urls = [downloadUrl, backupUrl?.trim() ?? '']
          .where((url) => url.isNotEmpty)
          .toSet();
      var downloaded = false;
      for (final url in urls) {
        try {
          cancellationToken.throwIfCancelled();
          await RetryHelper.run(
            () => _downloadEncryptedFile(
              url,
              encryptedFile!,
              onProgress: onProgress,
              cancellationToken: cancellationToken,
            ),
            attempts: 3,
            delay: const Duration(seconds: 1),
            shouldRetry: (error) => error is! _AudioCacheCancelledException,
          );
          downloaded = true;
          break;
        } on _AudioCacheCancelledException {
          await _deleteIfExists(encryptedFile);
          return const AudioCacheResult.cancelled();
        } catch (_) {
          try {
            if (await encryptedFile.exists()) await encryptedFile.delete();
          } catch (_) {}
        }
      }
      if (!downloaded) {
        return const AudioCacheResult.failure(AudioCacheFailureStage.download);
      }

      final downloadedFile = encryptedFile;
      final pendingKeyFile = keyFile;
      try {
        cancellationToken.throwIfCancelled();
        onPreparing?.call();
        await pendingKeyFile.writeAsString(key, flush: true);
        cancellationToken.throwIfCancelled();
        final committed = await _withCommitLock(() async {
          cancellationToken.throwIfCancelled();
          final target = File(path);
          final targetKey = File('$path.key');
          final existingKey = await _readDecryptionKey(path);
          if (await target.exists() &&
              await target.length() > 0 &&
              existingKey != null) {
            await _deleteIfExists(downloadedFile);
            await _deleteIfExists(pendingKeyFile);
            return existingKey;
          }
          if (await target.exists()) await target.delete();
          if (await targetKey.exists()) await targetKey.delete();
          await downloadedFile.rename(path);
          try {
            await pendingKeyFile.rename(targetKey.path);
          } catch (error) {
            await _deleteIfExists(target);
            throw _AudioCacheWriteException(error);
          }
          if (!isTvApp) {
            await _deleteAllForSong(songId, exceptPath: path);
          }
          return key;
        });
        return AudioCacheResult.success(path, decryptionKey: committed);
      } on _AudioCacheCancelledException {
        await _deleteIfExists(downloadedFile);
        await _deleteIfExists(pendingKeyFile);
        return const AudioCacheResult.cancelled();
      } catch (_) {
        await _deleteIfExists(downloadedFile);
        await _deleteIfExists(pendingKeyFile);
        return const AudioCacheResult.failure(
            AudioCacheFailureStage.cacheWrite);
      }
    } on _AudioCacheCancelledException {
      await _deleteIfExists(encryptedFile);
      await _deleteIfExists(keyFile);
      return const AudioCacheResult.cancelled();
    } catch (_) {
      await _deleteIfExists(encryptedFile);
      await _deleteIfExists(keyFile);
      return const AudioCacheResult.failure(AudioCacheFailureStage.setup);
    }
  }

  Future<void> _downloadEncryptedFile(
    String url,
    File target, {
    void Function(double progress)? onProgress,
    AudioCacheCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    if (await target.exists()) await target.delete();
    final request = http.Request('GET', Uri.parse(url));
    request.headers['User-Agent'] = 'Mozilla/5.0';
    final client = http.Client();
    late final http.StreamedResponse response;
    try {
      response = await Future.any([
        client.send(request),
        if (cancellationToken != null)
          cancellationToken.whenCancelled.then<http.StreamedResponse>(
            (_) => throw const _AudioCacheCancelledException(),
          ),
      ]);
    } catch (_) {
      client.close();
      rethrow;
    }
    if (response.statusCode != 200) {
      client.close();
      throw Exception('HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength ?? 0;
    var receivedBytes = 0;
    final sink = target.openWrite();
    final downloadCompleter = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    try {
      subscription = response.stream.listen(
        (chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            onProgress?.call((receivedBytes / totalBytes).clamp(0.0, 1.0));
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!downloadCompleter.isCompleted) {
            downloadCompleter.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!downloadCompleter.isCompleted) downloadCompleter.complete();
        },
        cancelOnError: true,
      );
      await Future.any([
        downloadCompleter.future,
        if (cancellationToken != null)
          cancellationToken.whenCancelled.then<void>(
            (_) => throw const _AudioCacheCancelledException(),
          ),
      ]);
    } finally {
      await subscription.cancel();
      client.close();
      await sink.close();
    }

    if (await target.length() <= 0) throw const FileSystemException('下载文件为空');
    if (totalBytes > 0 && receivedBytes < totalBytes) {
      throw const FileSystemException('下载未完成');
    }
  }

  Future<bool> deleteCachedFile(String path) async {
    if (isTvApp) return false;
    return _withCommitLock(() async {
      await _deleteIfExists(File(path));
      await _deleteIfExists(File('$path.key'));
      return !await File(path).exists() && !await File('$path.key').exists();
    });
  }

  Future<T> _withCommitLock<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _commitTail = _commitTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class _AudioCacheCancelledException implements Exception {
  const _AudioCacheCancelledException();
}

Future<void> _deleteIfExists(File? file) async {
  if (file == null) return;
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

class _AudioCacheWriteException implements Exception {
  final Object cause;
  const _AudioCacheWriteException(this.cause);

  @override
  String toString() => 'Unable to commit encrypted audio cache: $cause';
}
