import 'package:flutter/material.dart';
import '../services/player_service.dart';
import '../services/favorites_service.dart';
import '../models/song.dart';
import '../utils/toast.dart';
import 'playlist_page.dart';
import 'search_result_page.dart';

/// LRC 歌词行
class _LrcLine {
  final int timeMs;
  final String text;
  const _LrcLine(this.timeMs, this.text);
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _player = PlayerService();
  bool _isFavorite = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<_LrcLine> _parsedLrc = [];

  @override
  void initState() {
    super.initState();
    _player.onProgress = (pos, dur) {
      if (mounted) setState(() { _position = pos; _duration = dur ?? Duration.zero; });
    };
    _player.onPlayStateChanged = (_) => mounted ? setState(() {}) : null;
    _player.onSongChanged = (s) {
      if (mounted) {
        _parsedLrc = _parseLrc(s.lyric);
        setState(() {});
        _checkFavorite();
      }
    };
    _syncState();
    _checkFavorite();
  }

  void _syncState() {
    if (_player.duration != null) _duration = _player.duration!;
    _position = _player.position;
    final song = _player.currentSong;
    if (song != null && _parsedLrc.isEmpty) {
      _parsedLrc = _parseLrc(song.lyric);
    }
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
    Toast.show(context, msg);
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _showSearchSameSheet() {
    final song = _player.currentSong;
    if (song == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('搜索同名歌曲或歌手', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.music_note, color: Color(0xFF6890F9)),
              title: Text('歌曲名: ${song.name}', style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => SearchResultPage(keyword: song.name)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.person, color: Color(0xFF6890F9)),
              title: Text('歌手: ${song.singer}', style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => SearchResultPage(keyword: song.singer)));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 解析 LRC 歌词
  List<_LrcLine> _parseLrc(String? lyric) {
    if (lyric == null || lyric.isEmpty) return [];
    final lines = <_LrcLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})(?:[.:](\d{2,3}))?\](.*)');
    for (final line in lyric.split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        var msStr = match.group(3);
        var ms = 0;
        if (msStr != null) {
          ms = int.parse(msStr);
          if (msStr.length == 2) ms *= 10;
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

  /// 获取当前播放位置对应的歌词行
  int _currentLrcIndex() {
    if (_parsedLrc.isEmpty) return -1;
    final posMs = _position.inMilliseconds;
    var idx = -1;
    for (var i = 0; i < _parsedLrc.length; i++) {
      if (_parsedLrc[i].timeMs <= posMs) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  Widget _buildLyricArea() {
    if (_parsedLrc.isEmpty) return const SizedBox.shrink();

    final currentIdx = _currentLrcIndex();
    final lines = <Widget>[];

    // 上一行
    if (currentIdx > 0) {
      lines.add(Text(
        _parsedLrc[currentIdx - 1].text,
        style: const TextStyle(color: Color(0xFF5A5D6E), fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
      lines.add(const SizedBox(height: 6));
    }

    // 当前行
    if (currentIdx >= 0) {
      lines.add(Text(
        _parsedLrc[currentIdx].text,
        style: const TextStyle(color: Color(0xFF6890F9), fontSize: 16, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
      lines.add(const SizedBox(height: 6));
    }

    // 下一行
    if (currentIdx >= 0 && currentIdx + 1 < _parsedLrc.length) {
      lines.add(Text(
        _parsedLrc[currentIdx + 1].text,
        style: const TextStyle(color: Color(0xFF5A5D6E), fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Column(
        key: ValueKey(currentIdx),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: lines,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = _player.currentSong;
    if (song == null) return const Scaffold(body: SizedBox());

    final hasLrc = _parsedLrc.isNotEmpty;
    final lyricText = !hasLrc && song.lyric.isNotEmpty ? _firstLyric(song.lyric) : null;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0F14),
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(child: _buildCenterContent(song, lyricText)),
              _buildBottomActions(),
              _buildSeekBar(),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
          ),
          const Spacer(),
          Column(
            children: [
              const Text('正在播放', style: TextStyle(color: Color(0xFF8F919A), fontSize: 12)),
              const Text('24bit 无损', style: TextStyle(color: Color(0xFF6890F9), fontSize: 11)),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlaylistPage())),
            child: const Icon(Icons.queue_music, color: Colors.white, size: 26),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterContent(Song song, String? lyricText) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 专辑封面 + 文字覆盖层
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFF1E2030),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 10)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 封面图
                  song.cover.isNotEmpty
                      ? Image.network(song.cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultCover())
                      : _defaultCover(),
                  // 半透明遮罩 + 文字
                  Container(
                    color: const Color(0x88000000),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          song.name,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          song.singer,
                          style: const TextStyle(color: Color(0xFFF4F4F7), fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '24bit 无损',
                          style: TextStyle(color: Color(0xFF6890F9), fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 歌词区域
          if (_parsedLrc.isNotEmpty)
            _buildLyricArea()
          else if (lyricText != null)
            Text(
              lyricText,
              style: const TextStyle(color: Color(0xFF6C97FF), fontSize: 15),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          else
            const Text('歌词加载中...',
                style: TextStyle(color: Color(0xFF8F919A), fontSize: 15)),
        ],
      ),
    );
  }

  Widget _defaultCover() {
    return Container(
      color: const Color(0xFF2A2D3A),
      child: const Center(child: Icon(Icons.music_note, color: Color(0xFF6890F9), size: 80)),
    );
  }

  Widget _buildSeekBar() {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: const Color(0xFF6890F9),
              inactiveTrackColor: const Color(0xFF2A2D3A),
              thumbColor: const Color(0xFF6890F9),
              overlayColor: const Color(0x226890F9),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: (v) {
                final newPos = Duration(milliseconds: (v * _duration.inMilliseconds).toInt());
                _player.seekRelative(newPos.inMilliseconds - _position.inMilliseconds);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(_position), style: const TextStyle(color: Color(0xFF8F919A), fontSize: 11)),
                Text(_fmt(_duration), style: const TextStyle(color: Color(0xFF8F919A), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.skip_previous, color: Colors.white, size: 36),
            onPressed: () => _player.prev(),
          ),
          GestureDetector(
            onTap: () => _player.togglePlayPause(),
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF6890F9),
              ),
              child: Icon(
                _player.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white, size: 36,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, color: Colors.white, size: 36),
            onPressed: () => _player.next(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: _toggleFavorite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorite ? Colors.red : const Color(0xFF8F919A),
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text(_isFavorite ? '已收藏' : '收藏', style: const TextStyle(color: Color(0xFF8F919A), fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _showSearchSameSheet,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search, color: Color(0xFF8F919A), size: 22),
                const SizedBox(height: 4),
                const Text('搜索同名', style: TextStyle(color: Color(0xFF8F919A), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _firstLyric(String? lyric) {
    if (lyric == null || lyric.isEmpty) return '歌词加载中...';
    return lyric.split('\n').firstWhere((l) => l.trim().isNotEmpty,
        orElse: () => '歌词加载中...').replaceAll(RegExp(r'\[.*?\]'), '').trim();
  }
}
