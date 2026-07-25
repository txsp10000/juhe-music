import 'dart:async';
import 'dart:math';
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

  void Function(Song song)? onSongChanged;
  void Function(Duration pos, Duration? dur)? onProgress;
  void Function(bool playing)? onPlayStateChanged;

  // 快进/快退：纯虚拟位置方案（与 TV 逻辑一致）
  bool _seekMode = false;
  int _virtualPosMs = 0;
  Timer? _seekResumeTimer;
  int _lastSeekTarget = -1;
  int _seekEndTimeMs = 0;

  // 暴露 seekMode 给外部判断
  bool get isSeeking => _seekMode;

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

    instance._player.positionStream.listen((pos) {
      if (!instance._seekMode) {
        var posMs = pos.inMilliseconds;
        // seek后3秒内：跟踪最高位置，但不强制clamp（iOS seek精度不如Android）
        final now = DateTime.now().millisecondsSinceEpoch;
        if (instance._lastSeekTarget >= 0 &&
            now - instance._seekEndTimeMs < 3000 &&
            posMs > instance._lastSeekTarget) {
          instance._lastSeekTarget = posMs;
        }
        // 边界保护
        final durMs = instance._player.duration?.inMilliseconds ?? 0;
        if (durMs > 0 && posMs > durMs) {
          posMs = durMs;
        }
        instance.onProgress?.call(
          Duration(milliseconds: posMs),
          instance._player.duration,
        );
      }
    });
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
    } else {
      _player.play();
    }
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= playlist.length) return;
    _currentIndex = index;
    final song = playlist[index];

    // 重置 seek 状态，避免上一首歌的防跳保护污染新歌进度
    _seekMode = false;
    _seekResumeTimer?.cancel();
    _lastSeekTarget = -1;
    _seekEndTimeMs = 0;

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

    await _player.setAudioSource(AudioSource.uri(Uri.parse(url)));

    _player.play();

    onSongChanged?.call(song);
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
    final now = DateTime.now().millisecondsSinceEpoch;
    // 仅播放状态下才叠加已播放时长，暂停时进度静止，直接用真实位置
    _virtualPosMs = (_lastSeekTarget >= 0 &&
            now - _seekEndTimeMs < 3000 &&
            _player.playing)
        ? max(_lastSeekTarget + (now - _seekEndTimeMs), realPos)
        : realPos;
  }

  /// seek 中：仅更新虚拟位置（不碰播放器）
  void seekMove(int deltaMs) {
    _seekResumeTimer?.cancel();
    if (!_seekMode) seekStart();
    final maxDur =
        _player.duration?.inMilliseconds ?? double.maxFinite.toInt();
    _virtualPosMs = (_virtualPosMs + deltaMs).clamp(0, maxDur);
    onProgress?.call(
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
    onProgress?.call(
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

    // 位置差小于100ms直接跳过
    if ((targetPos - _player.position.inMilliseconds).abs() < 100) {
      _seekMode = false;
      _seekEndTimeMs = DateTime.now().millisecondsSinceEpoch;
      _lastSeekTarget = _player.position.inMilliseconds;
      onProgress?.call(_player.position, _player.duration);
      return;
    }

    _lastSeekTarget = targetPos;

    try {
      await _player.seek(Duration(milliseconds: targetPos));
    } catch (_) {}

    _seekMode = false;
    final realSeekPos = _player.position.inMilliseconds;
    _lastSeekTarget = realSeekPos;
    _seekEndTimeMs = DateTime.now().millisecondsSinceEpoch;
    onProgress?.call(
      Duration(milliseconds: realSeekPos),
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
