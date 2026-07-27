import 'package:flutter/services.dart';
import '../models/song.dart';
import 'player_service.dart';
import 'favorites_service.dart';
import 'diag_service.dart';

class CarPlayService {
  static const _channel = MethodChannel('com.miaomiao.music/carplay');
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;

    DiagService.log('Dart', 'CarPlayService.init 已注册 handler');

    _channel.setMethodCallHandler((call) async {
      DiagService.log('Dart', '收到调用: ${call.method}');
      switch (call.method) {
        case 'getPlaylist':
          final list = _getPlaylist();
          DiagService.log('Dart', 'getPlaylist 返回 ${list.length} 首');
          return list;
        case 'getFavorites':
          final favs = await _getFavorites();
          DiagService.log('Dart', 'getFavorites 返回 ${favs.length} 首');
          return favs;
        case 'playAtIndex':
          final index = call.arguments as int;
          PlayerService().playAt(index);
          return null;
        case 'playFavorite':
          final index = call.arguments as int;
          await _playFavorite(index);
          return null;
        case 'getCurrentSongId':
          return PlayerService().currentSong?.id ?? '';
        default:
          return null;
      }
    });
  }

  static List<Map<String, dynamic>> _getPlaylist() {
    final ps = PlayerService();
    return ps.playlist.map((s) => {
      'name': s.name,
      'singer': s.singer,
      'album': s.album,
      'cover': s.cover,
      'id': s.id,
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> _getFavorites() async {
    final songs = await FavoritesService.load();
    return songs.map((s) => {
      'name': s.name,
      'singer': s.singer,
      'album': s.album,
      'cover': s.cover,
      'id': s.id,
    }).toList();
  }

  static Future<void> _playFavorite(int index) async {
    final songs = await FavoritesService.load();
    if (index < 0 || index >= songs.length) return;
    final ps = PlayerService();
    ps.playlist.clear();
    ps.playlist.addAll(songs);
    ps.playAt(index);
  }
}
