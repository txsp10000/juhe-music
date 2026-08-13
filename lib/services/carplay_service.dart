import 'dart:io';

import 'package:flutter/services.dart';

import '../api/music_api.dart';
import '../models/listening_mode.dart';
import '../models/song.dart';
import '../utils/lyric_parser.dart';
import 'favorites_service.dart';
import 'playback_history_service.dart';
import 'player_service.dart';

class CarPlayService {
  static const _channel = MethodChannel('com.music/carplay');
  static bool _initialized = false;

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
        return _encodeNowPlaying();
      case 'playSong':
        final source = _stringArgument(call.arguments, 'source');
        final index = _intArgument(call.arguments, 'index');
        final songs = await _songsForSource(source);
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
        await player.playAt(0);
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
        PlayerService().prev();
        return true;
      case 'next':
        PlayerService().next();
        return true;
      case 'togglePlayPause':
        await PlayerService().togglePlayPause();
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
    await player.playAt(index);
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

  static Map<String, Object?> _encodeNowPlaying() {
    final player = PlayerService();
    final song = player.currentSong;
    if (song == null) {
      return {
        'hasSong': false,
        'positionMs': 0,
        'durationMs': 0,
        'playing': false,
      };
    }

    final positionMs = player.livePosition.inMilliseconds;
    final lyrics = parseLyrics(song.lyric);
    var currentIndex = -1;
    for (var index = 0; index < lyrics.length; index++) {
      if (lyrics[index].startMs <= positionMs) {
        currentIndex = index;
      } else {
        break;
      }
    }

    final current = currentIndex >= 0 ? lyrics[currentIndex] : null;
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
      'previousLyric': currentIndex > 0 ? lyrics[currentIndex - 1].text : '',
      'currentLyric': current == null
          ? null
          : {
              'startMs': current.startMs,
              'durationMs': current.durationMs,
              'text': current.text,
              'syllables': current.syllables
                  .map((syllable) => {
                        'startMs': syllable.startMs,
                        'durationMs': syllable.durationMs,
                        'text': syllable.text,
                      })
                  .toList(),
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
