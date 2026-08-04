import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/music_api.dart';
import '../data/categories.dart';
import '../models/song.dart';
import '../services/cover_cache_service.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../services/settings_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../utils/toast.dart';
import '../widgets/glass_panel.dart';
import '../widgets/mode_drawer.dart';
import '../widgets/music_list_tile.dart';
import 'favorites_page.dart';
import 'playlist_page.dart';
import 'search_page.dart';
import 'search_result_page.dart';

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
  int _swipeDirection = 0;

  Color _accent = AppDesignTokens.lyricWhite;
  Color _bgHint = AppDesignTokens.inkBlack;

  @override
  void initState() {
    super.initState();
    ThemeService.accentColor.addListener(_onThemeChange);
    ThemeService.bgHint.addListener(_onThemeChange);
    _player.addProgressListener(_onProgressUpdate);
    _player.addSongChangeListener(_onSongChange);
    _player.addDownloadProgressListener(_onDownloadProgress);
    _player.addPlayStateListener(_onPlayStateChange);
    _syncState();
    _checkFavorite();
    _onThemeChange();
  }

  void _onThemeChange() {
    if (mounted) {
      setState(() {
        _accent = AppDesignTokens.readableAccent(ThemeService.accentColor.value);
        _bgHint = ThemeService.bgHint.value;
      });
    }
  }

  void _onProgressUpdate(Duration pos, Duration? dur) {
    if (!mounted) return;
    setState(() {
      _position = pos;
      _duration = dur ?? Duration.zero;
    });
    final song = _player.currentSong;
    if (song != null && _coverBytes == null && song.cover.isNotEmpty && song.cover != _coverUrl) {
      _loadCover(song);
    }
  }

  void _onSongChange(Song s) {
    if (!mounted) return;
    _parsedLrc = _parseLrc(s.lyric);
    if (s.cover.isEmpty || s.cover != _coverUrl) {
      _coverBytes = null;
      _coverUrl = '';
    }
    setState(() {});
    _checkFavorite();
    _loadCover(s);
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
    ThemeService.accentColor.removeListener(_onThemeChange);
    ThemeService.bgHint.removeListener(_onThemeChange);
    super.dispose();
  }

  void _syncState() {
    if (_player.duration != null) _duration = _player.duration!;
    _position = _player.position;
    final song = _player.currentSong;
    if (song != null && _parsedLrc.isEmpty) _parsedLrc = _parseLrc(song.lyric);
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
      ThemeService.updateFromCover(cached);
      return;
    }
    if (url.startsWith('file://')) return;
    final downloaded = await coverCache.download(picId, url);
    if (downloaded != null && mounted && _coverUrl == url) {
      setState(() => _coverBytes = downloaded);
      ThemeService.updateFromCover(downloaded);
    } else if (_coverUrl == url) {
      _coverUrl = '';
    }
  }

  Future<void> _checkFavorite() async {
    final song = _player.currentSong;
    if (song == null) return;
    _isFavorite = await FavoritesService.isFavorite(song);
    if (mounted) setState(() {});
  }

  Future<void> _toggleFavorite() async {
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
      if (match == null) continue;
      final min = int.parse(match.group(1)!);
      final sec = int.parse(match.group(2)!);
      final msStr = match.group(3);
      var ms = 0;
      if (msStr != null) {
        ms = int.parse(msStr);
        if (msStr.length == 1) ms *= 100;
        if (msStr.length == 2) ms *= 10;
      }
      final text = match.group(4)?.trim() ?? '';
      if (text.isNotEmpty) lines.add(_LrcLine((min * 60 + sec) * 1000 + ms, text));
    }
    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return lines;
  }

  int _currentLrcIndex() {
    if (_parsedLrc.isEmpty) return -1;
    final posMs = _position.inMilliseconds;
    var left = 0;
    var right = _parsedLrc.length - 1;
    var idx = -1;
    while (left <= right) {
      final mid = (left + right) ~/ 2;
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
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MusicSheet(
        accent: _accent,
        title: '搜索同名歌曲或歌手',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetAction(Icons.music_note_rounded, '歌曲名', song.name, () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => SearchResultPage(keyword: song.name, fromPlayer: true)));
            }),
            const SizedBox(height: 10),
            _sheetAction(Icons.person_rounded, '歌手', song.singer, () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => SearchResultPage(keyword: song.singer, fromPlayer: true)));
            }),
          ],
        ),
      ),
    );
  }

  void _showQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MusicSheet(
        accent: _accent,
        title: '音质选择',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: AudioQuality.values.map((q) {
            final selected = SettingsService().quality == q;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () async {
                  final oldBr = SettingsService().quality.br;
                  await SettingsService().setQuality(q);
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  setState(() {});
                  if (q.br > oldBr) PlayerService().redownloadCurrentAtNewQuality();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: selected ? AppDesignTokens.selectedPill : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined, color: selected ? Colors.black87 : AppDesignTokens.warmWhite, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(q.label, style: AppDesignTokens.body(color: selected ? Colors.black87 : AppDesignTokens.lyricWhite, weight: FontWeight.w800))),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _sheetAction(IconData icon, String label, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Icon(icon, color: AppDesignTokens.lyricWhite, size: 22),
            const SizedBox(width: 12),
            Text('$label：', style: AppDesignTokens.caption(color: AppDesignTokens.quietGrey)),
            Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppDesignTokens.body(weight: FontWeight.w800))),
          ],
        ),
      ),
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
      case AudioQuality.low128: return '标准';
      case AudioQuality.medium192: return '较高';
      case AudioQuality.high320: return '极高';
      case AudioQuality.lossless740: return '无损';
      case AudioQuality.lossless999: return '极高';
    }
  }

  void _showPlaylistSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.62),
      builder: (ctx) {
        final songs = _player.playlist;
        final currentIdx = _player.currentIndex;
        return _MusicSheet(
          accent: _accent,
          title: '播放队列 · ${songs.length} 首',
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.46,
            child: songs.isEmpty
                ? MusicEmptyState(accent: _accent, icon: Icons.queue_music_rounded, title: '队列是空的', message: '去搜索或播放收藏里的歌曲。')
                : ListView.builder(
                    itemCount: songs.length,
                    itemBuilder: (_, i) => MusicListTile(
                      song: songs[i],
                      index: i,
                      isCurrent: i == currentIdx,
                      accent: _accent,
                      margin: const EdgeInsets.only(bottom: 8),
                      onTap: () {
                        _player.playAt(i);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
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
      if (mounted) Toast.show(context, '加载失败，请重试');
    }
  }

  Future<void> _openFavorites() async {
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

  Future<void> _randomPlay() async {
    final prefs = await SharedPreferences.getInstance();
    final pinned = prefs.getStringList('pinned_playlists') ?? [];
    final playlists = <PlaylistInfo>[];
    for (final s in pinned) {
      final parts = s.split('|');
      if (parts.length >= 2 && parts[0].isNotEmpty) {
        playlists.add(PlaylistInfo(parts[1], parts[0], coverUrl: parts.length > 2 ? parts[2] : ''));
      }
    }
    if (playlists.isEmpty) {
      Toast.show(context, '请先置顶一些歌单');
      return;
    }
    final random = Random();
    _loadAndPlay(playlists[random.nextInt(playlists.length)]);
  }

  @override
  Widget build(BuildContext context) {
    final song = _player.currentSong;
    if (song == null && !widget.isRoot) {
      return const Scaffold(backgroundColor: AppDesignTokens.inkBlack, body: SizedBox());
    }
    return Scaffold(
      key: widget.isRoot ? _scaffoldKey : null,
      backgroundColor: Colors.transparent,
      drawer: widget.isRoot ? ModeDrawer(onSelectPlaylist: _loadAndPlay, onOpenFavorites: _openFavorites, onRandomPlay: _randomPlay) : null,
      body: MusicScaffoldBackground(
        bgHint: _bgHint,
        accent: _accent,
        coverBytes: _coverBytes,
        useCoverBlur: true,
        child: SafeArea(
          bottom: !widget.isRoot,
          child: Column(
            children: [
              _buildHeader(song),
              Expanded(child: song != null ? _buildSwipeableContent(song) : _buildEmptyState()),
              if (song != null) _buildProgressBar(),
              if (!widget.isRoot && song != null) _buildNonRootControls(),
              if (widget.isRoot) const SizedBox(height: 92),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Song? song) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 18, 26, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.isRoot ? () => _scaffoldKey.currentState?.openDrawer() : () => Navigator.pop(context),
            child: Row(
              children: [
                Icon(widget.isRoot ? Icons.menu_rounded : Icons.keyboard_arrow_down_rounded, color: AppDesignTokens.lyricWhite, size: 34),
                const SizedBox(width: 10),
                Text(widget.isRoot ? '模式选择' : '正在播放', style: AppDesignTokens.title(size: 26)),
              ],
            ),
          ),
          const Spacer(),
          if (!widget.isRoot)
            GestureDetector(onTap: _showPlaylistSheet, child: const Icon(Icons.queue_music_rounded, color: AppDesignTokens.lyricWhite, size: 32)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_rounded, color: AppDesignTokens.lyricWhite.withOpacity(0.86), size: 78),
            const SizedBox(height: 22),
            Text('选择一个听歌模式', style: AppDesignTokens.title(size: 26)),
            const SizedBox(height: 10),
            Text('让当前专辑的颜色铺满整个房间。', textAlign: TextAlign.center, style: AppDesignTokens.body(color: AppDesignTokens.warmWhite.withOpacity(0.72))),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(color: AppDesignTokens.selectedPill, borderRadius: BorderRadius.circular(999)),
                child: Text('打开模式选择', style: AppDesignTokens.body(color: Colors.black87, weight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwipeableContent(Song song) {
    return GestureDetector(
      onVerticalDragEnd: (details) {
        final dy = details.primaryVelocity ?? 0;
        if (dy < -300) { setState(() => _swipeDirection = -1); _player.next(); }
        if (dy > 300) { setState(() => _swipeDirection = 1); _player.prev(); }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        transitionBuilder: (child, animation) {
          final offset = _swipeDirection <= 0 ? Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero) : Tween<Offset>(begin: const Offset(0, -0.12), end: Offset.zero);
          return FadeTransition(opacity: animation, child: SlideTransition(position: offset.animate(animation), child: child));
        },
        child: _buildPlayerContent(song),
      ),
    );
  }

  Widget _buildPlayerContent(Song song) {
    final coverSize = min(MediaQuery.of(context).size.width * 0.82, 360.0);
    final currentLyric = _currentLyricText(song);
    final nextLyric = _nextLyricText(song);
    return SingleChildScrollView(
      key: ValueKey(song.id),
      padding: const EdgeInsets.fromLTRB(26, 80, 26, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: coverSize,
              height: coverSize,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), color: Colors.white.withOpacity(0.08), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 28, offset: const Offset(0, 16))]),
              clipBehavior: Clip.antiAlias,
              child: _coverBytes != null ? Image.memory(_coverBytes!, fit: BoxFit.cover) : Icon(Icons.music_note_rounded, color: AppDesignTokens.lyricWhite.withOpacity(0.72), size: 90),
            ),
          ),
          const SizedBox(height: 48),
          Text(currentLyric, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppDesignTokens.display(size: 27)),
          const SizedBox(height: 12),
          Text(nextLyric, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppDesignTokens.title(size: 21, color: AppDesignTokens.warmWhite.withOpacity(0.58))),
          const SizedBox(height: 78),
          Row(
            children: [
              Expanded(child: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppDesignTokens.display(size: 27))),
              const SizedBox(width: 8),
              MusicChip(label: _qualityLabel(), accent: _accent, active: true, onTap: _showQualityPicker),
            ],
          ),
          const SizedBox(height: 12),
          Text(song.singer, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppDesignTokens.title(size: 22, color: AppDesignTokens.warmWhite.withOpacity(0.76))),
          const SizedBox(height: 30),
          _buildSocialActions(),
          if (_downloadProgress != null) ...[const SizedBox(height: 14), _buildDownloadProgress()],
        ],
      ),
    );
  }

  Widget _buildSocialActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _toggleFavorite,
                child: Icon(_isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: _isFavorite ? AppDesignTokens.lyricWhite : AppDesignTokens.warmWhite.withOpacity(0.85), size: 38),
              ),
              const SizedBox(height: 5),
              Text('收藏', style: AppDesignTokens.caption(size: 10, color: AppDesignTokens.warmWhite.withOpacity(0.65))),
            ],
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _showPlaylistSheet,
                child: Icon(Icons.queue_music_rounded, color: AppDesignTokens.warmWhite.withOpacity(0.85), size: 38),
              ),
              const SizedBox(height: 5),
              Text('列表', style: AppDesignTokens.caption(size: 10, color: AppDesignTokens.warmWhite.withOpacity(0.65))),
            ],
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _showQualityPicker,
                child: Icon(Icons.high_quality_rounded, color: AppDesignTokens.warmWhite.withOpacity(0.85), size: 38),
              ),
              const SizedBox(height: 5),
              Text('音质', style: AppDesignTokens.caption(size: 10, color: AppDesignTokens.warmWhite.withOpacity(0.65))),
            ],
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _showSearchSameSheet,
                child: Icon(Icons.search_rounded, color: AppDesignTokens.warmWhite.withOpacity(0.85), size: 38),
              ),
              const SizedBox(height: 5),
              Text('搜索', style: AppDesignTokens.caption(size: 10, color: AppDesignTokens.warmWhite.withOpacity(0.65))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _socialAction(IconData icon, String count, VoidCallback onTap, [Color? color]) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: color ?? AppDesignTokens.lyricWhite, size: 42),
          const SizedBox(width: 5),
          Text(count, style: AppDesignTokens.body(size: 16, weight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildDownloadProgress() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: _accent, value: _downloadProgress)),
        const SizedBox(width: 9),
        Text('缓存中', style: AppDesignTokens.caption(color: AppDesignTokens.warmWhite.withOpacity(0.72))),
      ],
    );
  }

  Widget _buildProgressBar() {
    final max = _duration.inMilliseconds.toDouble();
    final current = _isDragging ? _dragValue : _position.inMilliseconds.toDouble().clamp(0.0, max);
    return Padding(
      padding: EdgeInsets.fromLTRB(30, 0, 30, widget.isRoot ? 84 : 14),
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          activeTrackColor: AppDesignTokens.lyricWhite,
          inactiveTrackColor: Colors.white.withOpacity(0.26),
          thumbColor: AppDesignTokens.lyricWhite,
          overlayColor: Colors.white.withOpacity(0.10),
        ),
        child: Slider(
          min: 0,
          max: max > 0 ? max : 1,
          value: max > 0 ? current.clamp(0.0, max) : 0,
          onChangeStart: (v) { _isDragging = true; _dragValue = v; },
          onChanged: (v) => setState(() => _dragValue = v),
          onChangeEnd: (v) { _isDragging = false; _player.seek(Duration(milliseconds: v.toInt())); },
        ),
      ),
    );
  }

  Widget _buildNonRootControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 0, 26, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconOrbButton(icon: _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, accent: _accent, active: _isFavorite, onTap: _toggleFavorite),
          IconOrbButton(icon: Icons.search_rounded, accent: _accent, onTap: _showSearchSameSheet),
          MusicChip(label: _qualityLabel(), accent: _accent, active: true, onTap: _showQualityPicker),
          IconOrbButton(icon: Icons.queue_music_rounded, accent: _accent, onTap: _showPlaylistSheet),
        ],
      ),
    );
  }

  String _currentLyricText(Song song) {
    final idx = _currentLrcIndex();
    if (idx >= 0 && idx < _parsedLrc.length) return _parsedLrc[idx].text;
    return _firstLyric(song.lyric);
  }

  String _nextLyricText(Song song) {
    final idx = _currentLrcIndex();
    if (idx + 1 >= 0 && idx + 1 < _parsedLrc.length) return _parsedLrc[idx + 1].text;
    return song.album.isNotEmpty ? song.album : '何必沾惹愁滋味';
  }

  String _firstLyric(String? lyric) {
    if (lyric == null || lyric.isEmpty) return '纵此生也不过百岁';
    final line = lyric.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '纵此生也不过百岁').replaceAll(RegExp(r'\[.*?\]'), '').trim();
    return line.isEmpty ? '纵此生也不过百岁' : line;
  }
}

class _MusicSheet extends StatelessWidget {
  final Color accent;
  final String title;
  final Widget child;

  const _MusicSheet({required this.accent, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        decoration: BoxDecoration(color: const Color(0xFF241A14).withOpacity(0.96), borderRadius: BorderRadius.circular(AppDesignTokens.sheetRadius)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 42, height: 4, decoration: BoxDecoration(color: Colors.white.withOpacity(0.32), borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 16),
            Text(title, style: AppDesignTokens.title(size: 18)),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
