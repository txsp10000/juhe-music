import 'dart:async';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../api/music_api.dart';
import 'lyric_cache_service.dart';
import 'audio_cache_service.dart';
import 'cover_cache_service.dart';

class PlayerService {
  static final PlayerService _instance = PlayerService._();
  factory PlayerService() => _instance;
  PlayerService._();

  late final Player _player;
  final List<Song> playlist = [];
  int _currentIndex = -1;
  String? _currentUrl;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _playGeneration = 0;

  MediaItem? _currentMediaItem;

  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < playlist.length
          ? playlist[_currentIndex]
          : null;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration? get duration => _duration;

  void Function(bool playing)? onPlayStateChanged;

  // Download progress: 0.0 to 1.0, null means not downloading
  double? _downloadProgress;
  double? get downloadProgress => _downloadProgress;
  final List<void Function(double?)> _downloadProgressListeners = [];

  void addDownloadProgressListener(void Function(double?) listener) {
    _downloadProgressListeners.add(listener);
  }

  void removeDownloadProgressListener(void Function(double?) listener) {
    _downloadProgressListeners.remove(listener);
  }

  void _notifyDownloadProgress(double? progress) {
    _downloadProgress = progress;
    for (final l in _downloadProgressListeners) {
      l(progress);
    }
  }

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

  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _completedSub;

  static Future<void> init() async {
    MediaKit.ensureInitialized();
    final instance = PlayerService();
    instance._player = Player();

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

    instance._positionSub = instance._player.stream.position.listen((pos) {
      instance._position = pos;
      instance._notifyProgress(pos, instance._duration);
    });

    instance._durationSub = instance._player.stream.duration.listen((dur) {
      instance._duration = dur;
      if (instance._currentMediaItem != null) {
        try {
          AudioService.updateMediaItem(
              instance._currentMediaItem!.copyWith(duration: dur));
        } catch (_) {}
      }
    });

    instance._playingSub = instance._player.stream.playing.listen((playing) {
      instance._isPlaying = playing;
      instance.onPlayStateChanged?.call(playing);
    });

    instance._completedSub = instance._player.stream.completed.listen((completed) {
      if (completed) instance._onComplete();
    });
  }

  void _onComplete() {
    if (_isSeeking) return;
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
    _player.playOrPause();
  }

  bool _isSeeking = false;

  Future<void> seek(Duration position) async {
    _isSeeking = true;
    _player.seek(position);
    // Delay to let media_kit settle after seek, ignore spurious completed events
    Future.delayed(const Duration(milliseconds: 500), () {
      _isSeeking = false;
    });
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= playlist.length) return;
    _currentIndex = index;
    final song = playlist[index];
    final currentGen = ++_playGeneration;

    final playId = song.lyricId.isNotEmpty ? song.lyricId : song.id;
    final picId = song.picId.isNotEmpty ? song.picId : song.id;

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
    if (currentGen != _playGeneration) return;

    final results = await Future.wait([
      _fetchPlayUrl(song),
      _fetchCover(picId),
    ]);
    if (currentGen != _playGeneration) return;
    final url = results[0] as String?;
    final coverUrl = results[1] as String?;

    if (coverUrl != null && coverUrl.isNotEmpty) {
      song.cover = coverUrl;
    }
    final coverCache = CoverCacheService();
    final localCover = await coverCache.getLocalPath(picId);
    if (localCover != null) {
      if (song.cover.isEmpty) song.cover = 'file://$localCover';
      final uri = Uri.file(localCover);
      _currentMediaItem = _currentMediaItem!.copyWith(artUri: uri);
      try {
        AudioService.updateMediaItem(_currentMediaItem!);
      } catch (_) {}
    } else if (coverUrl != null && coverUrl.isNotEmpty) {
      final uri = Uri.parse(coverUrl);
      _currentMediaItem = _currentMediaItem!.copyWith(artUri: uri);
      try {
        AudioService.updateMediaItem(_currentMediaItem!);
      } catch (_) {}
    }
    if (url == null || url.isEmpty) return;
    if (currentGen != _playGeneration) return;

    _currentUrl = url;

    final audioCache = AudioCacheService();
    _notifyDownloadProgress(0.0);
    String? localPath = await audioCache.download(song.id, url, onProgress: (p) {
      if (currentGen == _playGeneration) {
        _notifyDownloadProgress(p);
      }
    });
    if (currentGen == _playGeneration) {
      _notifyDownloadProgress(null);
    }
    if (currentGen != _playGeneration) return;

    if (localPath == null || localPath.isEmpty) return;
    await _player.open(Media('file://$localPath'), play: true);
    if (currentGen != _playGeneration) return;

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

  Future<String?> _fetchCover(String picId) async {
    final coverCache = CoverCacheService();
    final cached = await coverCache.getLocalPath(picId);
    if (cached != null) return null;
    try {
      final url = await MusicApi.getCover(picId);
      if (url.isNotEmpty) {
        await coverCache.download(picId, url);
        return url;
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _player.dispose();
  }
}

class _AudioPlayerTask extends BaseAudioHandler {
  static const _nowPlayingChannel = MethodChannel('com.miaomiao.music/nowplaying');

  _AudioPlayerTask() {
    final ps = PlayerService();

    ps._player.stream.playing.listen((playing) {
      _updatePlaybackState();
    });

    ps._player.stream.position.listen((_) {
      _updatePlaybackState();
      _syncNowPlaying();
    });

    ps._player.stream.duration.listen((dur) {
      final item = ps._currentMediaItem;
      if (item != null && dur > Duration.zero) {
        final updated = item.copyWith(duration: dur);
        mediaItem.add(updated);
        ps._currentMediaItem = updated;
        _syncNowPlaying();
      }
    });

    ps.addSongChangeListener((song) {
      final item = ps._currentMediaItem;
      if (item != null) {
        mediaItem.add(item);
      }
    });
  }

  void _updatePlaybackState() {
    final ps = PlayerService();
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (ps._isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      processingState: AudioProcessingState.ready,
      playing: ps._isPlaying,
      updatePosition: ps._position,
      speed: 1.0,
    ));
  }

  void _syncNowPlaying() {
    final ps = PlayerService();
    final item = ps._currentMediaItem;
    if (item == null) return;
    _nowPlayingChannel.invokeMethod('update', {
      'title': item.title,
      'artist': item.artist,
      'album': item.album ?? '',
      'duration': ps._duration.inMilliseconds / 1000.0,
      'elapsedTime': ps._position.inMilliseconds / 1000.0,
      'playbackRate': ps._isPlaying ? 1.0 : 0.0,
      'artUri': item.artUri?.toString() ?? '',
    });
  }

  @override
  Future<void> play() async => PlayerService()._player.play();

  @override
  Future<void> pause() async => PlayerService()._player.pause();

  @override
  Future<void> stop() async => PlayerService()._player.stop();

  @override
  Future<void> seek(Duration position) async => PlayerService().seek(position);

  @override
  Future<void> skipToNext() async => PlayerService().next();

  @override
  Future<void> skipToPrevious() async => PlayerService().prev();
}



