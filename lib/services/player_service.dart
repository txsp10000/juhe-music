import 'dart:async';
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

  /// 当前播放的 MediaItem（替代已废弃的 AudioSource.tag）
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

  // 多监听器列表（方案3：避免页面间互相覆盖回调）
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

  // 快进/快退：纯虚拟位置方案（与 TV 逻辑一致）
  bool _seekMode = false;
  int _virtualPosMs = 0;
  Timer? _seekResumeTimer;

  // 暴露 seekMode 给外部判断
  bool get isSeeking => _seekMode;

  // 歌词独立轮询定时器
  Timer? _lyricTimer;

  /// 初始化 audio_service 和 just_audio
  static Future<void> init() async {
    final instance = PlayerService();

    // 初始化 audio_service（用于锁屏控制 + CarPlay Now Playing）
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

    // 进度更新统一由 _lyricTimer 驱动
    instance._player.playerStateStream.listen((state) {
      instance.onPlayStateChanged?.call(state.playing);
      if (state.processingState == ProcessingState.completed &&
          !instance._seekMode) {
        instance._onComplete();
      }
    });
    // 监听 duration 变化，更新 Now Playing
    instance._player.durationStream.listen((dur) {
      if (dur != null && instance._currentMediaItem != null) {
        try {
          AudioService.updateMediaItem(instance._currentMediaItem!.copyWith(duration: dur));
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
      _stopLyricTimer();
    } else {
      _player.play();
      _startLyricTimer();
    }
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= playlist.length) return;
    _currentIndex = index;
    final song = playlist[index];

    // 重置 seek 状态
    _seekMode = false;
    _seekResumeTimer?.cancel();
    _stopLyricTimer();

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

    // 1. 先处理歌词：本地缓存优先，没有则下载并缓存到本地
    final lyricCache = LyricCacheService();
    String? lyric = await lyricCache.load(playId);
    if (lyric == null || lyric.isEmpty) {
      // 本地无缓存，从网络下载歌词
      lyric = await MusicApi.getLyric(playId);
      if (lyric != null && lyric.isNotEmpty) {
        await lyricCache.save(playId, lyric);
        // 同步缓存 playlist 中同 lyricId 歌曲的歌词
        for (final s in playlist) {
          final sid = s.lyricId.isNotEmpty ? s.lyricId : s.id;
          if (sid == playId) {
            s.lyric = lyric!;
          }
        }
      }
    }
    song.lyric = lyric ?? '';

    // 2. 歌词已缓存完毕，再获取播放地址和封面
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

    // 3. 音频先完整下载到本地缓存，再播放
    final audioCache = AudioCacheService();
    final localPath = await audioCache.download(song.id, url);
    if (localPath == null) return;

    await _player.setAudioSource(AudioSource.file(localPath));

    _player.play();

    _startLyricTimer();

    _notifySongChange(song);
  }

  void _startLyricTimer() {
    _lyricTimer?.cancel();
    _lyricTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      // 拖动中直接跳过
      if (_seekMode) return;

      final posMs = _player.position.inMilliseconds;

      final durMs = _player.duration?.inMilliseconds ?? 0;
      final clampedMs = (durMs > 0 && posMs > durMs) ? durMs : posMs;
      _notifyProgress(
        Duration(milliseconds: clampedMs),
        _player.duration,
      );
    });
  }

  void _stopLyricTimer() {
    _lyricTimer?.cancel();
    _lyricTimer = null;
  }

  Future<String?> _fetchPlayUrl(Song song) async {
    try {
      final id = song.id;
      if (id.isEmpty) return null;
      return await MusicApi.getPlayUrl(id);
    } catch (_) {
      return null;
    }
  }

  /// 开始 seek：进入虚拟位置模式
  void seekStart() {
    _seekResumeTimer?.cancel();
    if (_seekMode) return;
    _seekMode = true;
    final realPos = _player.position.inMilliseconds;
    _virtualPosMs = realPos;
    // 安全超时：5秒内无 seekEnd 则自动提交，防止 seekMode 卡死
    _seekResumeTimer = Timer(const Duration(seconds: 5), () {
      if (_seekMode) seekEnd();
    });
  }

  /// seek 中：仅更新虚拟位置（不碰播放器）
  void seekMove(int deltaMs) {
    _seekResumeTimer?.cancel();
    if (!_seekMode) seekStart();
    final maxDur =
        _player.duration?.inMilliseconds ?? double.maxFinite.toInt();
    _virtualPosMs = (_virtualPosMs + deltaMs).clamp(0, maxDur);
    _notifyProgress(
      Duration(milliseconds: _virtualPosMs),
      _player.duration,
    );
  }

  /// 设置虚拟位置（slider 拖动时用）
  void seekVirtual(int targetMs) {
    _seekResumeTimer?.cancel();
    if (!_seekMode) seekStart();
    final maxDur =
        _player.duration?.inMilliseconds ?? double.maxFinite.toInt();
    _virtualPosMs = targetMs.clamp(0, maxDur);
    _notifyProgress(
      Duration(milliseconds: _virtualPosMs),
      _player.duration,
    );
  }

  /// 结束 seek：跳到虚拟位置，恢复播放
  Future<void> seekEnd() async {
    _seekResumeTimer?.cancel();
    if (!_seekMode) return;

    var targetPos = _virtualPosMs;
    final durMs = _player.duration?.inMilliseconds ?? 0;

    // 末尾留500ms余量，避免直接触发播放完成自动切歌
    if (durMs > 0) {
      targetPos = targetPos.clamp(0, durMs - 500);
    }

    // 微小位移跳过 seek
    if ((targetPos - _player.position.inMilliseconds).abs() < 100) {
      _seekMode = false;
      _notifyProgress(_player.position, _player.duration);
      return;
    }

    try {
      await _player.seek(Duration(milliseconds: targetPos));
      // 等待播放器稳定，然后直接用实际位置（不再冻结）
      await Future.delayed(const Duration(milliseconds: 80));
    } catch (_) {
      _seekMode = false;
      return;
    }

    _seekMode = false;

    // 用播放器实际位置，保证显示和音频一致
    _notifyProgress(_player.position, _player.duration);
  }

  /// 单次快进/快退（自动延时提交）
  void seekSingle(int deltaMs) {
    seekStart();
    seekMove(deltaMs);
    _seekResumeTimer?.cancel();
    _seekResumeTimer = Timer(const Duration(milliseconds: 800), () {
      seekEnd();
    });
  }

  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  void dispose() {
    _stopLyricTimer();
    _seekResumeTimer?.cancel();
    _player.dispose();
  }
}

/// audio_service 后台音频任务（iOS: 处理 CarPlay / 锁屏控制事件）
class _AudioPlayerTask extends BaseAudioHandler {
  final _player = PlayerService()._player;

  _AudioPlayerTask() {
    _player.playbackEventStream.listen((event) {
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        processingState: _mapProcessingState(_player.processingState),
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ));
    });

    // 歌曲 ready 时更新 MediaItem（包含实际时长）
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
        }
      }
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

  @override
  Future<void> seekForward(bool begin) async {
    final p = _player.position;
    final newPos = p + const Duration(seconds: 15);
    if (newPos < (_player.duration ?? Duration.zero)) {
      await _player.seek(newPos);
    }
  }

  @override
  Future<void> seekBackward(bool begin) async {
    final p = _player.position;
    final newPos = p - const Duration(seconds: 15);
    await _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
  }
}
