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
  int _loopMode = 0;

  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < playlist.length
          ? playlist[_currentIndex]
          : null;
  int get currentIndex => _currentIndex;
  int get loopMode => _loopMode;
  set loopMode(int v) => _loopMode = v;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  void Function(Song song)? onSongChanged;
  void Function(Duration pos, Duration? dur)? onProgress;
  void Function(bool playing)? onPlayStateChanged;

  /// 初始化 audio_service 和 just_audio
  static Future<void> init() async {
    final instance = PlayerService();

    // 初始化 audio_service（用于锁屏控制 + CarPlay Now Playing）
    await AudioService.init(
      builder: () => _AudioPlayerTask(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.miaomiao.music.channel',
        androidNotificationChannelName: '苗苗music',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: false,
        androidShowNotificationBadge: false,
      ),
    );

    instance._player.positionStream.listen((pos) {
      instance.onProgress?.call(pos, instance._player.duration);
      // 同步更新 CarPlay/锁屏 进度
      AudioService.updatePosition(pos);
    });
    instance._player.playerStateStream.listen((state) {
      instance.onPlayStateChanged?.call(state.playing);
      if (state.processingState == ProcessingState.completed) {
        instance._onComplete();
      }
    });
    // 监听 duration 变化，更新 Now Playing
    instance._player.durationStream.listen((dur) {
      if (dur != null) {
        final tag = instance._player.audioSource?.tag;
        if (tag is MediaItem) {
          try {
            AudioService.updateMediaItem(tag.copyWith(duration: dur));
          } catch (_) {}
        }
      }
    });
  }

  void _onComplete() {
    if (_loopMode == 1) {
      _player.seek(Duration.zero);
      _player.play();
    } else if (_loopMode == 2) {
      if (_currentIndex < playlist.length - 1) playAt(_currentIndex + 1);
    } else {
      if (_currentIndex < playlist.length - 1) {
        playAt(_currentIndex + 1);
      } else if (playlist.isNotEmpty) {
        playAt(0);
      }
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

    final playId = song.lyricId.isNotEmpty ? song.lyricId : song.id;
    final picId = song.picId.isNotEmpty ? song.picId : song.id;

    // 先设置 MediaItem（先用占位信息，CarPlay 立即显示歌曲名）
    final mediaItem = MediaItem(
      id: song.id,
      title: song.name,
      artist: song.singer,
      album: song.album.isNotEmpty ? song.album : '苗苗music',
      artUri: song.cover.isNotEmpty ? Uri.parse(song.cover) : null,
    );
    try {
      await AudioService.setMediaItem(mediaItem);
    } catch (_) {}

    // 并行获取 URL + 封面
    final results = await Future.wait([
      _fetchPlayUrl(song),
      MusicApi.getCover(picId),
    ]);
    final url = results[0] as String?;
    final coverUrl = results[1] as String?;

    if (coverUrl != null && coverUrl.isNotEmpty) {
      song.cover = coverUrl;
      // 更新 CarPlay/锁屏 封面
      try {
        AudioService.updateMediaItem(mediaItem.copyWith(
          artUri: Uri.parse(coverUrl),
        ));
      } catch (_) {}
    }
    if (url == null || url.isEmpty) return;

    await _player.setAudioSource(AudioSource.uri(
      Uri.parse(url),
      tag: mediaItem.copyWith(
        artUri: song.cover.isNotEmpty ? Uri.parse(song.cover) : null,
      ),
    ));

    _player.play();

    // 异步获取歌词
    MusicApi.getLyric(playId).then((lyric) => song.lyric = lyric);

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

  void seekRelative(int deltaMs) {
    var newPos = _player.position + Duration(milliseconds: deltaMs);
    if (newPos < Duration.zero) {
      newPos = Duration.zero;
    } else if (_player.duration != null && newPos > _player.duration!) {
      newPos = _player.duration!;
    }
    _player.seek(newPos);
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
        final tag = _player.audioSource?.tag;
        if (tag is MediaItem) {
          final updated = tag.copyWith(
            duration: _player.duration ?? Duration.zero,
          );
          mediaItem.add(updated);
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
