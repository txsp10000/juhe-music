import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../api/music_api.dart';
import 'lyric_cache_service.dart';
import 'audio_cache_service.dart';
import 'cover_cache_service.dart';
import 'settings_service.dart';

class PlayerService {
  static final PlayerService _instance = PlayerService._();
  factory PlayerService() => _instance;
  PlayerService._();

  Player? _player;
  bool _initialized = false;
  final List<Song> playlist = [];
  int _currentIndex = -1;
  String? _currentUrl;
  int _currentPlayingBr = 999;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _playGeneration = 0;

  MediaItem? _currentMediaItem;

  Song? get currentSong => _currentIndex >= 0 && _currentIndex < playlist.length
      ? playlist[_currentIndex]
      : null;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration? get duration => _duration;
  int get currentPlayingBr => _currentPlayingBr;

  void Function(bool playing)? onPlayStateChanged;

  final List<void Function(bool)> _playStateListeners = [];

  void addPlayStateListener(void Function(bool) listener) {
    _playStateListeners.add(listener);
  }

  void removePlayStateListener(void Function(bool) listener) {
    _playStateListeners.remove(listener);
  }

  void _notifyPlayStateChanged(bool playing) {
    onPlayStateChanged?.call(playing);
    for (final l in List<void Function(bool)>.from(_playStateListeners)) {
      l(playing);
    }
  }

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
    final instance = PlayerService();
    if (instance._initialized) return;
    MediaKit.ensureInitialized();
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
    final player = instance._player!;
    instance._initialized = true;

    instance._positionSub = player.stream.position.listen((pos) {
      instance._position = pos;
      instance._notifyProgress(pos, instance._duration);
    });

    instance._durationSub = player.stream.duration.listen((dur) {
      instance._duration = dur;
      if (instance._currentMediaItem != null) {
        try {
          AudioService.updateMediaItem(
              instance._currentMediaItem!.copyWith(duration: dur));
        } catch (_) {}
      }
    });

    instance._playingSub = player.stream.playing.listen((playing) {
      instance._isPlaying = playing;
      instance._notifyPlayStateChanged(playing);
    });

    instance._completedSub = player.stream.completed.listen((completed) {
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

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= playlist.length) return;

    final removingCurrent = index == _currentIndex;
    playlist.removeAt(index);

    if (playlist.isEmpty) {
      _currentIndex = -1;
      _currentMediaItem = null;
      _currentUrl = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      await _player?.stop();
      _notifyPlayStateChanged(false);
      _notifyDownloadProgress(null);
      return;
    }

    if (removingCurrent) {
      final nextIndex = index >= playlist.length ? playlist.length - 1 : index;
      await playAt(nextIndex);
    } else if (index < _currentIndex) {
      _currentIndex--;
    }
  }

  void togglePlayPause() {
    _player?.playOrPause();
  }

  bool _isSeeking = false;

  Future<void> seek(Duration position) async {
    final player = _player;
    if (player == null) return;
    _isSeeking = true;
    player.seek(position);
    // Delay to let media_kit settle after seek, ignore spurious completed events
    Future.delayed(const Duration(milliseconds: 500), () {
      _isSeeking = false;
    });
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= playlist.length) return;
    if (_player == null) {
      try {
        await PlayerService.init();
      } catch (_) {}
    }
    final player = _player;
    _currentIndex = index;
    final song = playlist[index];
    final currentGen = ++_playGeneration;
    _notifyDownloadProgress(null);
    _position = Duration.zero;
    _duration = Duration.zero;
    _currentUrl = null;

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

    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
    }

    final coverCache = CoverCacheService();
    final localCover = await coverCache.getLocalPath(picId);
    if (currentGen != _playGeneration) return;
    if (localCover != null) {
      song.cover = 'file://$localCover';
      _currentMediaItem =
          _currentMediaItem!.copyWith(artUri: Uri.file(localCover));
      try {
        AudioService.updateMediaItem(_currentMediaItem!);
      } catch (_) {}
    }

    _notifyProgress(Duration.zero, Duration.zero);
    _notifySongChange(song);
    if (player == null) return;

    _notifyDownloadProgress(-1.0);
    unawaited(_hydrateSongDetails(song, currentGen));
    unawaited(_prepareAndPlayAudio(song, currentGen));
  }

  Future<void> _hydrateSongDetails(Song song, int generation) async {
    final playId = song.lyricId.isNotEmpty ? song.lyricId : song.id;
    final picId = song.picId.isNotEmpty ? song.picId : song.id;

    final lyricCache = LyricCacheService();
    String? lyric = await lyricCache.load(playId);
    if (generation != _playGeneration) return;
    if (lyric == null || lyric.isEmpty) {
      lyric = await MusicApi.getLyric(playId);
      if (lyric != null && lyric.isNotEmpty) {
        await lyricCache.save(playId, lyric);
      }
    }
    if (generation != _playGeneration) return;
    if (lyric != null && lyric.isNotEmpty) {
      for (final s in playlist) {
        final sid = s.lyricId.isNotEmpty ? s.lyricId : s.id;
        if (sid == playId) s.lyric = lyric;
      }
      song.lyric = lyric;
      _notifySongChange(song);
    }

    if (song.cover.isEmpty || !song.cover.startsWith('file://')) {
      final coverUrl = await _fetchCover(picId);
      if (generation != _playGeneration) return;
      if (coverUrl != null && coverUrl.isNotEmpty) {
        song.cover = coverUrl;
        final cachedCover = await CoverCacheService().getLocalPath(picId);
        if (generation != _playGeneration) return;
        if (cachedCover != null) {
          _currentMediaItem =
              _currentMediaItem?.copyWith(artUri: Uri.file(cachedCover));
        } else {
          _currentMediaItem =
              _currentMediaItem?.copyWith(artUri: Uri.parse(coverUrl));
        }
        try {
          if (_currentMediaItem != null)
            AudioService.updateMediaItem(_currentMediaItem!);
        } catch (_) {}
        _notifySongChange(song);
      }
    }
  }

  Future<void> _prepareAndPlayAudio(Song song, int generation) async {
    final player = _player;
    if (player == null) return;
    final audioCache = AudioCacheService();
    String? localPath = await audioCache.findCachedFile(song.id);
    if (generation != _playGeneration) return;

    if (localPath != null && localPath.isNotEmpty) {
      _currentPlayingBr = _extractBrFromPath(localPath);
      await player.open(Media('file://$localPath'), play: true);
      if (generation == _playGeneration) _notifyDownloadProgress(null);
      return;
    }

    final url = await _fetchPlayUrl(song);
    if (generation != _playGeneration) return;
    if (url == null || url.isEmpty) {
      if (_currentIndex < playlist.length - 1) {
        unawaited(playAt(_currentIndex + 1));
      } else if (generation == _playGeneration) {
        _notifyDownloadProgress(null);
      }
      return;
    }

    _currentUrl = url;
    _notifyDownloadProgress(0.0);
    localPath = await audioCache.download(song.id, url, onProgress: (p) {
      if (generation == _playGeneration) _notifyDownloadProgress(p);
    });
    if (generation == _playGeneration) _notifyDownloadProgress(null);
    if (generation != _playGeneration) return;

    if (localPath == null || localPath.isEmpty) {
      if (_currentIndex < playlist.length - 1) {
        unawaited(playAt(_currentIndex + 1));
      } else if (generation == _playGeneration) {
        _notifyDownloadProgress(null);
      }
      return;
    }

    _currentPlayingBr = SettingsService().quality.br;
    await player.open(Media('file://$localPath'), play: true);
    if (generation == _playGeneration) _notifyDownloadProgress(null);
  }

  /// Extract br quality value from cached file path (e.g. songId_320.mp3 -> 320)
  int _extractBrFromPath(String path) {
    final name = path.split('/').last.split('\\').last;
    // Format: songId_br.ext
    final match = RegExp(r'_(\d+)\.[a-z0-9]+$').firstMatch(name);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 999;
    }
    return 999;
  }

  /// Re-download current song at new quality setting.
  /// Stops playback, downloads at new quality, then resumes.
  Future<void> redownloadCurrentAtNewQuality() async {
    final song = currentSong;
    if (song == null) return;
    final currentGen = ++_playGeneration;
    final wasPlaying = _isPlaying;
    final resumePosition = _position;

    // Check if we already have the right quality cached
    final audioCache = AudioCacheService();
    String? localPath = await audioCache.findCachedFile(song.id);

    // Need to re-download
    if (currentGen != _playGeneration) return;
    if (localPath == null) {
      final url = await _fetchPlayUrl(song);
      if (url == null || url.isEmpty) return;
      if (currentGen != _playGeneration) return;

      _notifyDownloadProgress(0.0);
      localPath = await audioCache.download(song.id, url, onProgress: (p) {
        if (currentGen == _playGeneration) {
          _notifyDownloadProgress(p);
        }
      });
      if (currentGen == _playGeneration) {
        _notifyDownloadProgress(null);
      }
      if (currentGen != _playGeneration) return;
    }

    final player = _player;
    if (player == null || localPath == null || localPath.isEmpty) return;
    _currentPlayingBr = _extractBrFromPath(localPath);
    await player.open(Media('file://$localPath'), play: wasPlaying);
    if (currentGen != _playGeneration) return;
    if (resumePosition > Duration.zero) {
      await player.seek(resumePosition);
    }
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
    _player?.dispose();
  }
}

class _AudioPlayerTask extends BaseAudioHandler {
  static const _nowPlayingChannel =
      MethodChannel('com.miaomiao.music/nowplaying');

  String? _pauseReason;
  bool _resumeAfterInterruption = false;

  _AudioPlayerTask() {
    final ps = PlayerService();

    _nowPlayingChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'audioEvent':
          final args = call.arguments as Map? ?? {};
          final event = args['event'] as String? ?? '';
          final reason = args['reason'] as String? ?? '';
          if (event == 'pause') {
            final wasPlaying = args['wasPlaying'] as bool? ?? ps._isPlaying;
            _resumeAfterInterruption = reason == 'interruption' && wasPlaying;
            _pauseReason = reason;
            await ps._player?.pause();
          } else if (event == 'resume') {
            if (reason == 'interruption' && _resumeAfterInterruption) {
              _resumeAfterInterruption = false;
              _pauseReason = null;
              await ps._player?.play();
            }
          }
          break;
        default:
          break;
      }
    });

    ps._player?.stream.playing.listen((playing) {
      if (playing && _pauseReason != null) {
        _pauseReason = null;
        _resumeAfterInterruption = false;
      }
      _updatePlaybackState();
      _syncNowPlaying();
    });

    ps._player?.stream.position.listen((_) {
      _updatePlaybackState();
      _syncNowPlaying();
    });

    ps._player?.stream.duration.listen((dur) {
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
  Future<void> play() async => PlayerService()._player?.play();

  @override
  Future<void> pause() async => PlayerService()._player?.pause();

  @override
  Future<void> stop() async => PlayerService()._player?.stop();

  @override
  Future<void> seek(Duration position) async => PlayerService().seek(position);

  @override
  Future<void> skipToNext() async => PlayerService().next();

  @override
  Future<void> skipToPrevious() async => PlayerService().prev();
}
