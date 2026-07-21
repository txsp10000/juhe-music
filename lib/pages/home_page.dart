import 'package:flutter/material.dart';
import '../services/player_service.dart';
import '../models/song.dart';
import 'search_page.dart';
import 'favorites_page.dart';
import 'player_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _player = PlayerService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Song? _currentSong;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
    _player.onProgress = (pos, dur) {
      if (mounted) setState(() { _position = pos; _duration = dur ?? Duration.zero; });
    };
    _player.onSongChanged = (song) {
      if (mounted) setState(() => _currentSong = song);
    };
    _player.onPlayStateChanged = (_) => mounted ? setState(() {}) : null;
    _syncState();
  }

  void _syncState() {
    _currentSong = _player.currentSong;
    if (_player.duration != null) _duration = _player.duration!;
    _position = _player.position;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _firstLyric(String? lyric) {
    if (lyric == null || lyric.isEmpty) return '';
    return lyric.split('\n').firstWhere((l) => l.trim().isNotEmpty,
        orElse: () => '').replaceAll(RegExp(r'\[.*?\]'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final hasSong = _currentSong != null;
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A1D28), Color(0xFF0D0F14)],
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0x226890F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.music_note, color: Color(0xFF6890F9), size: 24),
                    ),
                    const SizedBox(width: 10),
                    const Text('苗苗music',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0x33FFFFFF)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search, size: 20, color: Color(0xFF888888)),
                            SizedBox(width: 8),
                            Text('搜索', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesPage())),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0x33FFFFFF)),
                        ),
                        child: const Icon(Icons.favorite, size: 20, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasSong ? _currentSong!.name : '苗苗music',
                        style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasSong ? _currentSong!.singer : '搜索你喜欢的音乐',
                        style: const TextStyle(color: Color(0xFFF4F4F7), fontSize: 17),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        hasSong ? _firstLyric(_currentSong!.lyric) : '点击右上角搜索框开始',
                        style: const TextStyle(color: Color(0xFF8F919A), fontSize: 15),
                      ),
                      const SizedBox(height: 20),
                      if (hasSong)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  activeTrackColor: const Color(0xFF6890F9),
                                  inactiveTrackColor: const Color(0xFF2A2D3A),
                                  thumbColor: const Color(0xFF6890F9),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                ),
                                child: Slider(
                                  value: _duration.inMilliseconds > 0
                                      ? _position.inMilliseconds / _duration.inMilliseconds
                                      : 0,
                                  onChanged: (v) {
                                    final ms = (v * _duration.inMilliseconds).toInt();
                                    _player.seekRelative(ms - _position.inMilliseconds);
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_fmt(_position), style: const TextStyle(color: Color(0xFFF5F5F8), fontSize: 12)),
                                    Text(_fmt(_duration), style: const TextStyle(color: Color(0xFFF5F5F8), fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (hasSong) const SizedBox(height: 16),
                      if (hasSong)
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (_, child) => Transform.scale(
                            scale: _pulseAnimation.value,
                            child: child,
                          ),
                          child: GestureDetector(
                            onTap: () => _openPlayer(),
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.graphic_eq, color: Colors.white, size: 36),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (hasSong)
                Container(
                  color: const Color(0xEE09090C),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () => _player.prev(),
                        icon: const Icon(Icons.skip_previous, color: Colors.white, size: 32),
                      ),
                      const SizedBox(width: 14),
                      IconButton(
                        onPressed: () => _player.togglePlayPause(),
                        iconSize: 34,
                        icon: Icon(_player.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      IconButton(
                        onPressed: () => _player.next(),
                        icon: const Icon(Icons.skip_next, color: Colors.white, size: 32),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPlayer() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
  }
}
