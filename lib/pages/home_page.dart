import 'package:flutter/material.dart';
import '../services/player_service.dart';
import '../models/song.dart';
import 'search_page.dart';
import 'favorites_page.dart';
import 'player_page.dart';

/// LRC 歌词行
class _LrcLine {
  final int timeMs;
  final String text;
  const _LrcLine(this.timeMs, this.text);
}

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
  List<_LrcLine> _parsedLrc = [];
  bool _isDragging = false;
  double _dragValue = 0.0;

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
    _bindPlayer();
    _syncState();
  }

  void _bindPlayer() {
    _player.addProgressListener(_onProgressUpdate);
    _player.addSongChangeListener(_onSongChange);
    _player.onPlayStateChanged = (_) => mounted ? setState(() {}) : null;
  }

  void _onProgressUpdate(Duration pos, Duration? dur) {
    if (mounted) setState(() { _position = pos; _duration = dur ?? Duration.zero; });
  }

  void _onSongChange(Song song) {
    if (mounted) {
      _parsedLrc = _parseLrc(song.lyric);
      setState(() => _currentSong = song);
    }
  }

  void _syncState() {
    _currentSong = _player.currentSong;
    if (_currentSong != null) _parsedLrc = _parseLrc(_currentSong!.lyric);
    if (_player.duration != null) _duration = _player.duration!;
    _position = _player.position;
  }

  /// 解析 LRC 歌词
  List<_LrcLine> _parseLrc(String? lyric) {
    if (lyric == null || lyric.isEmpty) return [];
    final lines = <_LrcLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\](.*)');
    for (final line in lyric.split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        var msStr = match.group(3);
        var ms = 0;
        if (msStr != null) {
          ms = int.parse(msStr);
          switch (msStr.length) {
            case 1: ms *= 100; break;
            case 2: ms *= 10; break;
          }
        }
        final text = match.group(4)?.trim() ?? '';
        if (text.isNotEmpty) {
          lines.add(_LrcLine((min * 60 + sec) * 1000 + ms, text));
        }
      }
    }
    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return lines;
  }

  /// 获取当前播放位置对应的歌词行（二分查找）
  int _currentLrcIndex() {
    if (_parsedLrc.isEmpty) return -1;
    final posMs = _position.inMilliseconds;
    int left = 0;
    int right = _parsedLrc.length - 1;
    int idx = -1;
    while (left <= right) {
      int mid = (left + right) ~/ 2;
      if (_parsedLrc[mid].timeMs <= posMs) {
        idx = mid;
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }
    return idx;
  }

  @override
  void dispose() {
    _player.removeProgressListener(_onProgressUpdate);
    _player.removeSongChangeListener(_onSongChange);
    _pulseController.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _buildProgressBar() {
    final max = _duration.inMilliseconds.toDouble();
    final current = _isDragging
        ? _dragValue
        : _position.inMilliseconds.toDouble().clamp(0.0, max);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: const Color(0xFF6890F9),
              inactiveTrackColor: const Color(0xFF2A2D3A),
              thumbColor: const Color(0xFF6890F9),
              overlayColor: const Color(0xFF6890F9).withOpacity(0.2),
            ),
            child: Slider(
              min: 0,
              max: max > 0 ? max : 1,
              value: max > 0 ? current.clamp(0.0, max) : 0,
              onChangeStart: (v) {
                _isDragging = true;
                _dragValue = v;
              },
              onChanged: (v) {
                setState(() => _dragValue = v);
              },
              onChangeEnd: (v) {
                _isDragging = false;
                _player.seek(Duration(milliseconds: v.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmt(_isDragging ? Duration(milliseconds: _dragValue.toInt()) : _position),
                  style: const TextStyle(color: Color(0xFF8F919A), fontSize: 11),
                ),
                Text(_fmt(_duration),
                    style: const TextStyle(color: Color(0xFF8F919A), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricArea() {
    if (_parsedLrc.isEmpty) return const SizedBox.shrink();

    final currentIdx = _currentLrcIndex();
    final lines = <Widget>[];

    // 前两行
    for (var i = currentIdx - 2; i < currentIdx; i++) {
      if (i >= 0) {
        lines.add(Text(
          _parsedLrc[i].text,
          style: const TextStyle(color: Color(0xFF5A5D6E), fontSize: 17),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ));
        lines.add(const SizedBox(height: 6));
      }
    }
    // 当前行
    if (currentIdx >= 0) {
      lines.add(Text(
        _parsedLrc[currentIdx].text,
        style: const TextStyle(color: Color(0xFF6890F9), fontSize: 21, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
      lines.add(const SizedBox(height: 6));
    }
    // 后三行
    for (var i = currentIdx + 1; i <= currentIdx + 3; i++) {
      if (i < _parsedLrc.length) {
        lines.add(Text(
          _parsedLrc[i].text,
          style: const TextStyle(color: Color(0xFF5A5D6E), fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ));
        if (i < currentIdx + 3) lines.add(const SizedBox(height: 6));
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Column(
          key: ValueKey(currentIdx),
          mainAxisSize: MainAxisSize.min,
          children: lines,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSong = _currentSong != null;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
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
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())).then((_) { _bindPlayer(); _syncState(); if (mounted) setState(() {}); }),
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
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesPage())).then((_) { _bindPlayer(); _syncState(); if (mounted) setState(() {}); }),
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
                child: Padding(
                  padding: const EdgeInsets.only(top: 30),
                  child: Column(
                    children: [
                      Text(
                        hasSong ? _currentSong!.name : '苗苗music',
                        style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasSong ? _currentSong!.singer : '搜索你喜欢的音乐',
                        style: const TextStyle(color: Color(0xFFF4F4F7), fontSize: 17),
                      ),
                      const Spacer(),
                      if (hasSong)
                        _buildLyricArea(),
                      if (!hasSong || _parsedLrc.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            hasSong ? '暂无歌词' : '点击右上角搜索框开始',
                            style: const TextStyle(color: Color(0xFF8F919A), fontSize: 15),
                          ),
                        ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
              if (hasSong)
                _buildProgressBar(),
              if (hasSong)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (_, child) => Transform.scale(
                      scale: _pulseAnimation.value,
                      child: child,
                    ),
                    child: GestureDetector(
                      onTap: () => _openPlayer(),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.graphic_eq, color: Colors.white, size: 32),
                      ),
                    ),
                  ),
                ),
              if (hasSong)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () => _player.prev(),
                        icon: const Icon(Icons.skip_previous, color: Colors.white, size: 48),
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        onPressed: () => _player.togglePlayPause(),
                        iconSize: 60,
                        icon: Icon(_player.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        onPressed: () => _player.next(),
                        icon: const Icon(Icons.skip_next, color: Colors.white, size: 48),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _openPlayer() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage())).then((_) {
      _bindPlayer();
      _syncState();
      if (mounted) setState(() {});
    });
  }
}
