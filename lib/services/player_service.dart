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
import 'settings_service.dart';
import 'theme_service.dart';

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
  bool _suppressCompletion = false;
  int _seekGeneration = 0;

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
            androidNotificationChannelId: 'com.qishui.music.channel',
            androidNotificationChannelName: '汽水音乐',
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
      _notifyPlayStateChanged(playing);
    });

    _completedSub = player.stream.completed.listen((completed) {
      if (completed) _onComplete();
    });
    _errorSub = player.stream.error.listen((_) {
      final generation = _openedGeneration;
      if (generation != null) {
        unawaited(_handlePlaybackFailure(generation, '播放失败，请重试'));
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

  void _onComplete() {
    if (_isSeeking || _suppressCompletion) return;
    if (_currentIndex < queue.length - 1) {
      playAt(_currentIndex + 1);
    } else if (queue.isNotEmpty) {
      if (_activeMode != null) {
        unawaited(_loadMoreModeSongsAndPlay());
      } else {
        playAt(0);
      }
    }
  }

  void prev() {
    if (queue.isEmpty) return;
    final newIdx = _currentIndex > 0 ? _currentIndex - 1 : queue.length - 1;
    playAt(newIdx);
  }

  void next() {
    if (queue.isEmpty) return;
    if (_currentIndex < queue.length - 1) {
      playAt(_currentIndex + 1);
    } else if (_activeMode != null) {
      unawaited(_loadMoreModeSongsAndPlay());
    } else {
      playAt(0);
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

  Future<void> _loadMoreModeSongsAndPlay() async {
    await loadMoreModeSongs(playNext: true);
  }

  Future<void> loadMoreModeSongs({bool playNext = false}) async {
    final mode = _activeMode;
    if (mode == null || _loadingModeSongs) return;
    _loadingModeSongs = true;
    final previousLength = queue.length;
    try {
      final songs = await MusicApi.getSceneTracks(mode.sceneModeId);
      if (!identical(_activeMode, mode) || songs.isEmpty) return;
      // Scene feeds may repeat items across requests. Keep the queue
      // stable while still allowing each scroll to contribute new songs.
      final existingIds = queue.map((song) => song.id).toSet();
      queue.addAll(songs.where((song) => existingIds.add(song.id)));
      if (playNext &&
          _currentIndex >= previousLength - 1 &&
          _currentIndex < queue.length - 1) {
        await playAt(_currentIndex + 1);
      }
    } catch (_) {
      // Keep the current song playable; a later next/completion retries.
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
      _activeMode = null;
      _queueSource = PlaybackQueueSource.regular;
      _currentIndex = -1;
      _currentMediaItem = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _openedGeneration = null;
      _suppressCompletion = true;
      try {
        await _player?.stop();
      } finally {
        _suppressCompletion = false;
      }
      await _deactivateAndroidAudioSession();
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

  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (_failedGeneration == _playGeneration &&
        _currentIndex >= 0 &&
        _currentIndex < queue.length) {
      await playAt(_currentIndex);
      return;
    }
    _resumeAfterAndroidInterruption = false;
    if (!await _activateAndroidAudioSession()) return;
    await _player?.play();
  }

  Future<void> pause() async {
    _resumeAfterAndroidInterruption = false;
    await _player?.pause();
    await _deactivateAndroidAudioSession();
  }

  Future<void> stop() async {
    _resumeAfterAndroidInterruption = false;
    _openedGeneration = null;
    _playGeneration++;
    _suppressCompletion = true;
    try {
      await _player?.stop();
    } finally {
      _suppressCompletion = false;
    }
    await _deactivateAndroidAudioSession();
    _notifyDownloadProgress(null);
  }

  bool _isSeeking = false;

  Future<void> seek(Duration position) async {
    final player = _player;
    if (player == null) return;
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

  Future<void> playAt(int index, {bool play = true}) async {
    if (index < 0 || index >= queue.length) return;
    if (_player == null) {
      try {
        await PlayerService.init();
      } catch (_) {
        _notifyPlaybackError('播放器初始化失败，请重新打开应用');
        return;
      }
    }
    final player = _player;
    if (player == null) {
      _notifyPlaybackError('播放器初始化失败，请重新打开应用');
      return;
    }
    _currentIndex = index;
    final song = queue[index];
    final currentGen = ++_playGeneration;
    _openedGeneration = null;
    _failedGeneration = null;
    _notifyDownloadProgress(null);
    _position = Duration.zero;
    _duration = Duration.zero;

    final picId = song.picId.isNotEmpty ? song.picId : song.id;
    _currentMediaItem = MediaItem(
      id: song.id,
      title: song.name,
      artist: song.singer,
      album: song.album.isNotEmpty ? song.album : '汽水音乐',
      artUri: song.cover.startsWith('file:') ? Uri.tryParse(song.cover) : null,
    );
    try {
      await _audioHandler?.updateMediaItem(_currentMediaItem!);
    } catch (_) {}

    _suppressCompletion = true;
    try {
      await player.stop();
    } catch (_) {
    } finally {
      _suppressCompletion = false;
    }
    final coverCache = CoverCacheService();
    final localCover = await coverCache.getLocalPath(picId);
    if (currentGen != _playGeneration) return;
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
    unawaited(_prepareAndPlayAudio(song, currentGen, play: play));
  }

  Future<void> _hydrateSongDetails(Song song, int generation) async {
    final playId = song.lyricId.isNotEmpty ? song.lyricId : song.id;
    final cachedLyric = await LyricCacheService().load(playId);
    if (generation != _playGeneration) return;
    if (cachedLyric != null && cachedLyric.isNotEmpty) {
      _applyLyric(song, playId, cachedLyric);
    }

    try {
      final details = await MusicApi.getTrackDetails(playId);
      if (generation != _playGeneration) return;
      final lyricText = details.lyric;
      if (lyricText.isNotEmpty) {
        final localLyric =
            await LyricCacheService().saveAndLoad(playId, lyricText);
        if (generation != _playGeneration) return;
        if (localLyric != null) _applyLyric(song, playId, localLyric);
      }

      if (!song.cover.startsWith('file:')) {
        final picId = song.picId.isNotEmpty ? song.picId : song.id;
        final coverUrl =
            details.song.cover.isNotEmpty ? details.song.cover : song.cover;
        if (generation != _playGeneration) return;
        if (coverUrl.isNotEmpty) {
          final coverBytes =
              await CoverCacheService().download(picId, coverUrl);
          if (generation != _playGeneration) return;
          if (coverBytes != null) {
            unawaited(ThemeService.updateFromCover(coverBytes));
          }
          final localCover = await CoverCacheService().getLocalPath(picId);
          if (generation != _playGeneration) return;
          final artUri = localCover == null ? null : Uri.file(localCover);
          if (artUri != null) song.cover = artUri.toString();
          _currentMediaItem = _currentMediaItem?.copyWith(artUri: artUri);
          try {
            if (_currentMediaItem != null) {
              await _audioHandler?.updateMediaItem(_currentMediaItem!);
            }
          } catch (_) {}
          _notifySongChange(song);
        }
      }
    } catch (_) {}
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
    int? requestedBr,
  }) async {
    final player = _player;
    if (player == null) return;
    final requestedQuality = requestedBr == null
        ? SettingsService().quality
        : AudioQuality.values.firstWhere(
            (candidate) => candidate.br == requestedBr,
            orElse: () => SettingsService().quality,
          );
    var quality = requestedQuality.br;
    final cachedPath = await AudioCacheService().findBestCachedFile(song.id);
    if (generation != _playGeneration) return;
    if (cachedPath != null) {
      _currentPlayingBr = _extractBrFromPath(cachedPath);
      await _openMedia(
        Media(Uri.file(cachedPath).toString()),
        generation,
        play: play,
        resumePosition: resumePosition,
      );
      return;
    }
    StreamSelection? selection;
    try {
      selection = await MusicApi.resolveStream(song.id, requestedQuality);
      if (selection.bitrateKbps > 0) quality = selection.bitrateKbps;
    } catch (_) {}
    if (generation != _playGeneration) return;
    final url = selection?.url;
    if (generation != _playGeneration) return;
    if (url == null || url.isEmpty) {
      await _handlePlaybackFailure(generation, '无法获取播放地址，请重试');
      return;
    }

    _currentPlayingBr = quality;
    _notifyDownloadProgress(0.0);
    final localPath = await AudioCacheService().download(
      song.id,
      url,
      br: quality,
      onProgress: (progress) {
        if (generation == _playGeneration) {
          _notifyDownloadProgress(progress);
        }
      },
    );
    if (generation != _playGeneration) return;
    if (localPath == null) {
      await _handlePlaybackFailure(generation, '歌曲下载失败，请检查网络后重试');
      return;
    }
    _notifyDownloadProgress(null);
    _currentPlayingBr = _extractBrFromPath(localPath);
    await _openMedia(
      Media(Uri.file(localPath).toString()),
      generation,
      play: play,
      resumePosition: resumePosition,
    );
  }

  Future<bool> _openMedia(
    Media media,
    int generation, {
    required bool play,
    Duration resumePosition = Duration.zero,
  }) async {
    final player = _player;
    if (player == null || generation != _playGeneration) return false;
    if (play && !await _activateAndroidAudioSession()) {
      await _handlePlaybackFailure(generation, '无法取得音频播放权限');
      return false;
    }
    _openedGeneration = generation;
    try {
      await player.open(media, play: play);
      if (generation != _playGeneration) return false;
      if (resumePosition > Duration.zero) await player.seek(resumePosition);
      return true;
    } catch (_) {
      await _handlePlaybackFailure(generation, '播放失败，请重试');
      return false;
    }
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
    await _deactivateAndroidAudioSession();
    _notifyPlaybackError(message);
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

  /// Downloads the current song at the selected quality, then resumes it
  /// from the complete local cache file.
  Future<void> redownloadCurrentAtNewQuality() async {
    final song = currentSong;
    if (song == null) return;
    final currentGen = ++_playGeneration;
    final wasPlaying = isPlaying;
    final resumePosition = position;
    final quality = SettingsService().quality.br;
    _openedGeneration = null;
    _failedGeneration = null;
    final player = _player;
    if (player == null) return;
    _suppressCompletion = true;
    try {
      await player.stop();
    } catch (_) {
    } finally {
      _suppressCompletion = false;
    }
    if (currentGen != _playGeneration) return;
    _notifyDownloadProgress(-1.0);
    await _prepareAndPlayAudio(
      song,
      currentGen,
      play: wasPlaying,
      resumePosition: resumePosition,
      requestedBr: quality,
    );
  }

  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _errorSub?.cancel();
    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();
    unawaited(_deactivateAndroidAudioSession());
    _player?.dispose();
    _player = null;
    _audioHandler = null;
    _initialized = false;
  }
}

class _AudioPlayerTask extends BaseAudioHandler {
  static const _nowPlayingChannel =
      MethodChannel('com.qishui.music/nowplaying');

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
  Future<void> play() async => PlayerService().play();

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
