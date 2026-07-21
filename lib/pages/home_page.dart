import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _focusGotoPlayer = FocusNode();
  final _focusSeekBar = FocusNode();
  final _focusSearch = FocusNode();
  final _focusFavorites = FocusNode();
  final _focusPrev = FocusNode();
  final _focusPlayPause = FocusNode();
  final _focusNext = FocusNode();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Song? _currentSong;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  StreamSubscription? _posSub;
  StreamSubscription? _songSub;

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
    _posSub = _player.onProgress?.call != null ? null : _setupListeners();
    _player.onProgress = (pos, dur) {
      if (mounted) setState(() { _position = pos; _duration = dur ?? Duration.zero; });
    };
    _player.onSongChanged = (song) {
      if (mounted) setState(() => _currentSong = song);
    };
    _player.onPlayStateChanged = (_) => mounted ? setState(() {}) : null;
    _syncState();
  }

  void _setupListeners() {
    _player.onProgress = (pos, dur) {
      if (mounted) setState(() { _position = pos; _duration = dur ?? Duration.zero; });
    };
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1D28), Color(0xFF0D0F14)],
          ),
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
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
                  // Search box
                  _focusableChip(
                    '搜索', Icons.search, _focusSearch,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
                  ),
                  const SizedBox(width: 12),
                  // Favorites button
                  _focusableChip(
                    '', null, _focusFavorites, icon: Icons.favorite, iconColor: Colors.red,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesPage())),
                  ),
                ],
              ),
            ),
            // Center content
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
                    // Seekbar
                    if (hasSong)
                      _focusableBox(
                        focusNode: _focusSeekBar,
                        onKeyLeft: () => _player.seekRelative(-5000),
                        onKeyRight: () => _player.seekRelative(5000),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            children: [
                              SizedBox(
                                width: 360,
                                child: LinearProgressIndicator(
                                  value: _duration.inMilliseconds > 0
                                      ? _position.inMilliseconds / _duration.inMilliseconds
                                      : 0,
                                  backgroundColor: const Color(0xFF2A2D3A),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6890F9)),
                                  minHeight: 4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 360,
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
                      ),
                    if (hasSong) const SizedBox(height: 16),
                    // Goto player button (pulse)
                    if (hasSong)
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (_, child) => Transform.scale(
                          scale: _pulseAnimation.value,
                          child: child,
                        ),
                        child: _focusableBox(
                          size: 72,
                          focusNode: _focusGotoPlayer,
                          onTap: () => _openPlayer(),
                          child: const Icon(Icons.graphic_eq, color: Colors.white, size: 36),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Bottom control bar
            if (hasSong)
              Container(
                color: const Color(0xEE09090C),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _focusableBox(focusNode: _focusPrev, onTap: () => _player.prev(),
                      child: const Icon(Icons.skip_previous, color: Colors.white, size: 32)),
                    const SizedBox(width: 14),
                    _focusableBox(focusNode: _focusPlayPause, size: 64, onTap: () => _player.togglePlayPause(),
                      child: Icon(_player.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 34)),
                    const SizedBox(width: 14),
                    _focusableBox(focusNode: _focusNext, onTap: () => _player.next(),
                      child: const Icon(Icons.skip_next, color: Colors.white, size: 32)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openPlayer() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
  }

  Widget _focusableChip(String label, IconData? ic, FocusNode node,
      {IconData? icon, Color? iconColor, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Focus(
        focusNode: node,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
            onTap?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedBuilder(
          animation: node,
          builder: (_, __) => Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: node.hasFocus ? const Color(0x1A6890F9) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: node.hasFocus
                  ? Border.all(color: const Color(0xFF6890F9), width: 2)
                  : Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null)
                  Icon(icon, size: 20, color: iconColor ?? Colors.white),
                if (icon != null && ic != null) const SizedBox(width: 6),
                if (ic != null) Icon(ic, size: 20, color: const Color(0xFF888888)),
                if (ic != null && label.isNotEmpty) const SizedBox(width: 8),
                if (label.isNotEmpty)
                  Text(label, style: TextStyle(color: ic != null ? const Color(0xFF888888) : Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _focusableBox({
    FocusNode? focusNode,
    double size = 56,
    VoidCallback? onTap,
    VoidCallback? onKeyLeft,
    VoidCallback? onKeyRight,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Focus(
        focusNode: focusNode,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              onTap?.call();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft && onKeyLeft != null) {
              onKeyLeft();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight && onKeyRight != null) {
              onKeyRight();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedBuilder(
          animation: focusNode ?? FocusNode(),
          builder: (_, __) => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: (focusNode?.hasFocus ?? false) ? const Color(0x1A6890F9) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: (focusNode?.hasFocus ?? false)
                  ? Border.all(color: const Color(0xFF6890F9), width: 2)
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
