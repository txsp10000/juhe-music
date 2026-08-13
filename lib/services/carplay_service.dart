import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../api/music_api.dart';
import '../models/listening_mode.dart';
import '../models/song.dart';
import '../utils/lyric_parser.dart';
import 'favorites_service.dart';
import 'playback_history_service.dart';
import 'player_service.dart';
import 'theme_service.dart';

class CarPlayService {
  static const _channel = MethodChannel('com.music/carplay');
  static bool _initialized = false;
  static String _cachedLyricSongId = '';
  static String _cachedLyricContent = '';
  static List<LyricLine> _cachedLyrics = const [];
  static String _cachedFavoriteSongId = '';
  static int _cachedFavoriteVersion = -1;
  static bool _cachedFavorite = false;
  static Future<void> _favoriteOperationTail = Future<void>.value();

  static void initialize() {
    if (_initialized || !Platform.isIOS) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleCall);
  }

  static Future<Object?> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'getLibrary':
        final results = await Future.wait([
          PlaybackHistoryService.load(),
          FavoritesService.load(),
        ]);
        final player = PlayerService();
        return {
          'recent': results[0].map(_encodeSong).toList(),
          'favorites': results[1].map(_encodeSong).toList(),
          'queue': player.queue.map(_encodeSong).toList(),
        };
      case 'getModes':
        const preferredModeIds = [33, 1, 5, 2, 6, 3, 40, 21, 11, 28, 15, 16];
        final modesById = {
          for (final mode in listeningModes) mode.sceneModeId: mode,
        };
        final carPlayModes = [
          for (final id in preferredModeIds)
            if (modesById[id] case final mode?) mode,
          ...listeningModes.where(
            (mode) => !preferredModeIds.contains(mode.sceneModeId),
          ),
        ];
        return carPlayModes
            .map((mode) => {
                  'name': mode.name,
                  'sceneModeId': mode.sceneModeId,
                })
            .toList();
      case 'getSongs':
        final source = _stringArgument(call.arguments, 'source');
        return (await _songsForSource(source)).map(_encodeSong).toList();
      case 'getNowPlaying':
        return await _encodeNowPlaying();
      case 'toggleFavorite':
        return _serializeFavoriteToggle();
      case 'loadMoreQueue':
        final player = PlayerService();
        var addedCount = 0;
        if (player.activeMode != null) {
          addedCount = await player.loadMoreModeSongs(throwOnError: true);
        }
        return {
          'songs': player.queue.map(_encodeSong).toList(),
          'canLoadMore': player.activeMode != null,
          'addedCount': addedCount,
        };
      case 'playSong':
        final source = _stringArgument(call.arguments, 'source');
        final songId = _stringArgument(call.arguments, 'songId');
        final songSource = _stringArgument(call.arguments, 'songSource');
        final songs = await _songsForSource(source);
        final index = findCarPlaySongIndex(songs, songId, songSource);
        await _playSongs(songs, index, source: source);
        return true;
      case 'playMode':
        final sceneModeId = _intArgument(call.arguments, 'sceneModeId');
        final mode = listeningModes.firstWhere(
          (item) => item.sceneModeId == sceneModeId,
        );
        final songs = await MusicApi.getModeTracks(sceneModeId: sceneModeId);
        if (songs.isEmpty) return false;
        final player = PlayerService();
        await PlayerService.init();
        player.replaceQueue(songs, mode: mode);
        if (!await player.playAt(0)) {
          throw PlatformException(
            code: 'playback_failed',
            message: '场景歌曲暂时无法播放，请稍后重试。',
          );
        }
        return true;
      case 'search':
        final query = _stringArgument(call.arguments, 'query').trim();
        if (query.isEmpty) return const [];
        final result = await MusicApi.searchTracks(query);
        return result.songs.map(_encodeSong).toList();
      case 'playSearchResults':
        final arguments = Map<Object?, Object?>.from(call.arguments as Map);
        final rawSongs = arguments['songs'] as List? ?? const [];
        final songs = rawSongs
            .whereType<Map>()
            .map((value) => Song.fromJson(Map<String, dynamic>.from(value)))
            .toList();
        await _playSongs(songs, _intArgument(arguments, 'index'));
        return true;
      case 'previous':
        if (!await PlayerService().prev()) {
          throw PlatformException(
            code: 'playback_failed',
            message: '无法切换到上一首歌曲。',
          );
        }
        return true;
      case 'next':
        if (!await PlayerService().next()) {
          throw PlatformException(
            code: 'playback_failed',
            message: '无法切换到下一首歌曲。',
          );
        }
        return true;
      case 'togglePlayPause':
        if (!await PlayerService().togglePlayPause()) {
          throw PlatformException(
            code: 'playback_failed',
            message: '当前没有可播放的歌曲。',
          );
        }
        return true;
      default:
        throw PlatformException(
          code: 'not_implemented',
          message: 'Unsupported CarPlay method: ${call.method}',
        );
    }
  }

  static Future<List<Song>> _songsForSource(String source) {
    switch (source) {
      case 'recent':
        return PlaybackHistoryService.load();
      case 'favorites':
        return FavoritesService.load();
      case 'queue':
        return Future.value(List<Song>.of(PlayerService().queue));
      default:
        throw PlatformException(
          code: 'invalid_source',
          message: 'Unknown CarPlay collection: $source',
        );
    }
  }

  static Future<void> _playSongs(
    List<Song> songs,
    int index, {
    String source = 'regular',
  }) async {
    if (songs.isEmpty || index < 0 || index >= songs.length) {
      throw PlatformException(
        code: 'invalid_selection',
        message: 'The selected CarPlay song is unavailable.',
      );
    }
    await PlayerService.init();
    final player = PlayerService();
    if (source != 'queue') {
      player.replaceQueue(
        songs,
        source: source == 'favorites'
            ? PlaybackQueueSource.favorites
            : PlaybackQueueSource.regular,
      );
    }
    if (!await player.playAt(index)) {
      throw PlatformException(
        code: 'playback_failed',
        message: '歌曲暂时无法播放，请稍后重试。',
      );
    }
  }

  static Future<bool> _serializeFavoriteToggle() {
    final completer = Completer<bool>();
    _favoriteOperationTail =
        _favoriteOperationTail.catchError((_) {}).then((_) async {
      try {
        final song = PlayerService().currentSong;
        if (song == null) {
          completer.complete(false);
          return;
        }
        final wasFavorite = await FavoritesService.isFavorite(song);
        if (wasFavorite) {
          await FavoritesService.remove(song);
        } else {
          await FavoritesService.save(song);
        }
        _cachedFavoriteSongId = song.id;
        _cachedFavoriteVersion = FavoritesService.version.value;
        _cachedFavorite = !wasFavorite;
        completer.complete(_cachedFavorite);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static Map<String, Object> _encodeSong(Song song) => {
        'id': song.id,
        'name': song.name,
        'singer': song.singer,
        'album': song.album,
        'source': song.source,
        'pic_id': song.picId,
        'lyric_id': song.lyricId,
        'duration': song.duration,
        'cover': song.cover,
      };

  static Future<Map<String, Object?>> _encodeNowPlaying() async {
    final player = PlayerService();
    final song = player.currentSong;
    if (song == null) {
      return {
        'hasSong': false,
        'positionMs': 0,
        'durationMs': 0,
        'playing': false,
        'themeColor': ThemeService.bgHint.value.toARGB32(),
      };
    }

    final positionMs = player.livePosition.inMilliseconds;
    const carPlayVisualDelayMs = 500;
    final lyricPositionMs =
        (positionMs - carPlayVisualDelayMs).clamp(0, positionMs);
    if (_cachedLyricSongId != song.id || _cachedLyricContent != song.lyric) {
      _cachedLyricSongId = song.id;
      _cachedLyricContent = song.lyric;
      _cachedLyrics = parseLyrics(song.lyric);
    }
    if (_cachedFavoriteSongId != song.id ||
        _cachedFavoriteVersion != FavoritesService.version.value) {
      _cachedFavoriteSongId = song.id;
      _cachedFavoriteVersion = FavoritesService.version.value;
      _cachedFavorite = await FavoritesService.isFavorite(song);
    }
    final lyrics = _cachedLyrics;
    var currentIndex = -1;
    for (var index = 0; index < lyrics.length; index++) {
      if (lyrics[index].startMs <= lyricPositionMs) {
        currentIndex = index;
      } else {
        break;
      }
    }

    final current = currentIndex >= 0 ? lyrics[currentIndex] : null;
    final nextIndex = currentIndex + 1;
    final nextStartMs = nextIndex >= 0 && nextIndex < lyrics.length
        ? lyrics[nextIndex].startMs
        : null;
    return {
      'hasSong': true,
      'id': song.id,
      'name': song.name,
      'singer': song.singer,
      'album': song.album,
      'cover': song.cover,
      'positionMs': positionMs,
      'durationMs': player.liveDuration.inMilliseconds,
      'playing': player.isPlaying,
      'favorite': _cachedFavorite,
      'themeColor': ThemeService.bgHint.value.toARGB32(),
      'nextLyricChangeInMs': carPlayLyricChangeDelayMs(
        positionMs: positionMs,
        nextLyricStartMs: nextStartMs,
      ),
      'previousLyric': currentIndex > 0 ? lyrics[currentIndex - 1].text : '',
      'currentLyric': current == null
          ? null
          : {
              'startMs': current.startMs,
              'durationMs': current.durationMs,
              'text': current.text,
            },
      'nextLyric': currentIndex + 1 < lyrics.length
          ? lyrics[currentIndex + 1].text
          : currentIndex < 0 && lyrics.isNotEmpty
              ? lyrics.first.text
              : '',
    };
  }

  static String _stringArgument(Object? arguments, String key) {
    final values = Map<Object?, Object?>.from(arguments as Map);
    return values[key]?.toString() ?? '';
  }

  static int _intArgument(Object? arguments, String key) {
    final values = Map<Object?, Object?>.from(arguments as Map);
    final value = values[key];
    return value is int ? value : int.tryParse(value?.toString() ?? '') ?? -1;
  }
}

int findCarPlaySongIndex(List<Song> songs, String songId, String songSource) {
  return songs.indexWhere(
    (song) =>
        song.id == songId && (songSource.isEmpty || song.source == songSource),
  );
}

int? carPlayLyricChangeDelayMs({
  required int positionMs,
  required int? nextLyricStartMs,
  int visualDelayMs = 500,
}) {
  if (nextLyricStartMs == null) return null;
  return (nextLyricStartMs + visualDelayMs - positionMs)
      .clamp(0, nextLyricStartMs + visualDelayMs);
}
