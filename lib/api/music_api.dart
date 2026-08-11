import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import '../utils/retry_helper.dart';

class MusicApi {
  static const _base = 'http://pc.w8a.cn:8787';
  static const _requestTimeout = Duration(seconds: 15);
  static final _client = http.Client();
  static final Map<String, Future<TrackDetails>> _trackRequests = {};
  static final Map<String, Future<StreamInfo>> _streamRequests = {};

  static Future<String> _httpGet(Uri uri) async {
    final response = await _client.get(uri,
        headers: {'User-Agent': 'SodaMusic'}).timeout(_requestTimeout);
    if (response.statusCode >= 400) {
      var message = 'HTTP ${response.statusCode}';
      try {
        final error = jsonDecode(response.body);
        if (error is Map && error['error'] != null) {
          message = error['error'].toString();
        }
      } catch (_) {}
      throw Exception(message);
    }
    return utf8.decode(response.bodyBytes);
  }

  static Future<T> _retry<T>(Future<T> Function() action) => RetryHelper.run(
        action,
        attempts: 3,
        delay: const Duration(seconds: 1),
      );

  static Future<SearchTracksResult> searchTracks(String keyword,
      {int cursor = 0}) {
    return _retry(() async {
      final uri = Uri.parse('$_base/search/tracks').replace(
        queryParameters: {'q': keyword, 'cursor': cursor.toString()},
      );
      final body = await _httpGet(uri);
      final decoded = jsonDecode(body);
      final groups = decoded is Map ? decoded['result_groups'] : null;
      final group = groups is List && groups.isNotEmpty ? groups.first : null;
      final data = group is Map ? group['data'] : null;
      if (data is! List) throw const FormatException('搜索响应格式无效');
      final songs = data
          .whereType<Map<String, dynamic>>()
          .map(Song.fromApiJson)
          .where((song) => song.id.isNotEmpty)
          .take(20)
          .toList();
      return SearchTracksResult(
        songs,
        nextCursor: group is Map ? group['next_cursor']?.toString() : null,
        hasMore: group is Map && group['has_more'] == true,
      );
    });
  }

  static Future<TrackDetails> getTrackDetails(String trackId) {
    return _trackRequests.putIfAbsent(trackId, () async {
      try {
        final uri = Uri.parse('$_base/track/${Uri.encodeComponent(trackId)}');
        final decoded = jsonDecode(await _retry(() => _httpGet(uri)));
        if (decoded is! Map || decoded['track'] is! Map) {
          throw const FormatException('单曲详情缺少 track');
        }
        final lyric = decoded['lyric'];
        return TrackDetails(
          song: Song.fromApiJson(
              Map<String, dynamic>.from(decoded['track'] as Map)),
          lyric: lyric is Map ? lyric['content']?.toString() ?? '' : '',
        );
      } catch (_) {
        _trackRequests.remove(trackId);
        rethrow;
      }
    });
  }

  static Future<SearchPlaylistsResult> searchPlaylists(String keyword,
      {int cursor = 0}) {
    return _retry(() async {
      final uri = Uri.parse('$_base/search/playlists').replace(
        queryParameters: {'q': keyword, 'cursor': cursor.toString()},
      );
      final decoded = jsonDecode(await _httpGet(uri));
      final groups = decoded is Map ? decoded['result_groups'] : null;
      final group = groups is List && groups.isNotEmpty ? groups.first : null;
      final data = group is Map ? group['data'] : null;
      if (data is! List) throw const FormatException('歌单搜索响应格式无效');
      final playlists = data
          .whereType<Map>()
          .map((item) {
            final entity = item['entity'];
            final playlist = entity is Map ? entity['playlist'] : null;
            return playlist is Map ? PlaylistInfo.fromApiJson(playlist) : null;
          })
          .whereType<PlaylistInfo>()
          .where((item) => item.id.isNotEmpty)
          .toList();
      return SearchPlaylistsResult(
        playlists,
        nextCursor: group is Map ? group['next_cursor']?.toString() : null,
        hasMore: group is Map && group['has_more'] == true,
      );
    });
  }

  static Future<PlaylistPage> getPlaylistPage(String playlistId,
      {int cursor = 0, int count = 20}) {
    return _retry(() async {
      final uri =
          Uri.parse('$_base/playlist/${Uri.encodeComponent(playlistId)}')
              .replace(queryParameters: {
        'cursor': cursor.toString(),
        'count': count.toString(),
      });
      final decoded = jsonDecode(await _httpGet(uri));
      final resources = decoded is Map ? decoded['media_resources'] : null;
      if (resources is! List) throw const FormatException('歌单歌曲响应格式无效');
      final songs = _songsFromResources(resources);
      final map = decoded is Map ? decoded : const <String, dynamic>{};
      final playlist = map['playlist'] is Map
          ? PlaylistInfo.fromApiJson(map['playlist'] as Map)
          : null;
      return PlaylistPage(
        songs,
        playlist: playlist,
        nextCursor: map['next_cursor']?.toString(),
        hasMore: map['has_more'] == true,
      );
    });
  }

  static Future<List<Song>> getPlaylistTracks(String playlistId) async {
    final songs = <Song>[];
    var cursor = 0;
    var pageCount = 0;
    while (true) {
      final page = await getPlaylistPage(playlistId, cursor: cursor, count: 50);
      songs.addAll(page.songs);
      pageCount++;
      final next = int.tryParse(page.nextCursor ?? '');
      if (!page.hasMore || next == null || next <= cursor || pageCount >= 40) {
        break;
      }
      cursor = next;
    }
    return songs;
  }

  /// Loads a fresh recommendation batch for a listening mode.
  ///
  /// Service scene modes use [sceneModeId]. The two client-only modes use
  /// [preference] (`familiar` or `fresh`). Exactly one is required.
  static Future<List<Song>> getModeTracks({
    int? sceneModeId,
    String? preference,
  }) async {
    final normalizedPreference = preference?.trim();
    final hasSceneModeId = sceneModeId != null;
    final hasPreference =
        normalizedPreference != null && normalizedPreference.isNotEmpty;
    if (hasSceneModeId == hasPreference) {
      throw ArgumentError(
        '常用模式歌曲请求必须且只能提供 sceneModeId 或 preference',
      );
    }

    final uri = Uri.parse('$_base/feed/mode/tracks').replace(
      queryParameters: hasSceneModeId
          ? {'scene_mode_id': sceneModeId.toString()}
          : {'preference': normalizedPreference!},
    );
    final decoded = jsonDecode(await _retry(() => _httpGet(uri)));
    final items = decoded is Map ? decoded['items'] : null;
    if (items is! List) throw const FormatException('模式歌曲响应格式无效');
    return _songsFromResources(items);
  }

  static List<Song> _songsFromResources(List resources) {
    return resources
        .whereType<Map>()
        .map((item) {
          final entity = item['entity'];
          final wrapper = entity is Map ? entity['track_wrapper'] : null;
          final track = wrapper is Map ? wrapper['track'] : entity;
          return track is Map
              ? Song.fromApiJson(Map<String, dynamic>.from(track))
              : null;
        })
        .whereType<Song>()
        .where((song) => song.id.isNotEmpty)
        .toList();
  }

  static Future<StreamInfo> getStreamInfo(String trackId) {
    return _streamRequests.putIfAbsent(trackId, () async {
      try {
        final uri =
            Uri.parse('$_base/stream/info/${Uri.encodeComponent(trackId)}');
        final decoded = jsonDecode(await _retry(() => _httpGet(uri)));
        final list = decoded is Map ? decoded['qualities'] : null;
        if (list is! List) throw const FormatException('音质响应格式无效');
        return StreamInfo(
            trackId,
            list
                .whereType<Map>()
                .map(StreamQuality.fromJson)
                .where((q) => q.downloadUrl.isNotEmpty)
                .toList());
      } catch (_) {
        _streamRequests.remove(trackId);
        rethrow;
      }
    });
  }

  /// Resolves the highest quality currently available for this track.
  static Future<StreamSelection> resolveStream(String trackId) async {
    final info = await getStreamInfo(trackId);
    if (info.qualities.isEmpty) throw StateError('歌曲没有可下载的音质');
    final chosen = selectStreamQuality(info.qualities);
    if (chosen.aesKeyHex.isEmpty) {
      throw const FormatException('音频下载响应缺少解密密钥');
    }
    return StreamSelection(
      chosen.downloadUrl,
      chosen.backupUrl,
      chosen.aesKeyHex,
      chosen.bitrateKbps,
      chosen.quality,
    );
  }

  static int _qualityRank(String quality) => switch (quality) {
        'medium' => 0,
        'higher' => 1,
        'highest' => 2,
        'hi_res' => 3,
        'spatial' => 4,
        _ => 1,
      };
}

class SearchTracksResult {
  final List<Song> songs;
  final String? nextCursor;
  final bool hasMore;
  const SearchTracksResult(this.songs, {this.nextCursor, this.hasMore = false});
}

class SearchPlaylistsResult {
  final List<PlaylistInfo> playlists;
  final String? nextCursor;
  final bool hasMore;
  const SearchPlaylistsResult(this.playlists,
      {this.nextCursor, this.hasMore = false});
}

class PlaylistInfo {
  final String id;
  final String title;
  final String coverUrl;
  final String description;
  final String owner;
  final int trackCount;

  const PlaylistInfo({
    required this.id,
    required this.title,
    this.coverUrl = '',
    this.description = '',
    this.owner = '',
    this.trackCount = 0,
  });

  factory PlaylistInfo.fromApiJson(Map json) {
    final owner = json['owner'];
    return PlaylistInfo(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? json['name']?.toString() ?? '',
      coverUrl: buildSodaImageUrl(json['url_cover'], size: 360),
      description: json['desc']?.toString() ?? '',
      owner: owner is Map
          ? (owner['nickname']?.toString() ??
              owner['public_name']?.toString() ??
              '')
          : '',
      trackCount: (json['count_tracks'] ??
              json['resource_cnt']?['track_cnt'] ??
              0) is num
          ? ((json['count_tracks'] ?? json['resource_cnt']?['track_cnt'] ?? 0)
                  as num)
              .toInt()
          : int.tryParse((json['count_tracks'] ??
                      json['resource_cnt']?['track_cnt'] ??
                      0)
                  .toString()) ??
              0,
    );
  }
}

class PlaylistPage {
  final List<Song> songs;
  final PlaylistInfo? playlist;
  final String? nextCursor;
  final bool hasMore;
  const PlaylistPage(this.songs,
      {this.playlist, this.nextCursor, this.hasMore = false});
}

class TrackDetails {
  final Song song;
  final String lyric;
  const TrackDetails({required this.song, required this.lyric});
}

class StreamQuality {
  final String quality;
  final int bitrateKbps;
  final String downloadUrl;
  final String backupUrl;
  final String aesKeyHex;
  final int rank;
  const StreamQuality(
    this.quality,
    this.bitrateKbps,
    this.downloadUrl,
    this.backupUrl,
    this.aesKeyHex,
    this.rank,
  );

  factory StreamQuality.fromJson(Map json) {
    final quality = json['quality']?.toString() ?? '';
    final bitrate = json['bitrate_kbps'] ?? json['bitrate'];
    final kbps = bitrate is num
        ? (bitrate > 1000 ? bitrate / 1000 : bitrate).round()
        : int.tryParse(bitrate?.toString() ?? '') ?? 0;
    final encryption = json['encryption'];
    return StreamQuality(
      quality,
      kbps,
      json['download_url']?.toString() ?? '',
      json['backup_url']?.toString() ?? '',
      encryption is Map ? encryption['aes_key_hex']?.toString() ?? '' : '',
      MusicApi._qualityRank(quality),
    );
  }
}

class StreamInfo {
  final String trackId;
  final List<StreamQuality> qualities;
  const StreamInfo(this.trackId, this.qualities);
}

class StreamSelection {
  final String downloadUrl;
  final String backupUrl;
  final String aesKeyHex;
  final int bitrateKbps;
  final String quality;
  const StreamSelection(
    this.downloadUrl,
    this.backupUrl,
    this.aesKeyHex,
    this.bitrateKbps,
    this.quality,
  );
}

StreamQuality selectStreamQuality(List<StreamQuality> qualities) {
  if (qualities.isEmpty) {
    throw StateError('没有可用音质');
  }
  final ranked = [...qualities]..sort((a, b) {
      final rankComparison = b.rank.compareTo(a.rank);
      return rankComparison != 0
          ? rankComparison
          : b.bitrateKbps.compareTo(a.bitrateKbps);
    });
  return ranked.first;
}
