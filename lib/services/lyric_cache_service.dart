import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LyricCacheService {
  static final LyricCacheService _instance = LyricCacheService._();
  factory LyricCacheService() => _instance;
  LyricCacheService._();

  Directory? _cacheDir;

  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${docDir.path}/lyric_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  /// 获取歌词缓存文件路径
  Future<File> _getFile(String lyricId) async {
    final dir = await _getCacheDir();
    return File('${dir.path}/$lyricId.lrc');
  }

  /// 从本地缓存读取歌词，未缓存返回 null
  Future<String?> load(String lyricId) async {
    try {
      final file = await _getFile(lyricId);
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (_) {}
    return null;
  }

  /// 将歌词保存到本地缓存
  Future<void> save(String lyricId, String lyric) async {
    try {
      final file = await _getFile(lyricId);
      await file.writeAsString(lyric);
    } catch (_) {}
  }
}
