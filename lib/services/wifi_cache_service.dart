import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
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
  StreamSubscription? _connectivitySub;

  void init() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (_isWifiResult(result) && !_running) {
        _startCaching();
      }
    });
    // 启动时立即检测一次
    Connectivity().checkConnectivity().then((result) {
      if (_isWifiResult(result)) {
        _startCaching();
      }
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
  }

  bool _isWifiResult(dynamic result) {
    if (result is List) {
      return result.contains(ConnectivityResult.wifi);
    }
    return result == ConnectivityResult.wifi;
  }

  Future<bool> _isOnWifi() async {
    final result = await Connectivity().checkConnectivity();
    return _isWifiResult(result);
  }

  Future<void> _startCaching() async {
    if (_running) return;
    _running = true;

    try {
      final songs = await FavoritesService.load();
      final cache = AudioCacheService();
      final br = SettingsService().quality.br;

      for (final song in songs) {
        // 每首歌下载前重新检测是否还在WiFi
        if (!await _isOnWifi()) break;

        // 检查是否已缓存
        final cached = await cache.findCachedFile(song.id, requestedBr: br);
        if (cached != null) continue;

        // 获取播放地址并下载
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
