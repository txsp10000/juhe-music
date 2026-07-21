import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../models/platform.dart';
import '../api/music_api.dart';

class PlayerService {
  static final PlayerService _instance = PlayerService._();
  factory PlayerService() => _instance;
  PlayerService._();

  final _player = AudioPlayer();
  final List<Song> playlist = [];
  int _currentIndex = -1;
  String _currentQuality = 'flac';
  int _loopMode = 0;

  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < playlist.length
          ? playlist[_currentIndex]
          : null;
  int get currentIndex => _currentIndex;
  String get currentQuality => _currentQuality;
  int get loopMode => _loopMode;
  set loopMode(int v) => _loopMode = v;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  void Function(Song song)? onSongChanged;
  void Function(Duration pos, Duration? dur)? onProgress;
  void Function(bool playing)? onPlayStateChanged;

  void init() {
    _player.positionStream.listen((pos) {
      onProgress?.call(pos, _player.duration);
    });
    _player.playerStateStream.listen((state) {
      onPlayStateChanged?.call(state.playing);
      if (state.processingState == ProcessingState.completed) {
        _onComplete();
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
      } else {
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
    try {
      final platform = Platform.fromCode(song.source) ?? Platform.qsvip;
      String url;
      if (platform == Platform.qsvip) {
        url = await MusicApi.qishuiGetUrl(song, quality: _currentQuality);
      } else {
        url = await MusicApi.getMusicUrl(platform, song, quality: _currentQuality);
      }
      await _player.setAudioSource(AudioSource.uri(
        Uri.parse(url),
        tag: MediaItem(
          id: song.id,
          title: song.name,
          artist: song.singer,
          album: song.album,
          artUri: song.cover.isNotEmpty ? Uri.parse(song.cover) : null,
        ),
      ));
      _player.play();
      MusicApi.getLyric(platform, song).then((lyric) => song.lyric = lyric);
    } catch (_) {
      try {
        final url = await MusicApi.qishuiGetUrl(song, quality: _currentQuality);
        await _player.setAudioSource(AudioSource.uri(
          Uri.parse(url),
          tag: MediaItem(
            id: song.id,
            title: song.name,
            artist: song.singer,
          ),
        ));
        _player.play();
      } catch (_) {}
    }
    onSongChanged?.call(song);
  }

  Future<void> switchQuality(String quality) async {
    _currentQuality = quality;
    final song = currentSong;
    if (song == null) return;
    final wasPlaying = _player.playing;
    final pos = _player.position;
    try {
      final platform = Platform.fromCode(song.source) ?? Platform.qsvip;
      String url;
      if (platform == Platform.qsvip) {
        url = await MusicApi.qishuiGetUrl(song, quality: quality);
      } else {
        url = await MusicApi.getMusicUrl(platform, song, quality: quality);
      }
      await _player.setAudioSource(AudioSource.uri(
        Uri.parse(url),
        tag: MediaItem(
          id: song.id,
          title: song.name,
          artist: song.singer,
          album: song.album,
          artUri: song.cover.isNotEmpty ? Uri.parse(song.cover) : null,
        ),
      ));
      await _player.seek(pos);
      if (wasPlaying) _player.play();
    } catch (_) {}
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

  void dispose() {
    _player.dispose();
  }
}
