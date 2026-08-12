import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../utils/retry_helper.dart';
import 'cenc_m4a_decryptor.dart';
import 'settings_service.dart';

enum AudioCacheFailureStage { setup, download, decrypt, cacheWrite }

class AudioCacheResult {
  final String? path;
  final AudioCacheFailureStage? failureStage;

  const AudioCacheResult.success(this.path) : failureStage = null;
  const AudioCacheResult.failure(this.failureStage) : path = null;
}

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
      await _migrateLegacyMp4Files(dir);
    } catch (_) {}
  }

  Future<void> _migrateLegacyMp4Files(Directory dir) async {
    await for (final entity in dir.list()) {
      if (entity is! File || entity.path.endsWith('.tmp')) continue;
      final name = entity.path.split('/').last.split('\\').last;
      if (!RegExp(r'_\d+\.mp3$', caseSensitive: false).hasMatch(name)) {
        continue;
      }
      final target = File(entity.path
          .replaceFirst(RegExp(r'\.mp3$', caseSensitive: false), '.m4a'));
      if (await target.exists()) {
        await entity.delete();
      } else {
        await entity.rename(target.path);
      }
    }
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
    // Encrypted CDN downloads are M4A and become standard M4A after decrypting.
    return 'm4a';
  }

  Future<AudioCacheResult> download(
    String songId,
    String downloadUrl, {
    void Function(double progress)? onProgress,
    void Function()? onPreparing,
    int? br,
    String? backupUrl,
    String? aesKeyHex,
  }) async {
    final quality = br ?? SettingsService().quality.br;
    String path;
    File tmpFile;

    try {
      path = await getFilePath(songId, downloadUrl, quality);
      final file = File(path);
      if (await file.exists() && await file.length() > 0) {
        onProgress?.call(1.0);
        return AudioCacheResult.success(path);
      }
      tmpFile = File('$path.tmp');
    } catch (error, stackTrace) {
      await _logDiagnostic('Audio cache setup failed: $error\n$stackTrace');
      return const AudioCacheResult.failure(AudioCacheFailureStage.setup);
    }

    try {
      final key = aesKeyHex?.trim() ?? '';
      if (key.isEmpty) {
        await _logDiagnostic('Audio decrypt setup failed: AES key is empty');
        return const AudioCacheResult.failure(AudioCacheFailureStage.decrypt);
      }
      final encryptedFile = File('$path.encrypted.tmp');
      final urls = [downloadUrl, backupUrl?.trim() ?? '']
          .where((url) => url.isNotEmpty)
          .toSet();
      var downloaded = false;
      for (final url in urls) {
        try {
          await RetryHelper.run(
            () => _downloadEncryptedFile(
              url,
              encryptedFile,
              onProgress: onProgress,
            ),
            attempts: 3,
            delay: const Duration(seconds: 1),
          );
          downloaded = true;
          break;
        } catch (error, stackTrace) {
          developer.log(
            'Audio download failed from ${Uri.tryParse(url)?.host ?? 'unknown host'}',
            name: 'AudioCacheService',
            error: error,
            stackTrace: stackTrace,
          );
          await _logDiagnostic(
            'Audio download failed: host=${Uri.tryParse(url)?.host ?? 'unknown'}, '
            'error=$error\n$stackTrace',
          );
          try {
            if (await encryptedFile.exists()) await encryptedFile.delete();
          } catch (_) {}
        }
      }
      if (!downloaded) {
        return const AudioCacheResult.failure(AudioCacheFailureStage.download);
      }

      try {
        onPreparing?.call();
        final decryptStats = await _decryptAudioInIsolate(
          encryptedFile.path,
          tmpFile.path,
          key,
        );
        if (decryptStats.outputBytes <= 0) {
          throw const FileSystemException('Decrypted audio file is empty');
        }
        await _logDiagnostic(
          'Audio decrypt completed: inputBytes=${decryptStats.inputBytes}, '
          'outputBytes=${decryptStats.outputBytes}, readMs=${decryptStats.readMs}, '
          'decryptMs=${decryptStats.decryptMs}, writeMs=${decryptStats.writeMs}',
          isError: false,
        );
        try {
          await tmpFile.rename(path);
        } catch (error) {
          throw _AudioCacheWriteException(error);
        }
        unawaited(_cleanupCommittedDownload(
          encryptedFile,
          songId,
          path,
        ));
        return AudioCacheResult.success(path);
      } catch (error, stackTrace) {
        final encryptedLength = await _safeLength(encryptedFile);
        final fileSummary = await _describeMp4(encryptedFile);
        final stage = error is _AudioCacheWriteException
            ? AudioCacheFailureStage.cacheWrite
            : AudioCacheFailureStage.decrypt;
        developer.log(
          'Audio decrypt/cache failed',
          name: 'AudioCacheService',
          error: error,
          stackTrace: stackTrace,
        );
        await _logDiagnostic(
          'Audio ${stage.name} failed: error=$error, '
          'encryptedBytes=$encryptedLength, keyHexLength=${key.length}, '
          'file=$fileSummary\n$stackTrace',
        );
        try {
          if (await tmpFile.exists()) await tmpFile.delete();
        } catch (_) {}
        return AudioCacheResult.failure(stage);
      }
    } catch (error, stackTrace) {
      developer.log(
        'Audio cache setup failed',
        name: 'AudioCacheService',
        error: error,
        stackTrace: stackTrace,
      );
      await _logDiagnostic('Audio cache setup failed: $error\n$stackTrace');
      try {
        if (await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {}
      return const AudioCacheResult.failure(AudioCacheFailureStage.setup);
    }
  }

  Future<void> _cleanupCommittedDownload(
    File encryptedFile,
    String songId,
    String path,
  ) async {
    try {
      if (await encryptedFile.exists()) await encryptedFile.delete();
      await _deleteAllForSong(songId, exceptPath: path);
    } catch (_) {}
  }

  Future<void> _downloadEncryptedFile(
    String url,
    File target, {
    void Function(double progress)? onProgress,
  }) async {
    if (await target.exists()) await target.delete();
    final request = http.Request('GET', Uri.parse(url));
    request.headers['User-Agent'] = 'Mozilla/5.0';
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength ?? 0;
    var receivedBytes = 0;
    final sink = target.openWrite();
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

    if (await target.length() <= 0) throw const FileSystemException('下载文件为空');
    if (totalBytes > 0 && receivedBytes < totalBytes) {
      throw const FileSystemException('下载未完成');
    }
  }
}

class _AudioCacheWriteException implements Exception {
  final Object cause;
  const _AudioCacheWriteException(this.cause);

  @override
  String toString() => 'Unable to commit decrypted audio: $cause';
}

const _diagnosticsChannel = MethodChannel('com.music/diagnostics');

Future<void> _logDiagnostic(String message, {bool isError = true}) async {
  try {
    await _diagnosticsChannel.invokeMethod<void>('log', {
      'message': message,
      'level': isError ? 'error' : 'info',
    });
  } catch (_) {}
}

Future<int> _safeLength(File file) async {
  try {
    return await file.length();
  } catch (_) {
    return -1;
  }
}

Future<String> _describeMp4(File file) async {
  try {
    final handle = await file.open();
    try {
      final length = await handle.length();
      final bytes = await handle.read(length.clamp(0, 4096));
      final header = bytes
          .take(32)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      final boxes = <String>[];
      var offset = 0;
      while (offset + 8 <= bytes.length && boxes.length < 12) {
        final size = _readDiagnosticUint32(bytes, offset);
        final type =
            String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
        boxes.add('$type:$size');
        if (size < 8 || offset + size > length) break;
        offset += size;
        if (offset >= bytes.length) break;
      }
      return 'header=$header, topBoxes=${boxes.join(',')}';
    } finally {
      await handle.close();
    }
  } catch (error) {
    return 'unreadable($error)';
  }
}

int _readDiagnosticUint32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

class _AudioDecryptStats {
  final int inputBytes;
  final int outputBytes;
  final int readMs;
  final int decryptMs;
  final int writeMs;

  const _AudioDecryptStats(
    this.inputBytes,
    this.outputBytes,
    this.readMs,
    this.decryptMs,
    this.writeMs,
  );
}

Future<_AudioDecryptStats> _decryptAudioInIsolate(
  String encryptedPath,
  String outputPath,
  String aesKeyHex,
) async {
  final responsePort = ReceivePort();
  final errorPort = ReceivePort();
  Isolate? isolate;
  try {
    final rootToken = ui.RootIsolateToken.instance;
    isolate = await Isolate.spawn<List<Object?>>(
      _decryptAudioIsolateEntry,
      <Object?>[
        responsePort.sendPort,
        encryptedPath,
        outputPath,
        aesKeyHex,
        rootToken,
      ],
      onError: errorPort.sendPort,
      errorsAreFatal: true,
    );
    final result = await Future.any<List<Object?>>([
      responsePort.first.then((value) => (value as List).cast<Object?>()),
      errorPort.first.then(
        (value) => <Object?>[false, 'Decrypt isolate error: $value', ''],
      ),
    ]).timeout(const Duration(minutes: 3));
    if (result.first == true) {
      return _AudioDecryptStats(
        result[1] as int,
        result[2] as int,
        result[3] as int,
        result[4] as int,
        result[5] as int,
      );
    }
    throw StateError('${result[1]}\n${result[2]}');
  } finally {
    responsePort.close();
    errorPort.close();
    isolate?.kill(priority: Isolate.immediate);
  }
}

void _decryptAudioIsolateEntry(List<Object?> message) async {
  final responsePort = message[0] as SendPort;
  try {
    final rootToken = message[4] as ui.RootIsolateToken?;
    final encryptedPath = message[1] as String;
    final outputPath = message[2] as String;
    final aesKeyHex = message[3] as String;
    _AudioDecryptStats stats;
    if ((Platform.isAndroid || Platform.isIOS) && rootToken != null) {
      try {
        stats = await _decryptAudioToFileNative(
          encryptedPath,
          outputPath,
          aesKeyHex,
          rootToken,
        );
      } catch (_) {
        stats = await _decryptAudioToFile(
          encryptedPath,
          outputPath,
          aesKeyHex,
        );
      }
    } else {
      stats = await _decryptAudioToFile(
        encryptedPath,
        outputPath,
        aesKeyHex,
      );
    }
    responsePort.send(<Object?>[
      true,
      stats.inputBytes,
      stats.outputBytes,
      stats.readMs,
      stats.decryptMs,
      stats.writeMs,
    ]);
  } catch (error, stackTrace) {
    responsePort
        .send(<Object?>[false, error.toString(), stackTrace.toString()]);
  }
}

Future<_AudioDecryptStats> _decryptAudioToFileNative(
  String encryptedPath,
  String outputPath,
  String aesKeyHex,
  ui.RootIsolateToken rootToken,
) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
  final readWatch = Stopwatch()..start();
  final encryptedBytes = await File(encryptedPath).readAsBytes();
  readWatch.stop();
  final prepareWatch = Stopwatch()..start();
  final plan = CencM4aDecryptor.prepareOwnedForNative(encryptedBytes);
  prepareWatch.stop();
  final writeWatch = Stopwatch()..start();
  await File(outputPath).writeAsBytes(plan.repairedEncrypted);
  writeWatch.stop();
  final nativeMs = await _diagnosticsChannel.invokeMethod<int>(
        'decryptAudioFile',
        <String, Object>{
          'path': outputPath,
          'keyHex': aesKeyHex,
          'sampleTable': plan.sampleTable,
        },
      ) ??
      0;
  return _AudioDecryptStats(
    encryptedBytes.length,
    plan.repairedEncrypted.length,
    readWatch.elapsedMilliseconds,
    prepareWatch.elapsedMilliseconds + nativeMs,
    writeWatch.elapsedMilliseconds,
  );
}

Future<_AudioDecryptStats> _decryptAudioToFile(
  String encryptedPath,
  String outputPath,
  String aesKeyHex,
) async {
  final readWatch = Stopwatch()..start();
  final encryptedBytes = await File(encryptedPath).readAsBytes();
  readWatch.stop();
  final decryptWatch = Stopwatch()..start();
  final decryptedBytes =
      CencM4aDecryptor.decryptOwned(encryptedBytes, aesKeyHex);
  decryptWatch.stop();
  final writeWatch = Stopwatch()..start();
  final output = File(outputPath);
  await output.writeAsBytes(decryptedBytes);
  writeWatch.stop();
  return _AudioDecryptStats(
    encryptedBytes.length,
    decryptedBytes.length,
    readWatch.elapsedMilliseconds,
    decryptWatch.elapsedMilliseconds,
    writeWatch.elapsedMilliseconds,
  );
}
