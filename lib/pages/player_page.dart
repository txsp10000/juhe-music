import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/player_service.dart';
import '../services/favorites_service.dart';
import '../models/song.dart';
import 'playlist_page.dart';
import 'search_result_page.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _player = PlayerService();
  final _focusSeekBar = FocusNode();
  final _focusLoop = FocusNode();
  final _focusPrev = FocusNode();
  final _focusPlayPause = FocusNode();
  final _focusNext = FocusNode();
  final _focusFavorite = FocusNode();
  final _focusPlaylist = FocusNode();
  final _focusQuality = FocusNode();
  final _focusSearchSame = FocusNode();

  bool _isFavorite = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String _lyric = '';

  static const _qualityLabels = {
    'flac': 'FLAC 无损', '320k': '320kbps', '192k': '192kbps', '128k': '128kbps',
  };

  @override
  void initState() {
    super.initState();
    _player.onProgress = (pos, dur) {
      if (mounted) setState(() { _position = pos; _duration = dur ?? Duration.zero; });
    };
    _player.onPlayStateChanged = (_) => mounted ? setState(() {}) : null;
    _player.onSongChanged = (s) {
      if (mounted) { setState(() {}); _checkFavorite(); }
    };
    _syncState();
    _checkFavorite();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusSeekBar.requestFocus());
  }

  void _syncState() {
    if (_player.duration != null) _duration = _player.duration!;
    _position = _player.position;
  }

  Future<void> _checkFavorite() async {
    final song = _player.currentSong;
    if (song == null) return;
    _isFavorite = await FavoritesService.isFavorite(song);
    if (mounted) setState(() {});
  }

  void _toggleFavorite() async {
    final song = _player.currentSong;
    if (song == null) return;
    if (_isFavorite) {
      await FavoritesService.remove(song);
      _isFavorite = false;
      if (mounted) _showToast('已取消收藏');
    } else {
      await FavoritesService.save(song);
      _isFavorite = true;
      if (mounted) _showToast('已加入收藏');
    }
    if (mounted) setState(() {});
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2), backgroundColor: const Color(0xCC333333)),
    );
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _loopToggle() {
    _player.loopMode = (_player.loopMode + 1) % 3;
    setState(() {});
  }

  String get _loopLabel => switch (_player.loopMode) {
    0 => '列表循环', 1 => '单曲循环', _ => '顺序播放',
  };

  String get _currentQualityLabel => _qualityLabels[_player.currentQuality] ?? 'FLAC 无损';

  void _showQualityDialog() {
    final codes = ['flac', '320k', '192k', '128k'];
    final labels = ['FLAC 无损', '320k 极高', '192k 较高', '128k 标准'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171B26),
        title: const Text('选择音质', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++) ...{
              Focus(
                autofocus: i == 0,
                child: GestureDetector(
                  onTap: () { Navigator.pop(ctx); _player.switchQuality(codes[i]); setState(() {}); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x1A6890F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x336890F9)),
                    ),
                    child: Text(labels[i], style: const TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
              ),
            },
            const SizedBox(height: 12),
            Focus(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x1A6890F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x336890F9)),
                  ),
                  child: const Text('取消', textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF8F919A), fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSearchSameDialog() {
    final song = _player.currentSong;
    if (song == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171B26),
        title: const Text('搜索同名歌曲或歌手', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Focus(
              autofocus: true,
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SearchResultPage(keyword: song.name),
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x1A6890F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x336890F9)),
                  ),
                  child: Text('歌曲名: ${song.name}',
                      style: const TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ),
            Focus(
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SearchResultPage(keyword: song.singer),
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x1A6890F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x336890F9)),
                  ),
                  child: Text('歌手: ${song.singer}',
                      style: const TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Focus(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0x1A6890F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x336890F9)),
                  ),
                  child: const Text('取消', textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF8F919A), fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _focusSeekBar.dispose();
    _focusLoop.dispose();
    _focusPrev.dispose();
    _focusPlayPause.dispose();
    _focusNext.dispose();
    _focusFavorite.dispose();
    _focusPlaylist.dispose();
    _focusQuality.dispose();
    _focusSearchSame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = _player.currentSong;
    if (song == null) return const Scaffold(body: SizedBox());

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0F14),
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
              // Song info + lyrics area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(52, 24, 52, 0),
                  child: Row(
                    children: [
                      // Left: song info
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(song.name,
                                style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 10),
                            Text(song.singer,
                                style: const TextStyle(color: Color(0xFFF4F4F7), fontSize: 17)),
                            const SizedBox(height: 16),
                            Text(_currentQualityLabel,
                                style: const TextStyle(color: Color(0xFF6890F9), fontSize: 14)),
                            const SizedBox(height: 10),
                            // Quality button
                            _textButton(_focusQuality, '切换音质', _showQualityDialog),
                            const SizedBox(height: 10),
                            // Search same button
                            _textButton(_focusSearchSame, '搜索同名歌曲或歌手', _showSearchSameDialog),
                          ],
                        ),
                      ),
                      const SizedBox(width: 40),
                      // Right: lyrics
                      SizedBox(
                        width: 440,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_firstLyric(song.lyric),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Color(0xFF6C97FF), fontSize: 23, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Bottom control area
              Container(
                color: const Color(0xEE09090C),
                padding: const EdgeInsets.fromLTRB(58, 10, 58, 16),
                child: Column(
                  children: [
                    // Seekbar
                    _seekBarBox(),
                    // Time
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(_position), style: const TextStyle(color: Color(0xFFF5F5F8), fontSize: 12)),
                          Text(_fmt(_duration), style: const TextStyle(color: Color(0xFFF5F5F8), fontSize: 12)),
                        ],
                      ),
                    ),
                    // Controls
                    SizedBox(
                      height: 80,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Loop
                          _iconButton(_focusLoop, Icons.repeat, 54, _loopToggle,
                              label: _loopLabel),
                          const SizedBox(width: 14),
                          _iconButton(_focusPrev, Icons.skip_previous, 58, () { _player.prev(); }),
                          const SizedBox(width: 14),
                          _iconButton(_focusPlayPause,
                              _player.isPlaying ? Icons.pause : Icons.play_arrow, 64,
                              () { _player.togglePlayPause(); }),
                          const SizedBox(width: 14),
                          _iconButton(_focusNext, Icons.skip_next, 58, () { _player.next(); }),
                          const SizedBox(width: 14),
                          _iconButton(_focusFavorite,
                              _isFavorite ? Icons.favorite : Icons.favorite_border, 54,
                              _toggleFavorite,
                              iconColor: _isFavorite ? Colors.red : Colors.white),
                          const SizedBox(width: 14),
                          _iconButton(_focusPlaylist, Icons.queue_music, 54, () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const PlaylistPage()));
                          }),
                        ],
                      ),
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

  String _firstLyric(String? lyric) {
    if (lyric == null || lyric.isEmpty) return '歌词加载中...';
    return lyric.split('\n').firstWhere((l) => l.trim().isNotEmpty,
        orElse: () => '歌词加载中...').replaceAll(RegExp(r'\[.*?\]'), '').trim();
  }

  Widget _seekBarBox() {
    return GestureDetector(
      child: Focus(
        focusNode: _focusSeekBar,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) { _player.seekRelative(-5000); return KeyEventResult.handled; }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) { _player.seekRelative(5000); return KeyEventResult.handled; }
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedBuilder(
          animation: _focusSeekBar,
          builder: (_, __) => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: _focusSeekBar.hasFocus
                  ? Border.all(color: const Color(0xFF6890F9), width: 2)
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: LinearProgressIndicator(
              value: _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0,
              backgroundColor: const Color(0xFF2A2D3A),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6890F9)),
              minHeight: 6,
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton(FocusNode node, IconData icon, double size, VoidCallback onTap,
      {String? label, Color? iconColor}) {
    return GestureDetector(
      onTap: onTap,
      child: Focus(
        focusNode: node,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) { onTap(); return KeyEventResult.handled; }
          return KeyEventResult.ignored;
        },
        child: AnimatedBuilder(
          animation: node,
          builder: (_, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  color: node.hasFocus ? const Color(0x1A6890F9) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: node.hasFocus ? Border.all(color: const Color(0xFF6890F9), width: 2) : null,
                ),
                child: Icon(icon, color: iconColor ?? Colors.white, size: size * 0.45),
              ),
              if (label != null) ...[
                const SizedBox(height: 3),
                Text(label, style: const TextStyle(color: Color(0xFF8F919A), fontSize: 10)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _textButton(FocusNode node, String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Focus(
        focusNode: node,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) { onTap(); return KeyEventResult.handled; }
          return KeyEventResult.ignored;
        },
        child: AnimatedBuilder(
          animation: node,
          builder: (_, __) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: node.hasFocus ? const Color(0x1A6890F9) : const Color(0x226890F9),
              borderRadius: BorderRadius.circular(8),
              border: node.hasFocus ? Border.all(color: const Color(0xFF6890F9), width: 2) : null,
            ),
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ),
      ),
    );
  }
}
