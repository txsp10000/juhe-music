import 'dart:async';
import 'dart:io';
import '../api/music_api.dart';
import '../models/song.dart';
import 'favorites_service.dart';
import 'audio_cache_service.dart';
import 'settings_service.dart';

/// WiFi下自动缓存收藏列表中未缓存的歌曲
class WifiCacheService {
  static final WifiCacheService _instance = WifiCacheService._();
  factory WifiCacheService() => _instance;
  WifiCacheService._();

  bool _running = false;
  Timer? _timer;

  void init() {
    // 启动后延迟5秒开始检测，之后每60秒检测一次
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _checkAndCache());
    Future.delayed(const Duration(seconds: 5), _checkAndCache);
  }

  void dispose() {
    _timer?.cancel();
  }

  Future<bool> _isOnWifi() async {
    try {
      final interfaces = await NetworkInterface.list();
      // iOS: en0 is WiFi interface
      return interfaces.any((i) => i.name == 'en0' && i.addresses.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkAndCache() async {
    if (_running) return;
    if (!await _isOnWifi()) return;
    _startCaching();
  }

  Future<void> _startCaching() async {
    if (_running) return;
    _running = true;

    try {
      final songs = await FavoritesService.load();
      final cache = AudioCacheService();
      final br = SettingsService().quality.br;

      for (final song in songs) {
        // Re-check WiFi before each download
        if (!await _isOnWifi()) break;

        // Check if already cached
        final cached = await cache.findCachedFile(song.id, requestedBr: br);
        if (cached != null) continue;

        // Get play URL and download
        try {
          final url = await MusicApi.getPlayUrl(song.id);
          if (url.isEmpty) continue;
          await cache.download(song.id, url, br: br);
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}

    _running = false;
  }
}
