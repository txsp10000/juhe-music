import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../api/music_api.dart';

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

  // —— 简化 seek 后进度方案 ——
  // seek 后短暂冻结在目标位置，等播放器位置追上后切回原生位置
  int _seekFreezeMs = -1;         // seek 冻结目标位置（-1 = 无冻结）
  int _seekFreezeStartWallMs = 0; // 冻结开始的墙钟时间
  /// 冻结最大时长（毫秒），超过后无条件切回原生位置
  /// 本地缓存后 seek 很快生效，冻结只需覆盖极短的位置上报延迟
  static const int _seekFreezeMaxMs = 600;
  /// 偏差阈值：播放器位置与冻结目标偏差小于此值时切回
  static const int _seekConvergeMs = 300;

  /// 当前歌曲的本地缓存音源，切歌时清理
  LockCachingAudioSource? _cachingSource;

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
    _seekFreezeMs = -1;
    _seekFreezeStartWallMs = 0;
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

    // 并行获取 URL + 封面 + 歌词
    final results = await Future.wait([
      _fetchPlayUrl(song),
      MusicApi.getCover(picId),
      MusicApi.getLyric(playId),
    ]);
    final url = results[0] as String?;
    final coverUrl = results[1] as String?;
    final lyric = results[2] as String?;

    if (lyric != null && lyric.isNotEmpty) {
      song.lyric = lyric;
    }

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

    // 关键：用 LockCachingAudioSource 边下边播（缓存到本地文件）
    // 远程 MP3 流式 seek 时 AVPlayer 只能按平均码率估算字节偏移，
    // VBR 文件没有帧索引会导致 seek 落点与请求时间不符
    // （表现为时间显示 1:12 但唱的不是 1:12 那句）。
    // 缓存成本地文件后可完整解析帧索引，seek 才能精准。
    final oldCache = _cachingSource;
    final cache = LockCachingAudioSource(Uri.parse(url));
    _cachingSource = cache;
    await _player.setAudioSource(cache);

    // 新音源已生效，再清理上一首的缓存文件，避免磁盘无限增长。
    // 注意：下载未完成时 clearCache 会抛错，这里静默忽略（残留文件在系统临时目录，
    // 会被 iOS 自动回收），不影响播放。
    if (oldCache != null) {
      try {
        await oldCache.clearCache();
      } catch (_) {}
    }

    _player.play();

    _startLyricTimer();

    _notifySongChange(song);
  }

  void _startLyricTimer() {
    _lyricTimer?.cancel();
    _lyricTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      // 拖动中直接跳过，沿用虚拟位置逻辑
      if (_seekMode) return;

      final realPosMs = _player.position.inMilliseconds;
      int posMs;

      // seek 冻结期：短暂显示目标位置，避免视觉回跳
      if (_seekFreezeMs >= 0) {
        final elapsed =
            DateTime.now().millisecondsSinceEpoch - _seekFreezeStartWallMs;
        final diff = (realPosMs - _seekFreezeMs).abs();

        // 切回原生位置的条件（满足任一）：
        // 1. 播放器位置已经追上冻结目标（偏差 < _seekConvergeMs）
        // 2. 冻结时间超过上限
        if (diff < _seekConvergeMs || elapsed > _seekFreezeMaxMs) {
          _seekFreezeMs = -1;
          _seekFreezeStartWallMs = 0;
          posMs = realPosMs;
        } else {
          // 仍在冻结期：显示目标位置
          posMs = _seekFreezeMs;
        }
      } else {
        // 正常播放：直接用播放器原生位置
        posMs = realPosMs;
      }

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
    _seekFreezeMs = -1;
    _seekFreezeStartWallMs = 0;
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
      _seekFreezeMs = -1;
      _seekFreezeStartWallMs = 0;
      _notifyProgress(_player.position, _player.duration);
      return;
    }

    try {
      await _player.seek(Duration(milliseconds: targetPos));
    } catch (_) {
      // seek 失败时重置状态
      _seekMode = false;
      _seekFreezeMs = -1;
      _seekFreezeStartWallMs = 0;
      return;
    }

    _seekMode = false;

    // 简化方案：seek 后冻结在目标位置，等播放器追上后切回原生
    // 这避免了墙钟补偿导致的长时间位置偏差
    _seekFreezeMs = targetPos;
    _seekFreezeStartWallMs = DateTime.now().millisecondsSinceEpoch;

    _notifyProgress(
      Duration(milliseconds: targetPos),
      _player.duration,
    );
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
    final cache = _cachingSource;
    _cachingSource = null;
    if (cache != null) {
      cache.clearCache().catchError((_) {});
    }
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
