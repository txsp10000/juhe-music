import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import '../models/song.dart';
import '../models/listening_mode.dart';
import '../api/music_api.dart';
import 'lyric_cache_service.dart';
import 'audio_cache_service.dart';
import 'cover_cache_service.dart';
import 'theme_service.dart';
import 'playback_history_service.dart';
import 'app_environment.dart';

enum PlaybackQueueSource { regular, favorites, listeningMode }

class PlayerService {
  static final PlayerService _instance = PlayerService._();
  factory PlayerService() => _instance;
  PlayerService._();

  Player? _player;
  AudioHandler? _audioHandler;
  bool _initialized = false;
  Future<void>? _initializing;
  final List<Song> queue = [];
  ListeningMode? _activeMode;
  PlaybackQueueSource _queueSource = PlaybackQueueSource.regular;
  bool _loadingModeSongs = false;
  ListeningMode? get activeMode => _activeMode;
  PlaybackQueueSource get queueSource => _queueSource;
  bool get loadingModeSongs => _loadingModeSongs;
  int _currentIndex = -1;
  int _currentPlayingBr = 999;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _playGeneration = 0;

  MediaItem? _currentMediaItem;

  Song? get currentSong => _currentIndex >= 0 && _currentIndex < queue.length
      ? queue[_currentIndex]
      : null;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _player?.state.playing ?? _isPlaying;
  bool get playing => isPlaying;
  Duration get position => _player?.state.position ?? _position;
  Duration get livePosition => position;
  Duration? get duration => _player?.state.duration ?? _duration;
  Duration get liveDuration => duration ?? _duration;
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
  final List<void Function(String)> _playbackErrorListeners = [];

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

  void addPlaybackErrorListener(void Function(String) listener) {
    _playbackErrorListeners.add(listener);
  }

  void removePlaybackErrorListener(void Function(String) listener) {
    _playbackErrorListeners.remove(listener);
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

  void _notifyPlaybackError(String message) {
    for (final listener
        in List<void Function(String)>.from(_playbackErrorListeners)) {
      listener(message);
    }
  }

  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _completedSub;
  StreamSubscription? _errorSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  AudioSession? _androidAudioSession;
  bool _resumeAfterAndroidInterruption = false;
  bool _androidDucked = false;
  double _volumeBeforeDucking = 100.0;
  int? _openedGeneration;
  int? _failedGeneration;
  int? _cachedPlaybackGeneration;
  int? _cachedRecoveryGeneration;
  String? _cachedPlaybackPath;
  bool _cachedPlayRequested = true;
  int? _progressiveGeneration;
  Future<AudioCacheResult>? _progressiveCacheFuture;
  AudioCacheCancellationToken? _progressiveCacheCancellation;
  int? _progressiveFallbackGeneration;
  bool _progressivePlayRequested = true;
  Duration? _progressiveResumePosition;
  Uint8List? _pendingThemeCover;
  int? _pendingThemeGeneration;
  bool _suppressCompletion = false;
  int _seekGeneration = 0;
  Future<void> _mediaOperationTail = Future<void>.value();

  static Future<void> init() async {
    final instance = PlayerService();
    if (instance._initialized) return;
    final pending = instance._initializing;
    if (pending != null) return pending;

    final initialization = instance._initialize();
    instance._initializing = initialization;
    try {
      await initialization;
    } finally {
      instance._initializing = null;
    }
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    MediaKit.ensureInitialized();
    final createdPlayer = Player(
      configuration: PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    _player = createdPlayer;
    final nativePlayer = createdPlayer.platform;
    if (nativePlayer is NativePlayer) {
      try {
        await nativePlayer.setProperty('cache-on-disk', 'no');
      } catch (_) {}
    }

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        _audioHandler = await AudioService.init(
          builder: () => _AudioPlayerTask(),
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'com.music.channel',
            androidNotificationChannelName: '音乐',
            androidNotificationOngoing: false,
            androidStopForegroundOnPause: true,
            androidShowNotificationBadge: false,
          ),
        );
        await _configureAndroidAudioSession();
      }
    } catch (_) {
      await createdPlayer.dispose();
      if (identical(_player, createdPlayer)) _player = null;
      rethrow;
    }
    final player = createdPlayer;
    _initialized = true;

    _positionSub = player.stream.position.listen((pos) {
      _position = pos;
      _notifyProgress(pos, _duration);
    });

    _durationSub = player.stream.duration.listen((dur) {
      _duration = dur;
      if (_audioHandler != null && _currentMediaItem != null) {
        try {
          unawaited(
            _audioHandler!.updateMediaItem(
              _currentMediaItem!.copyWith(duration: dur),
            ),
          );
        } catch (_) {}
      }
    });

    _playingSub = player.stream.playing.listen((playing) {
      _isPlaying = playing;
      if (playing) {
        _applyPendingThemeForPlayback(_openedGeneration);
      }
      _notifyPlayStateChanged(playing);
    });

    _completedSub = player.stream.completed.listen((completed) {
      if (completed) _onComplete();
    });
    _errorSub = player.stream.error.listen((_) {
      final generation = _openedGeneration;
      if (generation != null) {
        if (_cachedPlaybackGeneration == generation &&
            _cachedPlaybackPath != null) {
          unawaited(_recoverFromCachedPlayback(generation));
        } else if (_cachedRecoveryGeneration == generation) {
          return;
        } else if (_progressiveGeneration == generation) {
          unawaited(_fallbackFromProgressiveStream(generation));
        } else if (_progressiveFallbackGeneration == generation) {
          return;
        } else {
          unawaited(_handlePlaybackFailure(generation, '播放失败，请重试'));
        }
      }
    });
  }

  Future<void> _configureAndroidAudioSession() async {
    if (!Platform.isAndroid) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _androidAudioSession = session;
    await _interruptionSub?.cancel();
    await _becomingNoisySub?.cancel();
    _interruptionSub = session.interruptionEventStream.listen((event) async {
      final player = _player;
      if (player == null) return;
      if (event.begin) {
        if (event.type == AudioInterruptionType.duck) {
          if (!_androidDucked) {
            _volumeBeforeDucking = player.state.volume;
            _androidDucked = true;
            await player.setVolume((_volumeBeforeDucking * 0.25).clamp(0, 100));
          }
          return;
        }
        _resumeAfterAndroidInterruption =
            event.type == AudioInterruptionType.pause && player.state.playing;
        await player.pause();
        return;
      }

      if (event.type == AudioInterruptionType.duck && _androidDucked) {
        _androidDucked = false;
        await player.setVolume(_volumeBeforeDucking);
      } else if (event.type == AudioInterruptionType.pause &&
          _resumeAfterAndroidInterruption) {
        _resumeAfterAndroidInterruption = false;
        if (await session.setActive(true)) await player.play();
      }
    });
    _becomingNoisySub = session.becomingNoisyEventStream.listen((_) async {
      _resumeAfterAndroidInterruption = false;
      await _player?.pause();
      await session.setActive(false);
    });
  }

  Future<bool> _activateAndroidAudioSession() async {
    final session = _androidAudioSession;
    if (session == null) return true;
    return session.setActive(true);
  }

  Future<void> _deactivateAndroidAudioSession() async {
    await _androidAudioSession?.setActive(false);
  }

  Future<bool> _activatePlaybackSession() async {
    if (Platform.isIOS) {
      try {
        return await const MethodChannel('com.music/nowplaying')
                .invokeMethod<bool>('setPlaybackSessionActive', true) ??
            false;
      } catch (_) {
        return false;
      }
    }
    return _activateAndroidAudioSession();
  }

  Future<void> _deactivatePlaybackSession() async {
    if (Platform.isIOS) {
      try {
        await const MethodChannel('com.music/nowplaying')
            .invokeMethod<void>('setPlaybackSessionActive', false);
      } catch (_) {}
      return;
    }
    await _deactivateAndroidAudioSession();
  }

  void _onComplete() {
    if (_isSeeking || _suppressCompletion) return;
    if (_currentIndex < queue.length - 1) {
      unawaited(playAt(_currentIndex + 1));
    } else if (queue.isNotEmpty) {
      if (_activeMode != null) {
        unawaited(_loadMoreModeSongsAndPlay());
      } else {
        unawaited(playAt(0));
      }
    }
  }

  Future<bool> prev() async {
    if (queue.isEmpty) return false;
    final newIdx = _currentIndex > 0 ? _currentIndex - 1 : queue.length - 1;
    return playAt(newIdx);
  }

  Future<bool> next() async {
    if (queue.isEmpty) return false;
    if (_currentIndex < queue.length - 1) {
      return playAt(_currentIndex + 1);
    } else if (_activeMode != null) {
      return _loadMoreModeSongsAndPlay();
    } else {
      return playAt(0);
    }
  }

  void replaceQueue(
    List<Song> songs, {
    ListeningMode? mode,
    PlaybackQueueSource source = PlaybackQueueSource.regular,
  }) {
    _activeMode = mode;
    _queueSource = mode == null ? source : PlaybackQueueSource.listeningMode;
    queue
      ..clear()
      ..addAll(songs);
    _currentIndex = -1;
  }

  void clearMode() => _activeMode = null;

  Future<bool> _loadMoreModeSongsAndPlay() async {
    final previousIndex = _currentIndex;
    final addedCount = await loadMoreModeSongs();
    if (addedCount <= 0 ||
        _currentIndex != previousIndex ||
        previousIndex >= queue.length - 1) {
      return false;
    }
    return playAt(previousIndex + 1);
  }

  Future<int> loadMoreModeSongs({
    bool playNext = false,
    bool throwOnError = false,
  }) async {
    final mode = _activeMode;
    if (mode == null || _loadingModeSongs) return 0;
    _loadingModeSongs = true;
    final previousLength = queue.length;
    try {
      final songs = await MusicApi.getModeTracks(sceneModeId: mode.sceneModeId);
      if (!identical(_activeMode, mode) || songs.isEmpty) return 0;
      // Mode feeds may repeat items across requests. Keep the queue
      // stable while still allowing each scroll to contribute new songs.
      final existingIds = queue.map((song) => song.id).toSet();
      queue.addAll(songs.where((song) => existingIds.add(song.id)));
      if (playNext &&
          _currentIndex >= previousLength - 1 &&
          _currentIndex < queue.length - 1) {
        await playAt(_currentIndex + 1);
      }
      return queue.length - previousLength;
    } catch (_) {
      // Keep the current song playable; a later next/completion retries.
      if (throwOnError) rethrow;
      return 0;
    } finally {
      _loadingModeSongs = false;
    }
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= queue.length) return;

    final removingCurrent = index == _currentIndex;
    final wasPlaying = isPlaying;
    queue.removeAt(index);

    if (queue.isEmpty) {
      _playGeneration++;
      _cancelProgressiveCache();
      _clearCachedPlaybackState();
      _activeMode = null;
      _queueSource = PlaybackQueueSource.regular;
      _currentIndex = -1;
      _currentMediaItem = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _openedGeneration = null;
      await _stopPlayerSerialized();
      await _deactivatePlaybackSession();
      _notifyPlayStateChanged(false);
      _notifyDownloadProgress(null);
      return;
    }

    if (removingCurrent) {
      final nextIndex = index >= queue.length ? queue.length - 1 : index;
      await playAt(nextIndex, play: wasPlaying);
    } else if (index < _currentIndex) {
      _currentIndex--;
    }
  }

  Future<bool> togglePlayPause() async {
    if (isPlaying) {
      await pause();
      return true;
    } else {
      return play();
    }
  }

  Future<bool> play() async {
    if (_failedGeneration == _playGeneration &&
        _currentIndex >= 0 &&
        _currentIndex < queue.length) {
      return playAt(_currentIndex);
    }
    _resumeAfterAndroidInterruption = false;
    if (_player == null || currentSong == null) return false;
    if (!await _activatePlaybackSession()) return false;
    if (_progressiveGeneration == _playGeneration ||
        _progressiveFallbackGeneration == _playGeneration) {
      _progressivePlayRequested = true;
    }
    if (_cachedPlaybackGeneration == _playGeneration ||
        _cachedRecoveryGeneration == _playGeneration) {
      _cachedPlayRequested = true;
    }
    await _player?.play();
    return true;
  }

  Future<void> pause() async {
    _resumeAfterAndroidInterruption = false;
    if (_progressiveGeneration == _playGeneration ||
        _progressiveFallbackGeneration == _playGeneration) {
      _progressivePlayRequested = false;
    }
    if (_cachedPlaybackGeneration == _playGeneration ||
        _cachedRecoveryGeneration == _playGeneration) {
      _cachedPlayRequested = false;
    }
    await _player?.pause();
    await _deactivatePlaybackSession();
  }

  Future<void> stop() async {
    _resumeAfterAndroidInterruption = false;
    _openedGeneration = null;
    _playGeneration++;
    _cancelProgressiveCache();
    _clearCachedPlaybackState();
    await _stopPlayerSerialized();
    await _deactivatePlaybackSession();
    _notifyDownloadProgress(null);
  }

  bool _isSeeking = false;

  Future<void> seek(Duration position) async {
    final player = _player;
    if (player == null) return;
    if (_progressiveGeneration == _playGeneration ||
        _progressiveFallbackGeneration == _playGeneration) {
      _progressiveResumePosition = position;
    }
    final seekGeneration = ++_seekGeneration;
    _isSeeking = true;
    await player.seek(position);
    // Delay to let media_kit settle after seek, ignore spurious completed events
    Future.delayed(const Duration(milliseconds: 500), () {
      if (seekGeneration == _seekGeneration) _isSeeking = false;
    });
  }

  Future<void> seekRelative(Duration delta) async {
    final target = position + delta;
    final maximum = liveDuration;
    final bounded = target < Duration.zero
        ? Duration.zero
        : maximum > Duration.zero && target > maximum
            ? maximum
            : target;
    await seek(bounded);
  }

  Future<bool> playAt(int index, {bool play = true}) async {
    if (index < 0 || index >= queue.length) return false;
    if (_player == null) {
      try {
        await PlayerService.init();
      } catch (_) {
        _notifyPlaybackError('播放器初始化失败，请重新打开应用');
        return false;
      }
    }
    final player = _player;
    if (player == null) {
      _notifyPlaybackError('播放器初始化失败，请重新打开应用');
      return false;
    }
    _currentIndex = index;
    final song = queue[index];
    unawaited(PlaybackHistoryService.record(song));
    final currentGen = ++_playGeneration;
    _cancelProgressiveCache();
    _clearCachedPlaybackState();
    ThemeService.invalidateCover();
    _pendingThemeCover = null;
    _pendingThemeGeneration = null;
    _openedGeneration = null;
    _failedGeneration = null;
    _progressiveGeneration = null;
    _progressiveCacheFuture = null;
    _progressiveFallbackGeneration = null;
    _progressiveResumePosition = null;
    _notifyDownloadProgress(null);
    _position = Duration.zero;
    _duration = Duration.zero;

    final picId = song.picId.isNotEmpty ? song.picId : song.id;
    _currentMediaItem = MediaItem(
      id: song.id,
      title: song.name,
      artist: song.singer,
      album: song.album.isNotEmpty ? song.album : '音乐',
      artUri: song.cover.startsWith('file:') ? Uri.tryParse(song.cover) : null,
    );
    try {
      await _audioHandler?.updateMediaItem(_currentMediaItem!);
    } catch (_) {}

    await _stopPlayerSerialized();
    final coverCache = CoverCacheService();
    final localCover = await coverCache.getLocalPath(picId);
    if (currentGen != _playGeneration) return false;
    if (localCover != null) {
      song.cover = Uri.file(localCover).toString();
      _currentMediaItem =
          _currentMediaItem!.copyWith(artUri: Uri.file(localCover));
      try {
        await _audioHandler?.updateMediaItem(_currentMediaItem!);
      } catch (_) {}
    }

    _notifyProgress(Duration.zero, Duration.zero);
    _notifySongChange(song);

    unawaited(_hydrateSongDetails(song, currentGen));
    await _prepareAndPlayAudio(song, currentGen, play: play);
    return currentGen == _playGeneration &&
        _openedGeneration == currentGen &&
        _failedGeneration != currentGen;
  }

  Future<void> _hydrateSongDetails(Song song, int generation) async {
    final playId = song.lyricId.isNotEmpty ? song.lyricId : song.id;
    final picId = song.picId.isNotEmpty ? song.picId : song.id;
    final cachedLyric = await LyricCacheService().load(playId);
    if (generation != _playGeneration) return;
    final cachedCover = await CoverCacheService().load(picId);
    if (generation != _playGeneration) return;
    if (cachedLyric != null && cachedLyric.isNotEmpty) {
      _applyLyric(song, playId, cachedLyric);
    }
    if (cachedCover != null) {
      await _applyLocalCover(song, picId, cachedCover, generation);
      if (generation != _playGeneration) return;
    }

    final needsLyric = cachedLyric == null || cachedLyric.isEmpty;
    final needsCover = cachedCover == null;
    if (!needsLyric && !needsCover) return;

    try {
      final details = await MusicApi.getTrackDetails(playId);
      if (generation != _playGeneration) return;
      final lyricText = details.lyric;
      if (needsLyric && lyricText.isNotEmpty) {
        final localLyric =
            await LyricCacheService().saveAndLoad(playId, lyricText);
        if (generation != _playGeneration) return;
        if (localLyric != null) _applyLyric(song, playId, localLyric);
      }

      if (needsCover) {
        final coverUrl =
            details.song.cover.isNotEmpty ? details.song.cover : song.cover;
        if (generation != _playGeneration) return;
        if (coverUrl.isNotEmpty) {
          final coverBytes = await CoverCacheService().resolve(picId, coverUrl);
          if (generation != _playGeneration) return;
          if (coverBytes != null) {
            await _applyLocalCover(song, picId, coverBytes, generation);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _applyLocalCover(
    Song song,
    String picId,
    Uint8List coverBytes,
    int generation,
  ) async {
    if (generation != _playGeneration) return;
    _pendingThemeCover = coverBytes;
    _pendingThemeGeneration = generation;
    if (_openedGeneration == generation && isPlaying) {
      _applyPendingThemeForPlayback(generation);
    }
    final localCover = await CoverCacheService().getLocalPath(picId);
    if (generation != _playGeneration) return;
    final artUri = localCover == null ? null : Uri.file(localCover);
    if (artUri == null) return;
    song.cover = artUri.toString();
    _currentMediaItem = _currentMediaItem?.copyWith(artUri: artUri);
    try {
      if (_currentMediaItem != null) {
        await _audioHandler?.updateMediaItem(_currentMediaItem!);
      }
    } catch (_) {}
    _notifySongChange(song);
  }

  void _applyPendingThemeForPlayback(int? generation) {
    final coverBytes = _pendingThemeCover;
    if (generation == null ||
        generation != _playGeneration ||
        _pendingThemeGeneration != generation ||
        coverBytes == null) {
      return;
    }
    _pendingThemeCover = null;
    _pendingThemeGeneration = null;
    unawaited(ThemeService.updateFromCover(coverBytes));
  }

  void _applyLyric(Song song, String playId, String lyric) {
    for (final item in queue) {
      final lyricId = item.lyricId.isNotEmpty ? item.lyricId : item.id;
      if (lyricId == playId) item.lyric = lyric;
    }
    song.lyric = lyric;
    _notifySongChange(song);
  }

  Future<void> _prepareAndPlayAudio(
    Song song,
    int generation, {
    bool play = true,
    Duration resumePosition = Duration.zero,
  }) async {
    final player = _player;
    if (player == null) return;
    var quality = 0;
    final cachedFile = await AudioCacheService().findBestCachedFile(song.id);
    if (generation != _playGeneration) return;
    if (cachedFile != null) {
      _currentPlayingBr = _extractBrFromPath(cachedFile.path);
      _cachedPlaybackGeneration = generation;
      _cachedPlaybackPath = cachedFile.path;
      _cachedPlayRequested = play;
      final opened = await _openMedia(
        Media(Uri.file(cachedFile.path).toString()),
        generation,
        play: play,
        resumePosition: resumePosition,
        decryptionKey: cachedFile.decryptionKey,
        reportFailure: false,
      );
      if (generation != _playGeneration) return;
      if (!opened) await _recoverFromCachedPlayback(generation);
      return;
    }
    _clearCachedPlaybackState();
    StreamSelection? selection;
    try {
      selection = await MusicApi.resolveStream(song.id);
      if (selection.bitrateKbps > 0) quality = selection.bitrateKbps;
    } catch (_) {}
    if (generation != _playGeneration) return;
    final downloadUrl = selection?.downloadUrl;
    if (generation != _playGeneration) return;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      await _handlePlaybackFailure(generation, '无法获取播放地址，请重试');
      return;
    }

    final key = selection?.aesKeyHex.trim() ?? '';
    if (key.isEmpty) {
      await _handlePlaybackFailure(generation, '歌曲解密密钥无效，请重试');
      return;
    }

    _currentPlayingBr = quality;
    final cacheCancellation = AudioCacheCancellationToken();
    final cacheFuture = AudioCacheService().download(
      song.id,
      downloadUrl,
      br: quality,
      backupUrl: selection?.backupUrl,
      aesKeyHex: key,
      cancellationToken: cacheCancellation,
      onProgress: (progress) {
        if (generation == _playGeneration &&
            _progressiveFallbackGeneration == generation) {
          _notifyDownloadProgress(progress);
        }
      },
      onPreparing: () {
        if (generation == _playGeneration &&
            _progressiveFallbackGeneration == generation) {
          _notifyDownloadProgress(-1.0);
        }
      },
    );
    _progressiveGeneration = generation;
    _progressiveCacheFuture = cacheFuture;
    _progressiveCacheCancellation = cacheCancellation;
    _progressivePlayRequested = play;
    _progressiveResumePosition = resumePosition;
    unawaited(_finishProgressiveCache(cacheFuture, generation));

    final opened = await _openProgressiveMedia(
      Media(
        downloadUrl,
        httpHeaders: const {'User-Agent': 'Mozilla/5.0'},
      ),
      key,
      generation,
      play: play,
      resumePosition: resumePosition,
    );
    if (generation != _playGeneration) return;
    if (!opened) await _fallbackFromProgressiveStream(generation);
  }

  Future<void> _finishProgressiveCache(
    Future<AudioCacheResult> future,
    int generation,
  ) async {
    await future;
    if (generation == _playGeneration && _progressiveGeneration == generation) {
      _notifyDownloadProgress(null);
      _progressiveCacheCancellation = null;
    }
  }

  Future<bool> _openProgressiveMedia(
    Media media,
    String aesKeyHex,
    int generation, {
    required bool play,
    Duration resumePosition = Duration.zero,
  }) async {
    return _openMedia(
      media,
      generation,
      play: play,
      resumePosition: resumePosition,
      decryptionKey: aesKeyHex,
      reportFailure: false,
    );
  }

  Future<void> _fallbackFromProgressiveStream(int generation) async {
    if (generation != _playGeneration ||
        _progressiveGeneration != generation ||
        _progressiveFallbackGeneration == generation) {
      return;
    }
    _progressiveFallbackGeneration = generation;
    _progressiveGeneration = null;
    final cacheFuture = _progressiveCacheFuture;
    _progressiveResumePosition = _position;
    _notifyDownloadProgress(0.0);
    try {
      try {
        await _player?.pause();
      } catch (_) {}
      final cacheResult = cacheFuture == null
          ? const AudioCacheResult.failure(AudioCacheFailureStage.download)
          : await cacheFuture;
      if (generation != _playGeneration) return;
      if (cacheResult.cancelled) {
        await _handlePlaybackFailure(generation, '缓存已清理，流式播放失败，请重试');
        return;
      }
      final localPath = cacheResult.path;
      if (localPath == null) {
        final message = switch (cacheResult.failureStage) {
          AudioCacheFailureStage.cacheWrite => '歌曲缓存失败，请检查存储空间',
          AudioCacheFailureStage.setup => '歌曲缓存初始化失败，请重试',
          _ => '流式播放失败，请检查网络后重试',
        };
        await _handlePlaybackFailure(generation, message);
        return;
      }
      _notifyDownloadProgress(null);
      _currentPlayingBr = _extractBrFromPath(localPath);
      final resumePosition = _progressiveResumePosition ?? _position;
      await _openMedia(
        Media(Uri.file(localPath).toString()),
        generation,
        play: _progressivePlayRequested,
        resumePosition: resumePosition,
        decryptionKey: cacheResult.decryptionKey,
      );
      if (generation == _playGeneration) {
        _progressiveCacheFuture = null;
        _progressiveCacheCancellation = null;
        _progressiveResumePosition = null;
      }
    } finally {
      if (_progressiveFallbackGeneration == generation) {
        _progressiveFallbackGeneration = null;
      }
    }
  }

  Future<void> _recoverFromCachedPlayback(int generation) async {
    final path = _cachedPlaybackPath;
    final song = currentSong;
    if (generation != _playGeneration ||
        _cachedPlaybackGeneration != generation ||
        _cachedRecoveryGeneration == generation ||
        path == null ||
        song == null) {
      return;
    }
    _cachedRecoveryGeneration = generation;
    _cachedPlaybackGeneration = null;
    _cachedPlaybackPath = null;
    final resumePosition = _position;
    _openedGeneration = null;
    try {
      await _stopPlayerSerialized();
      if (generation != _playGeneration) return;
      if (isTvApp) {
        await _handlePlaybackFailure(
          generation,
          '本地歌曲缓存无法播放，请在主页点击“清理缓存”后重试',
        );
        return;
      }
      final deleted = await AudioCacheService().deleteCachedFile(path);
      if (!deleted) {
        await _handlePlaybackFailure(
          generation,
          '本地歌曲缓存损坏且无法删除，请清理缓存后重试',
        );
        return;
      }
      await _prepareAndPlayAudio(
        song,
        generation,
        play: _cachedPlayRequested,
        resumePosition: resumePosition,
      );
    } finally {
      if (_cachedRecoveryGeneration == generation) {
        _cachedRecoveryGeneration = null;
      }
    }
  }

  String _lavfOptions({String? decryptionKey}) => [
        'seg_max_retry=5',
        'strict=experimental',
        'allowed_extensions=ALL',
        'protocol_whitelist=[udp,rtp,tcp,tls,data,file,http,https,crypto]',
        if (decryptionKey != null && decryptionKey.isNotEmpty)
          'decryption_key=$decryptionKey',
      ].join(',');

  Future<bool> _openMedia(
    Media media,
    int generation, {
    required bool play,
    Duration resumePosition = Duration.zero,
    String? decryptionKey,
    bool reportFailure = true,
  }) async {
    return _withMediaOperation(() async {
      final player = _player;
      if (player == null || generation != _playGeneration) return false;
      if (play && !await _activatePlaybackSession()) {
        await _handlePlaybackFailure(generation, '无法取得音频播放权限');
        return false;
      }
      if (generation != _playGeneration) return false;
      try {
        final nativePlayer = player.platform;
        if (nativePlayer is NativePlayer) {
          if (decryptionKey != null) {
            await nativePlayer.setProperty('cache', 'yes');
            await nativePlayer.setProperty('cache-on-disk', 'no');
            await nativePlayer.setProperty('cache-pause', 'yes');
            await nativePlayer.setProperty('cache-pause-initial', 'yes');
            await nativePlayer.setProperty('cache-pause-wait', '8');
            await nativePlayer.setProperty('demuxer-readahead-secs', '8');
          }
          await nativePlayer.setProperty(
            'demuxer-lavf-o',
            _lavfOptions(decryptionKey: decryptionKey),
          );
        }
        if (generation != _playGeneration) return false;
        _openedGeneration = generation;
        await player.open(media, play: play);
        if (generation != _playGeneration) return false;
        if (resumePosition > Duration.zero) await player.seek(resumePosition);
        return true;
      } catch (_) {
        if (reportFailure) {
          await _handlePlaybackFailure(generation, '播放失败，请重试');
        }
        return false;
      }
    });
  }

  Future<T> _withMediaOperation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _mediaOperationTail = _mediaOperationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _stopPlayerSerialized() {
    return _withMediaOperation(() async {
      _suppressCompletion = true;
      try {
        await _player?.stop();
      } catch (_) {
      } finally {
        _suppressCompletion = false;
      }
    });
  }

  void _cancelProgressiveCache() {
    _progressiveCacheCancellation?.cancel();
    _progressiveCacheCancellation = null;
    _progressiveCacheFuture = null;
    _progressiveGeneration = null;
    _progressiveFallbackGeneration = null;
    _progressiveResumePosition = null;
  }

  void _clearCachedPlaybackState() {
    _cachedPlaybackGeneration = null;
    _cachedRecoveryGeneration = null;
    _cachedPlaybackPath = null;
  }

  Future<void> _handlePlaybackFailure(int generation, String message) async {
    if (generation != _playGeneration || _failedGeneration == generation) {
      return;
    }
    _failedGeneration = generation;
    _openedGeneration = null;
    _notifyDownloadProgress(null);
    try {
      await _player?.pause();
    } catch (_) {}
    await _deactivatePlaybackSession();
    _notifyPlaybackError(message);
  }

  /// Extracts the quality value from the encrypted cache filename.
  int _extractBrFromPath(String path) {
    final name = path.split('/').last.split('\\').last;
    final match = RegExp(r'_(\d+)\.encrypted\.m4a$', caseSensitive: false)
        .firstMatch(name);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 999;
    }
    return 999;
  }

  /// Downloads the current song at the best available quality, then resumes it
  /// from the complete local cache file.
  Future<void> redownloadCurrentAtNewQuality() async {
    final song = currentSong;
    if (song == null) return;
    final currentGen = ++_playGeneration;
    _cancelProgressiveCache();
    _clearCachedPlaybackState();
    final wasPlaying = isPlaying;
    final resumePosition = position;
    _openedGeneration = null;
    _failedGeneration = null;
    final player = _player;
    if (player == null) return;
    await _stopPlayerSerialized();
    if (currentGen != _playGeneration) return;
    _notifyDownloadProgress(-1.0);
    await _prepareAndPlayAudio(
      song,
      currentGen,
      play: wasPlaying,
      resumePosition: resumePosition,
    );
  }

  void dispose() {
    _cancelProgressiveCache();
    _clearCachedPlaybackState();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _errorSub?.cancel();
    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();
    unawaited(_deactivatePlaybackSession());
    _player?.dispose();
    _player = null;
    _audioHandler = null;
    _pendingThemeCover = null;
    _pendingThemeGeneration = null;
    _initialized = false;
  }
}

class _AudioPlayerTask extends BaseAudioHandler {
  static const _nowPlayingChannel = MethodChannel('com.music/nowplaying');

  String? _pauseReason;
  bool _resumeAfterInterruption = false;
  DateTime _lastNowPlayingSync = DateTime.fromMillisecondsSinceEpoch(0);

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
            await ps.pause();
          } else if (event == 'resume') {
            if (reason == 'interruption' && _resumeAfterInterruption) {
              _resumeAfterInterruption = false;
              _pauseReason = null;
              await ps.play();
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
      _syncNowPlaying(force: true);
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
        _syncNowPlaying(force: true);
      }
    });

    ps.addSongChangeListener((song) {
      final item = ps._currentMediaItem;
      if (item != null) {
        mediaItem.add(item);
        _syncNowPlaying(force: true);
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

  void _syncNowPlaying({bool force = false}) {
    // The custom channel is implemented by the iOS runner only. Android and
    // TV are already handled by audio_service's native notification/session.
    if (!Platform.isIOS) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastNowPlayingSync).inMilliseconds < 1000) {
      return;
    }
    _lastNowPlayingSync = now;
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
  Future<void> play() async {
    await PlayerService().play();
  }

  @override
  Future<void> pause() async => PlayerService().pause();

  @override
  Future<void> stop() async => PlayerService().stop();

  @override
  Future<void> seek(Duration position) async => PlayerService().seek(position);

  @override
  Future<void> fastForward() async =>
      PlayerService().seekRelative(const Duration(seconds: 10));

  @override
  Future<void> rewind() async =>
      PlayerService().seekRelative(const Duration(seconds: -10));

  @override
  Future<void> skipToNext() async => PlayerService().next();

  @override
  Future<void> skipToPrevious() async => PlayerService().prev();
}
