import 'dart:async';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../api/music_api.dart';
import 'lyric_cache_service.dart';
import 'audio_cache_service.dart';

class PlayerService {
  static final PlayerService _instance = PlayerService._();
  factory PlayerService() => _instance;
  PlayerService._();

  final _player = AudioPlayer();
  final List<Song> playlist = [];
  int _currentIndex = -1;

  /// 当前播放的 MediaItem（CarPlay / 锁屏显示）
  MediaItem? _currentMediaItem;

  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < playlist.length
          ? playlist[_currentIndex]
          : null;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  void Function(bool playing)? onPlayStateChanged;

  final List<void Function(Duration, Duration?)> _progressListeners = [];
  final List<void Function(Song)> _songChangeListeners = [];

  void addProgressListener(void Function(Duration, Duration?) listener) {
    _progressListeners.add(listener);
  }

  void removeProgressListener(void Function(Duration, Duration?) listener) {
    _progressListeners.remove(listener);
  }

  void addSongChangeListener(void Function(Song) listener) {
    _songChangeListeners.add(listener);
  }

  void removeSongChangeListener(void Function(Song) listener) {
    _songChangeListeners.remove(listener);
  }

  void _notifyProgress(Duration pos, Duration? dur) {
    for (final l in _progressListeners) {
      l(pos, dur);
    }
  }

  void _notifySongChange(Song song) {
    for (final l in _songChangeListeners) {
      l(song);
    }
  }

  // 歌词轮询定时器
  StreamSubscription<Duration>? _positionSub;

  /// 初始化 audio_service 和 just_audio
  static Future<void> init() async {
    final instance = PlayerService();

    await AudioService.init(
      builder: () => _AudioPlayerTask(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.miaomiao.music.channel',
        androidNotificationChannelName: '苗苗music',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidShowNotificationBadge: false,
      ),
    );

    // 用 positionStream 替代 Timer.periodic：由音频硬件时钟驱动，无跨平台轮询延迟
    instance._positionSub = instance._player.positionStream.listen((pos) {
      instance._notifyProgress(pos, instance._player.duration);
    });

    instance._player.playerStateStream.listen((state) {
      instance.onPlayStateChanged?.call(state.playing);
      if (state.processingState == ProcessingState.completed) {
        instance._onComplete();
      }
    });

    instance._player.durationStream.listen((dur) {
      if (dur != null && instance._currentMediaItem != null) {
        try {
          AudioService.updateMediaItem(
              instance._currentMediaItem!.copyWith(duration: dur));
        } catch (_) {}
      }
    });
  }

  void _onComplete() {
    if (_currentIndex < playlist.length - 1) {
      playAt(_currentIndex + 1);
    } else if (playlist.isNotEmpty) {
      playAt(0);
    }
  }

  void prev() {
    if (playlist.isEmpty) return;
    final newIdx = _currentIndex > 0 ? _currentIndex - 1 : playlist.length - 1;
    playAt(newIdx);
  }

  void next() {
    if (playlist.isEmpty) return;
    final newIdx = _currentIndex < playlist.length - 1 ? _currentIndex + 1 : 0;
    playAt(newIdx);
  }

  void togglePlayPause() {
    if (_player.playing) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= playlist.length) return;
    _currentIndex = index;
    final song = playlist[index];

    final playId = song.lyricId.isNotEmpty ? song.lyricId : song.id;
    final picId = song.picId.isNotEmpty ? song.picId : song.id;

    // 先设置 MediaItem（CarPlay 立即显示歌曲名）
    _currentMediaItem = MediaItem(
      id: song.id,
      title: song.name,
      artist: song.singer,
      album: song.album.isNotEmpty ? song.album : '苗苗music',
      artUri: song.cover.isNotEmpty ? Uri.parse(song.cover) : null,
    );
    try {
      await AudioService.updateMediaItem(_currentMediaItem!);
    } catch (_) {}

    // 1. 歌词：本地缓存优先，没有则下载并缓存
    final lyricCache = LyricCacheService();
    String? lyric = await lyricCache.load(playId);
    if (lyric == null || lyric.isEmpty) {
      lyric = await MusicApi.getLyric(playId);
      if (lyric != null && lyric.isNotEmpty) {
        await lyricCache.save(playId, lyric);
        for (final s in playlist) {
          final sid = s.lyricId.isNotEmpty ? s.lyricId : s.id;
          if (sid == playId) {
            s.lyric = lyric!;
          }
        }
      }
    }
    song.lyric = lyric ?? '';

    // 2. 获取播放地址和封面
    final results = await Future.wait([
      _fetchPlayUrl(song),
      MusicApi.getCover(picId),
    ]);
    final url = results[0] as String?;
    final coverUrl = results[1] as String?;

    if (coverUrl != null && coverUrl.isNotEmpty) {
      song.cover = coverUrl;
      _currentMediaItem = _currentMediaItem!.copyWith(
        artUri: Uri.parse(coverUrl),
      );
      try {
        AudioService.updateMediaItem(_currentMediaItem!);
      } catch (_) {}
    }
    if (url == null || url.isEmpty) return;

    // 3. 直接使用网络 URL 流式播放（和 Safari 一样通过 HTTP Range 实现精确 seek）
    await _player.setAudioSource(
      AudioSource.uri(
        Uri.parse(url),
        headers: const {'User-Agent': 'Mozilla/5.0'},
      ),
    );
    _player.play();

    _notifySongChange(song);
  }

  Future<String?> _fetchPlayUrl(Song song) async {
    try {
      if (song.id.isEmpty) return null;
      return await MusicApi.getPlayUrl(song.id);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _positionSub?.cancel();
    _player.dispose();
  }
}

/// audio_service 后台音频任务（iOS: CarPlay / 锁屏控制）
class _AudioPlayerTask extends BaseAudioHandler {
  final _player = PlayerService()._player;

  static const _nowPlayingChannel = MethodChannel('com.miaomiao.music/nowplaying');

  _AudioPlayerTask() {
    _player.playbackEventStream.listen((event) {
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        processingState: _mapProcessingState(_player.processingState),
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ));
      _syncNowPlaying();
    });

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.ready) {
        final item = PlayerService()._currentMediaItem;
        if (item != null) {
          final updated = item.copyWith(
            duration: _player.duration ?? Duration.zero,
          );
          mediaItem.add(updated);
          PlayerService()._currentMediaItem = updated;
          try { AudioService.updateMediaItem(updated); } catch (_) {}
          _syncNowPlaying();
        }
      }
    });
  }

  /// 直接更新 MPNowPlayingInfoCenter（绕过 audio_service 的时机问题）
  void _syncNowPlaying() {
    final item = PlayerService()._currentMediaItem;
    if (item == null) return;
    _nowPlayingChannel.invokeMethod('update', {
      'title': item.title,
      'artist': item.artist,
      'album': item.album ?? '',
      'duration': (_player.duration?.inMilliseconds ?? 0) / 1000.0,
      'elapsedTime': _player.position.inMilliseconds / 1000.0,
      'playbackRate': _player.playing ? 1.0 : 0.0,
    });
  }

  AudioProcessingState _mapProcessingState(ProcessingState s) {
    return switch (s) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
  }

  @override
  Future<void> play() async => _player.play();

  @override
  Future<void> pause() async => _player.pause();

  @override
  Future<void> stop() async => _player.stop();

  @override
  Future<void> seek(Duration position) async => _player.seek(position);

  @override
  Future<void> skipToNext() async => PlayerService().next();

  @override
  Future<void> skipToPrevious() async => PlayerService().prev();
}
