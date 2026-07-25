import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class AudioCacheService {
  static final AudioCacheService _instance = AudioCacheService._();
  factory AudioCacheService() => _instance;
  AudioCacheService._();

  static final _client = http.Client();
  static const _channel = MethodChannel('com.miaomiao.music/converter');
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

  /// 获取 MP3 缓存路径
  Future<String> _getMp3Path(String songId) async {
    final dir = await _getCacheDir();
    return '${dir.path}/$songId.mp3';
  }

  /// 获取 WAV 缓存路径（用于精确 seek 播放）
  Future<String> getWavPath(String songId) async {
    final dir = await _getCacheDir();
    return '${dir.path}/$songId.wav';
  }

  /// 检查 WAV 是否已缓存
  Future<bool> isCached(String songId) async {
    final path = await getWavPath(songId);
    return File(path).exists();
  }

  /// 下载 MP3 并转为 WAV，返回 WAV 路径
  /// 返回 null 表示失败
  Future<String?> downloadAndConvert(String songId, String url) async {
    try {
      final wavPath = await getWavPath(songId);

      // WAV 已缓存，直接返回
      if (await File(wavPath).exists()) return wavPath;

      // 1. 下载 MP3
      final mp3Path = await _getMp3Path(songId);
      final mp3File = File(mp3Path);
      if (!await mp3File.exists()) {
        final response = await _client.get(
          Uri.parse(url),
          headers: {'User-Agent': 'Mozilla/5.0'},
        );
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          return null;
        }
        await mp3File.writeAsBytes(response.bodyBytes);
      }

      // 2. 调用原生平台通道转 WAV（AVAssetExportSession 帧精准）
      try {
        await _channel.invokeMethod('mp3ToWav', {
          'input': mp3Path,
          'output': wavPath,
        });
      } catch (_) {
        // 转换失败时回退用 MP3
        return mp3Path;
      }

      // 3. 转换成功后删除 MP3 节省空间
      try { await mp3File.delete(); } catch (_) {}

      return wavPath;
    } catch (_) {
      return null;
    }
  }

  /// 删除指定音频缓存
  Future<void> remove(String songId) async {
    try {
      final wavPath = await getWavPath(songId);
      final wavFile = File(wavPath);
      if (await wavFile.exists()) await wavFile.delete();

      final mp3Path = await _getMp3Path(songId);
      final mp3File = File(mp3Path);
      if (await mp3File.exists()) await mp3File.delete();
    } catch (_) {}
  }
}
