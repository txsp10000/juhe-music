import '../services/settings_service.dart';
import '../data/categories.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

class MusicApi {
  static const _base = 'https://music-api.gdstudio.xyz/api.php';
  static final _client = http.Client();
  static String _enc(String s) => Uri.encodeComponent(s);

  static Future<String> _httpGet(String url) async {
    final resp = await _client.get(Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0'});
    if (resp.statusCode >= 400) throw Exception('HTTP ${resp.statusCode}');
    return resp.body;
  }

  /// 通用重试：最多30次，间隔1秒
  static Future<T> _retry<T>(Future<T> Function() block) async {
    Exception? lastError;
    for (var attempt = 1; attempt <= 30; attempt++) {
      try {
        return await block();
      } on Exception catch (e) {
        lastError = e;
      }
      if (attempt < 30) await Future.delayed(const Duration(seconds: 1));
    }
    throw lastError ?? Exception('重试30次后仍失败');
  }

  /// 搜索歌曲（返回原始响应体，用于错误展示）
  static Future<SearchRawResult> searchRaw(String keyword, {int num = 20, int page = 1}) async {
    final encoded = _enc(keyword);
    var songs = <Song>[];
    var rawBody = '';
    for (var attempt = 1; attempt <= 30; attempt++) {
      try {
        final url = '$_base?types=search&source=netease&name=$encoded&count=$num&pages=$page';
        rawBody = await _httpGet(url);
        final list = jsonDecode(rawBody);
        if (list is List) {
          songs = list
              .whereType<Map<String, dynamic>>()
              .map((item) => Song.fromApiJson(item))
              .where((s) => s.id.isNotEmpty)
              .toList();
          if (songs.isNotEmpty) break;
        }
      } catch (_) {}
      if (attempt < 30) await Future.delayed(const Duration(seconds: 1));
    }
    return SearchRawResult(songs.take(num).toList(), rawBody);
  }

  /// 获取歌单（网易云歌单ID，返回真实歌单歌曲列表）
  static Future<List<Song>> getPlaylist(String id) async {
    for (var attempt = 1; attempt <= 30; attempt++) {
      try {
        final url = '$_base?types=playlist&id=${_enc(id)}';
        final body = await _httpGet(url);
        final json = jsonDecode(body);
        if (json is Map && json['code'] == 200) {
          final tracks = json['playlist']?['tracks'];
          if (tracks is List) {
            final songs = tracks
                .whereType<Map<String, dynamic>>()
                .map((t) {
                  final ar = t['ar'] as List? ?? [];
                  final singer = ar
                      .map((a) => a['name']?.toString() ?? '')
                      .where((n) => n.isNotEmpty)
                      .join(' / ');
                  final al = t['al'] as Map<String, dynamic>? ?? {};
                  final dt = t['dt'];
                  final sid = t['id']?.toString() ?? '';
                  return Song(
                    id: sid,
                    name: t['name'] ?? '未知歌曲',
                    singer: singer.isEmpty ? '未知歌手' : singer,
                    album: al['name'] ?? '',
                    source: 'netease',
                    picId: al['pic_str']?.toString() ?? '',
                    lyricId: sid,
                    duration: dt is int ? dt ~/ 1000 : 0,
                  );
                })
                .where((s) => s.id.isNotEmpty)
                .toList();
            if (songs.isNotEmpty) return songs;
          }
        }
      } catch (_) {}
      if (attempt < 30) await Future.delayed(const Duration(seconds: 1));
    }
    return [];
  }

  /// 获取歌单基本信息（名称 + 封面URL，每次启动从网络刷新）
  static final Map<String, PlaylistInfo> _playlistInfoCache = {};

  static Future<PlaylistInfo?> getPlaylistInfo(String id) async {
    if (_playlistInfoCache.containsKey(id)) return _playlistInfoCache[id];
    try {
      final url = '$_base?types=playlist&id=${_enc(id)}';
      final body = await _httpGet(url);
      final json = jsonDecode(body);
      if (json is Map && json['code'] == 200) {
        final playlist = json['playlist'] as Map<String, dynamic>? ?? {};
        final name = playlist['name'] ?? id;
        final cover = playlist['coverImgUrl']?.toString() ?? '';
        final info = PlaylistInfo(name.toString(), id, coverUrl: cover);
        _playlistInfoCache[id] = info;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('playlist_name_$id', name.toString());
        await prefs.setString('playlist_cover_$id', cover);
        return info;
      }
    } catch (_) {}
    // 网络失败时用本地缓存兜底
    final prefs = await SharedPreferences.getInstance();
    final cachedName = prefs.getString('playlist_name_$id');
    final cachedCover = prefs.getString('playlist_cover_$id');
    if (cachedName != null) {
      final info = PlaylistInfo(cachedName, id, coverUrl: cachedCover ?? '');
      _playlistInfoCache[id] = info;
      return info;
    }
    return null;
  }

  /// 获取播放URL（999=24bit FLAC无损，最多重试30次）
  static Future<String> getPlayUrl(String trackId) async {
    return _retry(() async {
      final br = SettingsService().quality.br;
      final url = '$_base?types=url&source=netease&id=${_enc(trackId)}&br=$br';
      final body = await _httpGet(url);
      final json = jsonDecode(body);
      final u = json['url'] as String?;
      if (u == null || u.isEmpty) throw Exception('播放地址为空');
      return u;
    });
  }

  /// 获取歌词（最多重试30次，空结果也重试）
  static Future<String> getLyric(String lyricId) async {
    try {
      return await _retry(() async {
        final url = '$_base?types=lyric&source=netease&id=${_enc(lyricId)}';
        final body = await _httpGet(url);
        final json = jsonDecode(body);
        final lyric = json['lyric'] as String? ?? '';
        if (lyric.trim().isEmpty) throw Exception('歌词为空');
        return lyric;
      });
    } catch (_) {
      return '';
    }
  }

  /// 获取专辑封面URL（最多重试30次，空结果也重试）
  static Future<String> getCover(String picId) async {
    try {
      return await _retry(() async {
        final url = '$_base?types=pic&source=netease&id=${_enc(picId)}&size=500';
        final body = await _httpGet(url);
        final json = jsonDecode(body);
        final u = json['url'] as String?;
        if (u == null || u.isEmpty) throw Exception('封面为空');
        return u;
      });
    } catch (_) {
      return '';
    }
  }

  /// 批量获取封面（并发请求）
  static Future<Map<String, String>> getCovers(List<String> picIds) async {
    final futures = picIds.map((id) async {
      try {
        return MapEntry(id, await getCover(id));
      } catch (_) {
        return MapEntry(id, '');
      }
    });
    final entries = await Future.wait(futures);
    return Map.fromEntries(entries);
  }
}

/// 搜索原始结果包装
class SearchRawResult {
  final List<Song> songs;
  final String rawBody;
  SearchRawResult(this.songs, this.rawBody);
}
