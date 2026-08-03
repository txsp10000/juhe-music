import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/player_service.dart';
import '../services/favorites_service.dart';
import '../services/cover_cache_service.dart';
import '../models/song.dart';
import '../utils/toast.dart';
import '../api/music_api.dart';
import '../data/categories.dart';
import '../widgets/mode_drawer.dart';
import 'playlist_page.dart';
import 'search_page.dart';
import 'search_result_page.dart';
import 'favorites_page.dart';
import '../services/settings_service.dart';
import 'dart:typed_data';

/// LRC 歌词行
class _LrcLine {
  final int timeMs;
  final String text;
  const _LrcLine(this.timeMs, this.text);
}

class PlayerPage extends StatefulWidget {
  final bool isRoot;
  const PlayerPage({super.key, this.isRoot = false});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _player = PlayerService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isFavorite = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<_LrcLine> _parsedLrc = [];
  bool _isDragging = false;
  double _dragValue = 0.0;
  double? _downloadProgress;
  String _coverUrl = '';
  Uint8List? _coverBytes;

  // ─── 纯黑极简配色 ───
  static const _bgColor = Color(0xFF000000);
  static const _cardColor = Color(0xFF1A1A1A);
  static const _textSecondary = Color(0xFF999999);
  static const _textTertiary = Color(0xFF666666);

  @override
  void initState() {
    super.initState();
    _player.addProgressListener(_onProgressUpdate);
    _player.addSongChangeListener(_onSongChange);
    _player.addDownloadProgressListener(_onDownloadProgress);
    _player.addPlayStateListener(_onPlayStateChange);
    _syncState();
    _checkFavorite();
  }

  void _onProgressUpdate(Duration pos, Duration? dur) {
    if (mounted) {
      setState(() {
        _position = pos;
        _duration = dur ?? Duration.zero;
      });
      final song = _player.currentSong;
      if (song != null && _coverBytes == null && song.cover.isNotEmpty && song.cover != _coverUrl) {
        _loadCover(song);
      }
    }
  }

  void _onSongChange(Song s) {
    if (mounted) {
      _parsedLrc = _parseLrc(s.lyric);
      if (s.cover.isEmpty || s.cover != _coverUrl) {
        _coverBytes = null;
        _coverUrl = '';
      }
      setState(() {});
      _checkFavorite();
      _loadCover(s);
    }
  }

  void _onDownloadProgress(double? progress) {
    if (mounted) setState(() => _downloadProgress = progress);
  }

  void _onPlayStateChange(bool _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player.removeProgressListener(_onProgressUpdate);
    _player.removeSongChangeListener(_onSongChange);
    _player.removeDownloadProgressListener(_onDownloadProgress);
    _player.removePlayStateListener(_onPlayStateChange);
    super.dispose();
  }

  void _syncState() {
    if (_player.duration != null) _duration = _player.duration!;
    _position = _player.position;
    final song = _player.currentSong;
    if (song != null && _parsedLrc.isEmpty) {
      _parsedLrc = _parseLrc(song.lyric);
    }
    if (song != null) _loadCover(song);
  }

  Future<void> _loadCover(Song song) async {
    if (song.cover.isEmpty) return;
    if (song.cover == _coverUrl && _coverBytes != null) return;
    final url = song.cover;
    _coverUrl = url;
    _coverBytes = null;
    final picId = song.picId.isNotEmpty ? song.picId : song.id;
    final coverCache = CoverCacheService();
    final cached = await coverCache.load(picId);
    if (cached != null && mounted && _coverUrl == url) {
      setState(() => _coverBytes = cached);
      return;
    }
    if (url.startsWith('file://')) return;
    final downloaded = await coverCache.download(picId, url);
    if (downloaded != null && mounted && _coverUrl == url) {
      setState(() => _coverBytes = downloaded);
    } else {
      if (_coverUrl == url) _coverUrl = '';
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
      if (mounted) Toast.show(context, '已取消收藏');
    } else {
      await FavoritesService.save(song);
      _isFavorite = true;
      if (mounted) Toast.show(context, '已加入收藏');
    }
    if (mounted) setState(() {});
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

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
            case 1:
              ms *= 100;
              break;
            case 2:
              ms *= 10;
              break;
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

  void _showSearchSameSheet() {
    final song = _player.currentSong;
    if (song == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text('搜索同名歌曲或歌手',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.music_note, color: Colors.white),
                title: Text('歌曲名: ${song.name}',
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SearchResultPage(keyword: song.name, fromPlayer: true)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.person, color: Colors.white),
                title: Text('歌手: ${song.singer}',
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SearchResultPage(keyword: song.singer, fromPlayer: true)));
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text('音质',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ...AudioQuality.values.map((q) {
                final selected = SettingsService().quality == q;
                return ListTile(
                  title: Text(q.label,
                      style: TextStyle(
                          color: selected ? Colors.white : _textSecondary,
                          fontSize: 15,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                  trailing: selected
                      ? const Icon(Icons.check_circle, color: Colors.white, size: 20)
                      : null,
                  onTap: () async {
                    final oldBr = SettingsService().quality.br;
                    await SettingsService().setQuality(q);
                    Navigator.pop(ctx);
                    if (mounted) setState(() {});
                    if (q.br > oldBr) {
                      PlayerService().redownloadCurrentAtNewQuality();
                    }
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  String _currentBrLabel() {
    final br = _player.currentPlayingBr;
    switch (br) {
      case 128: return '128kbps';
      case 192: return '192kbps';
      case 320: return '320kbps';
      case 740: return '16bit 无损';
      case 999: return '24bit 无损';
      default: return '${br}kbps';
    }
  }

  String _qualityLabel() {
    switch (SettingsService().quality) {
      case AudioQuality.low128: return '128k';
      case AudioQuality.medium192: return '192k';
      case AudioQuality.high320: return '320k';
      case AudioQuality.lossless740: return '16bit';
      case AudioQuality.lossless999: return '24bit';
    }
  }

  void _showPlaylistSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      builder: (ctx) {
        final songs = _player.playlist;
        final currentIdx = _player.currentIndex;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text('播放列表 (${songs.length})',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Expanded(
                child: songs.isEmpty
                    ? const Center(
                        child: Text('暂无歌曲', style: TextStyle(color: _textSecondary, fontSize: 15)))
                    : ListView.builder(
                        itemCount: songs.length,
                        itemBuilder: (_, i) {
                          final s = songs[i];
                          final isCurrent = i == currentIdx;
                          return InkWell(
                            onTap: () {
                              _player.playAt(i);
                              Navigator.pop(ctx);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                color: isCurrent ? Colors.white.withOpacity(0.05) : Colors.transparent,
                                border: const Border(bottom: BorderSide(color: Color(0x08FFFFFF))),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 26,
                                    child: isCurrent
                                        ? const Icon(Icons.volume_up, color: Colors.white, size: 18)
                                        : Text('${i + 1}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(color: _textTertiary, fontSize: 13)),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(s.name,
                                            style: TextStyle(
                                                color: isCurrent ? Colors.white : _textSecondary,
                                                fontSize: 15,
                                                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal)),
                                        const SizedBox(height: 3),
                                        Text(s.singer,
                                            style: const TextStyle(color: _textTertiary, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loadAndPlay(PlaylistInfo pl) async {
    Toast.show(context, '正在加载「${pl.name}」...');
    try {
      final songs = await MusicApi.getPlaylist(pl.id);
      if (!mounted) return;
      if (songs.isEmpty) {
        Toast.show(context, '未找到歌曲');
        return;
      }
      _player.playlist.clear();
      _player.playlist.addAll(songs);
      _player.playAt(0);
    } catch (_) {
      if (!mounted) return;
      Toast.show(context, '加载失败，请重试');
    }
  }

  void _openFavorites() async {
    final songs = await FavoritesService.load();
    if (!mounted) return;
    if (songs.isEmpty) {
      Toast.show(context, '收藏列表为空');
      return;
    }
    _player.playlist.clear();
    _player.playlist.addAll(songs);
    _player.playAt(0);
  }

  void _randomPlay() async {
    final prefs = await SharedPreferences.getInstance();
    final pinned = prefs.getStringList('pinned_playlists') ?? [];
    final playlists = <PlaylistInfo>[];
    for (final s in pinned) {
      final idx = s.indexOf('|');
      if (idx > 0) {
        playlists.add(PlaylistInfo(s.substring(idx + 1), s.substring(0, idx)));
      }
    }
    if (playlists.isEmpty) {
      Toast.show(context, '请先置顶一些歌单');
      return;
    }
    final random = Random();
    _loadAndPlay(playlists[random.nextInt(playlists.length)]);
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final song = _player.currentSong;
    if (song == null && !widget.isRoot) {
      return const Scaffold(backgroundColor: _bgColor, body: SizedBox());
    }

    return Scaffold(
      key: widget.isRoot ? _scaffoldKey : null,
      backgroundColor: _bgColor,
      drawer: widget.isRoot
          ? ModeDrawer(
              onSelectPlaylist: _loadAndPlay,
              onOpenFavorites: _openFavorites,
              onRandomPlay: _randomPlay,
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(song),
            Expanded(
              child: song != null ? _buildSwipeableContent(song) : _buildEmptyState(),
            ),
            if (song != null) _buildDownloadProgress(),
            if (song != null) _buildBottomActions(),
            if (song != null) _buildTimeBar(),
            if (!widget.isRoot) _buildBottomTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_note_outlined, size: 72, color: _textTertiary),
          const SizedBox(height: 20),
          const Text(
            '点击左上角「模式选择」开始听歌',
            style: TextStyle(color: _textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: _textTertiary),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Text(
                '选择模式',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(Song? song) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          if (widget.isRoot)
            GestureDetector(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.menu, color: Colors.white, size: 24),
              ),
            )
          else
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
            ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (song != null) ...[
                  Text(
                    song.name,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${song.singer}  ${_currentBrLabel()}',
                    style: const TextStyle(color: _textSecondary, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ] else
                  const SizedBox.shrink(),
              ],
            ),
          ),
          if (!widget.isRoot)
            IconButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PlaylistPage(fromPlayer: true))),
              icon: const Icon(Icons.queue_music, color: Colors.white, size: 26),
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }

  // ─── 滑动切歌方向 ───
  int _swipeDirection = 0; // -1=上滑(下一首), 1=下滑(上一首)

  Widget _buildSwipeableContent(Song song) {
    return GestureDetector(
      onVerticalDragEnd: (details) {
        final dy = details.primaryVelocity ?? 0;
        if (dy < -300) {
          setState(() => _swipeDirection = -1);
          _player.next();
        } else if (dy > 300) {
          setState(() => _swipeDirection = 1);
          _player.prev();
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, animation) {
          final offset = _swipeDirection <= 0
              ? Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              : Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero);
          return SlideTransition(
            position: offset.animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          );
        },
        child: _buildPlayerContent(song),
      ),
    );
  }

  Widget _buildPlayerContent(Song song) {
    final hasLrc = _parsedLrc.isNotEmpty;
    return SingleChildScrollView(
      key: ValueKey(song.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          children: [
            const SizedBox(height: 16),
            // 封面图（缩小）
            Container(
              width: MediaQuery.of(context).size.width * 0.6,
              height: MediaQuery.of(context).size.width * 0.6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: _cardColor,
              ),
              clipBehavior: Clip.antiAlias,
              child: _coverBytes != null
                  ? Image.memory(_coverBytes!, fit: BoxFit.cover)
                  : const Center(
                      child: Icon(Icons.music_note, color: _textTertiary, size: 56),
                    ),
            ),
            const SizedBox(height: 16),
            // 歌词区域（上移）
            if (hasLrc)
              _buildLyricArea()
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _firstLyric(song.lyric),
                  style: const TextStyle(color: _textSecondary, fontSize: 18),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLyricArea() {
    final currentIdx = _currentLrcIndex();
    final lines = <Widget>[];

    for (var i = currentIdx - 2; i < currentIdx; i++) {
      if (i >= 0) {
        lines.add(Text(
          _parsedLrc[i].text,
          style: const TextStyle(color: _textTertiary, fontSize: 18),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ));
        lines.add(const SizedBox(height: 8));
      }
    }
    if (currentIdx >= 0) {
      lines.add(Text(
        _parsedLrc[currentIdx].text,
        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
      lines.add(const SizedBox(height: 8));
    }
    for (var i = currentIdx + 1; i <= currentIdx + 3; i++) {
      if (i < _parsedLrc.length) {
        lines.add(Text(
          _parsedLrc[i].text,
          style: const TextStyle(color: _textTertiary, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ));
        if (i < currentIdx + 3) lines.add(const SizedBox(height: 8));
      }
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

  Widget _buildDownloadProgress() {
    if (_downloadProgress == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          SizedBox(width: 8),
          Text('缓存中', style: TextStyle(color: _textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTimeBar() {
    final max = _duration.inMilliseconds.toDouble();
    final current = _isDragging
        ? _dragValue
        : _position.inMilliseconds.toDouble().clamp(0.0, max);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white,
              inactiveTrackColor: const Color(0xFF333333),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withOpacity(0.1),
            ),
            child: Slider(
              min: 0,
              max: max > 0 ? max : 1,
              value: max > 0 ? current.clamp(0.0, max) : 0,
              onChangeStart: (v) {
                _isDragging = true;
                _dragValue = v;
              },
              onChanged: (v) => setState(() => _dragValue = v),
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
                  style: const TextStyle(color: _textSecondary, fontSize: 11),
                ),
                Text(_fmt(_duration),
                    style: const TextStyle(color: _textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomTab() {
    final hasSong = _player.currentSong != null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1A1A1A), width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SearchPage())),
            child: const Text('搜索',
                style: TextStyle(color: _textSecondary, fontSize: 16, fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: hasSong ? () => _player.togglePlayPause() : null,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: hasSong ? Colors.white : _textTertiary, width: 2.5),
              ),
              child: Center(
                child: Icon(
                  _player.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: hasSong ? Colors.white : _textTertiary,
                  size: 26,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const FavoritesPage())),
            child: const Text('收藏',
                style: TextStyle(color: _textSecondary, fontSize: 16, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: _toggleFavorite,
            child: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? Colors.red : _textSecondary,
              size: 30,
            ),
          ),
          GestureDetector(
            onTap: _showSearchSameSheet,
            child: const Icon(Icons.search, color: _textSecondary, size: 30),
          ),
          GestureDetector(
            onTap: _showQualityPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _textTertiary),
              ),
              child: Text(_qualityLabel(),
                  style: const TextStyle(color: _textSecondary, fontSize: 14)),
            ),
          ),
          GestureDetector(
            onTap: _showPlaylistSheet,
            child: const Icon(Icons.queue_music, color: _textSecondary, size: 30),
          ),
        ],
      ),
    );
  }

  String _firstLyric(String? lyric) {
    if (lyric == null || lyric.isEmpty) return '暂无歌词';
    return lyric
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '暂无歌词')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .trim();
  }
}
