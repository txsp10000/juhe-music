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

  /// 获取音频缓存文件路径
  Future<String> getFilePath(String songId, [String? url]) async {
    final dir = await _getCacheDir();
    final ext = _extractExt(url);
    return '${dir.path}/$songId.$ext';
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

  /// 检查音频是否已缓存
  Future<bool> isCached(String songId, [String? url]) async {
    final path = await getFilePath(songId, url);
    return File(path).exists();
  }

  /// 下载音频到本地缓存，返回本地文件路径
  /// 已缓存则直接返回，未缓存则下载
  Future<String?> download(String songId, String url) async {
    try {
      final path = await getFilePath(songId, url);
      final file = File(path);

      if (await file.exists()) return path;

      final dir = await _getCacheDir();
      final oldMp3 = File('${dir.path}/$songId.mp3');
      if (!path.endsWith('.mp3') && await oldMp3.exists()) {
        await oldMp3.delete();
      }

      final response = await _client.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0'},
      );

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(response.bodyBytes);
        return path;
      }
    } catch (_) {}
    return null;
  }

}
