import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/cover_cache_service.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../utils/toast.dart';
import '../utils/lyric_parser.dart';
import '../widgets/music_list_tile.dart';
import 'search_result_page.dart';

class PlayerPage extends StatefulWidget {
  final VoidCallback? onOpenDrawer;
  final bool embedded;

  const PlayerPage({super.key, this.onOpenDrawer, this.embedded = false});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _player = PlayerService();
  bool _isFavorite = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<LyricLine> _parsedLrc = [];
  bool _isDragging = false;
  double _dragValue = 0.0;
  double? _downloadProgress;
  String _coverUrl = '';
  Uint8List? _coverBytes;
  int _swipeDirection = 0;
  double _dragOffset = 0.0;
  bool _isSwitchingSong = false;
  bool _awaitingSongTransition = false;
  bool _incomingSong = false;
  bool _favoriteOperationInProgress = false;
  String? _displayedSongId;

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
    _player.addPlaybackErrorListener(_onPlaybackError);
    _syncState();
    _checkFavorite();
    _onThemeChange();
  }

  void _onThemeChange() {
    if (mounted) {
      setState(() {
        _accent =
            AppDesignTokens.readableAccent(ThemeService.accentColor.value);
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
    if (song != null &&
        _coverBytes == null &&
        song.cover.isNotEmpty &&
        song.cover != _coverUrl) {
      _loadCover(song);
    }
  }

  void _onSongChange(Song s) {
    if (!mounted) return;
    final changedSong = _displayedSongId != s.id;
    _displayedSongId = s.id;
    _parsedLrc = _parseLrc(s.lyric);
    if (s.cover.isEmpty || s.cover != _coverUrl) {
      ThemeService.invalidateCover();
      _coverBytes = null;
      _coverUrl = '';
    }
    final animateFromOppositeSide = _awaitingSongTransition;
    setState(() {
      if (changedSong) {
        _dragOffset = 0.0;
        // Keep the compact transition card active until the incoming slide
        // has completed; switching straight to the full player here causes a
        // one-frame flash of lyrics and controls.
        _isSwitchingSong = animateFromOppositeSide;
        _awaitingSongTransition = false;
        _incomingSong = animateFromOppositeSide;
      }
    });
    _checkFavorite();
    _loadCover(s);
    if (animateFromOppositeSide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Future.delayed(const Duration(milliseconds: 280), () {
          if (mounted) {
            setState(() {
              _incomingSong = false;
              _isSwitchingSong = false;
            });
          }
        });
      });
    }
  }

  void _onDownloadProgress(double? progress) {
    if (mounted) setState(() => _downloadProgress = progress);
  }

  void _onPlayStateChange(bool _) {
    if (mounted) setState(() {});
  }

  void _onPlaybackError(String message) {
    if (mounted) Toast.show(context, message);
  }

  @override
  void dispose() {
    _player.removeProgressListener(_onProgressUpdate);
    _player.removeSongChangeListener(_onSongChange);
    _player.removeDownloadProgressListener(_onDownloadProgress);
    _player.removePlayStateListener(_onPlayStateChange);
    _player.removePlaybackErrorListener(_onPlaybackError);
    ThemeService.accentColor.removeListener(_onThemeChange);
    ThemeService.bgHint.removeListener(_onThemeChange);
    super.dispose();
  }

  void _syncState() {
    _duration = _player.liveDuration;
    _position = _player.livePosition;
    final song = _player.currentSong;
    if (song != null && _parsedLrc.isEmpty) {
      _parsedLrc = _parseLrc(song.lyric);
    }
    if (song != null) {
      _loadCover(song);
    }
  }

  void _prefetchAdjacentCover({required bool next}) {
    final index = _player.currentIndex + (next ? 1 : -1);
    if (index < 0 || index >= _player.queue.length) return;
    final song = _player.queue[index];
    if (song.cover.isEmpty) return;
    final picId = song.picId.isNotEmpty ? song.picId : song.id;
    unawaited(CoverCacheService().download(picId, song.cover));
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
      unawaited(ThemeService.updateFromCover(cached));
      return;
    }
    if (url.startsWith('file://')) return;
    final downloaded = await coverCache.download(picId, url);
    if (downloaded != null && mounted && _coverUrl == url) {
      setState(() => _coverBytes = downloaded);
      unawaited(ThemeService.updateFromCover(downloaded));
    } else if (_coverUrl == url) {
      _coverUrl = '';
    }
  }

  Future<void> _checkFavorite() async {
    final song = _player.currentSong;
    if (song == null) return;
    final songId = song.id;
    final favorite = await FavoritesService.isFavorite(song);
    if (!mounted || _player.currentSong?.id != songId) return;
    setState(() => _isFavorite = favorite);
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteOperationInProgress) return;
    final song = _player.currentSong;
    if (song == null) return;
    final songId = song.id;
    _favoriteOperationInProgress = true;
    try {
      final wasFavorite = await FavoritesService.isFavorite(song);
      if (wasFavorite) {
        await FavoritesService.remove(song);
      } else {
        await FavoritesService.save(song);
      }
      if (!mounted || _player.currentSong?.id != songId) return;
      setState(() => _isFavorite = !wasFavorite);
      Toast.show(context, wasFavorite ? '已取消收藏' : '已加入收藏');
    } finally {
      _favoriteOperationInProgress = false;
    }
  }

  List<LyricLine> _parseLrc(String? lyric) => parseLyrics(lyric);

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
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SearchResultPage(
                          keyword: song.name, fromPlayer: true)));
            }),
            const SizedBox(height: 10),
            _sheetAction(Icons.person_rounded, '歌手', song.singer, () {
              Navigator.pop(ctx);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SearchResultPage(
                          keyword: song.singer, fromPlayer: true)));
            }),
          ],
        ),
      ),
    );
  }

  Widget _sheetAction(
      IconData icon, String label, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Icon(icon, color: AppDesignTokens.lyricWhite, size: 22),
            const SizedBox(width: 12),
            Text('$label：',
                style:
                    AppDesignTokens.caption(color: AppDesignTokens.quietGrey)),
            Expanded(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppDesignTokens.body(weight: FontWeight.w800))),
          ],
        ),
      ),
    );
  }

  void _showPlaylistSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.62),
      builder: (ctx) => _PlaylistSheetContent(
        accent: _accent,
        player: _player,
        height: MediaQuery.of(context).size.height * 0.46,
        onClose: () => Navigator.pop(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = _player.currentSong;
    final content = SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildHeader(song),
          Expanded(
              child: song != null
                  ? _buildSwipeableContent(song)
                  : _buildEmptyState()),
          SizedBox(height: widget.embedded ? 8 : 65),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: widget.embedded
          ? content
          : MusicScaffoldBackground(
              bgHint: _bgHint, accent: _accent, child: content),
    );
  }

  Widget _buildHeader(Song? song) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 18, 26, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => widget.onOpenDrawer?.call(),
            child: Row(
              children: [
                const Icon(Icons.menu_rounded,
                    color: AppDesignTokens.lyricWhite, size: 34),
                const SizedBox(width: 10),
                Text('模式选择', style: AppDesignTokens.title(size: 26)),
              ],
            ),
          ),
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
            Icon(Icons.music_note_rounded,
                color: AppDesignTokens.lyricWhite.withValues(alpha: 0.86),
                size: 78),
            const SizedBox(height: 22),
            Text('选择一个听歌模式', style: AppDesignTokens.title(size: 26)),
            const SizedBox(height: 10),
            Text('让当前专辑的颜色铺满整个房间。',
                textAlign: TextAlign.center,
                style: AppDesignTokens.body(
                    color: AppDesignTokens.warmWhite.withValues(alpha: 0.72))),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () => widget.onOpenDrawer?.call(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                    color: AppDesignTokens.selectedPill,
                    borderRadius: BorderRadius.circular(999)),
                child: Text('打开模式选择',
                    style: AppDesignTokens.body(
                        color: Colors.black87, weight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwipeableContent(Song song) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight == double.infinity
            ? MediaQuery.of(context).size.height
            : constraints.maxHeight;
        final dragProgress =
            (_dragOffset.abs() / max(height * 0.46, 1.0)).clamp(0.0, 1.0);
        final opacity = _isSwitchingSong
            ? 1.0
            : (1.0 - dragProgress * 0.72).clamp(0.28, 1.0);
        final adjacentIndex = _player.currentIndex + (_dragOffset < 0 ? 1 : -1);
        final adjacentSong =
            adjacentIndex >= 0 && adjacentIndex < _player.queue.length
                ? _player.queue[adjacentIndex]
                : null;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            if (_isSwitchingSong || _incomingSong) return;
            if (_dragOffset == 0.0) {
              _prefetchAdjacentCover(next: details.delta.dy < 0);
            }
            setState(() => _dragOffset = (_dragOffset + details.delta.dy)
                .clamp(-height * 0.58, height * 0.58));
          },
          onVerticalDragEnd: (details) =>
              _finishSongDrag(details.primaryVelocity ?? 0, height),
          onVerticalDragCancel: () {
            if (!_isSwitchingSong) setState(() => _dragOffset = 0.0);
          },
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (adjacentSong != null && _dragOffset != 0)
                  Transform.translate(
                    offset: Offset(
                        0,
                        _dragOffset < 0
                            ? height + _dragOffset
                            : -height + _dragOffset),
                    child: _buildSongTransitionCard(adjacentSong),
                  ),
                Transform.translate(
                  offset: Offset(0, _incomingSong ? 0 : _dragOffset),
                  child: AnimatedOpacity(
                    opacity: opacity,
                    duration: const Duration(milliseconds: 80),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      reverseDuration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        // Next (upward swipe) enters from the bottom; previous
                        // (downward swipe) enters from the top.
                        final begin =
                            Offset(0, _swipeDirection < 0 ? 1.0 : -1.0);
                        return SlideTransition(
                          position: animation.drive(
                            Tween(begin: begin, end: Offset.zero),
                          ),
                          child: child,
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(song.id),
                        child: (_incomingSong || _isSwitchingSong)
                            ? _buildSongTransitionCard(song)
                            : _buildPlayerContent(song),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _finishSongDrag(double velocity, double height) {
    if (_isSwitchingSong) return;
    final threshold = height * 0.18;
    final shouldNext = _dragOffset < -threshold || velocity < -650;
    final shouldPrev = _dragOffset > threshold || velocity > 650;
    if (!shouldNext && !shouldPrev) {
      setState(() => _dragOffset = 0.0);
      return;
    }
    setState(() {
      _swipeDirection = shouldNext ? -1 : 1;
      _isSwitchingSong = true;
      _awaitingSongTransition = true;
      _dragOffset = shouldNext ? -height : height;
    });
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      if (shouldNext) {
        _player.next();
      } else {
        _player.prev();
      }
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted || !_isSwitchingSong) return;
      setState(() {
        _isSwitchingSong = false;
        _dragOffset = 0.0;
      });
    });
  }

  Widget _buildPlayerContent(Song song, {Uint8List? coverBytes}) {
    return LayoutBuilder(
      key: ValueKey(song.id),
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final width = constraints.maxWidth;
        final effectiveCoverBytes = coverBytes ??
            (song.id == _player.currentSong?.id ? _coverBytes : null);
        final compact = availableHeight < 620;
        final tiny = availableHeight < 480;
        final contentWidth = width * 0.90;
        final coverHeight = min(
          contentWidth * 0.92,
          availableHeight * (tiny ? 0.30 : 0.44),
        ).clamp(108.0, 360.0);
        final coverWidth = contentWidth;
        final lyricWindow = _visibleLyricTexts(song);
        final titleSize = tiny ? 20.0 : (compact ? 22.0 : 25.0);
        final singerSize = tiny ? 15.0 : (compact ? 17.0 : 18.0);
        final lyricSize = tiny ? 20.0 : (compact ? 22.0 : 25.0);
        final nextLyricSize = tiny ? 15.0 : (compact ? 17.0 : 19.0);
        final coverToInfoGap = tiny ? 8.0 : (compact ? 12.0 : 20.0);
        final infoToLyricGap = tiny ? 8.0 : (compact ? 14.0 : 22.0);
        final lyricToActionsGap = tiny ? 8.0 : (compact ? 12.0 : 18.0);
        final actionsToProgressGap = tiny ? 4.0 : (compact ? 8.0 : 12.0);
        final lyricHeight = nextLyricSize * 2.3 + lyricSize * 2.16 + 16;
        return Padding(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: coverWidth,
                  height: coverHeight,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      color: Colors.white.withValues(alpha: 0.08),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.30),
                            blurRadius: 34,
                            offset: const Offset(0, 18))
                      ]),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (effectiveCoverBytes != null)
                        Image.memory(effectiveCoverBytes, fit: BoxFit.cover)
                      else if (song.cover.isNotEmpty)
                        Image.network(song.cover, fit: BoxFit.cover)
                      else
                        Icon(Icons.music_note_rounded,
                            color: AppDesignTokens.lyricWhite
                                .withValues(alpha: 0.72),
                            size: coverHeight * 0.26),
                      IgnorePointer(
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _downloadProgress == null
                                ? const SizedBox.shrink()
                                : _CoverCacheProgress(
                                    key: const ValueKey('cover-cache-progress'),
                                    progress: _downloadProgress!,
                                    size: min(coverWidth, coverHeight) * 0.28,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: coverToInfoGap),
              Center(
                child: SizedBox(
                  width: coverWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(song.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppDesignTokens.display(size: titleSize)),
                      SizedBox(height: tiny ? 5 : 8),
                      Text(song.singer,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppDesignTokens.title(
                              size: singerSize,
                              color: AppDesignTokens.warmWhite
                                  .withValues(alpha: 0.76))),
                    ],
                  ),
                ),
              ),
              SizedBox(height: infoToLyricGap),
              Center(
                child: SizedBox(
                  width: coverWidth,
                  height: lyricHeight,
                  child:
                      _buildLyricPreview(lyricWindow, lyricSize, nextLyricSize),
                ),
              ),
              const Spacer(),
              SizedBox(height: lyricToActionsGap),
              _buildSocialActions(),
              SizedBox(height: actionsToProgressGap),
              _buildProgressBar(),
              SizedBox(height: tiny ? 4 : 6),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSongTransitionCard(Song song) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 620;
        final tiny = constraints.maxHeight < 480;
        final topSpace = constraints.maxHeight * (tiny ? 0.28 : 0.42);
        return Padding(
          padding: EdgeInsets.fromLTRB(24, topSpace, 24, 0),
          child: Column(
            children: [
              Text(song.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppDesignTokens.display(
                      size: tiny ? 20 : (compact ? 22 : 25))),
              SizedBox(height: tiny ? 5 : 8),
              Text(song.singer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppDesignTokens.title(
                      size: tiny ? 15 : (compact ? 17 : 18),
                      color:
                          AppDesignTokens.warmWhite.withValues(alpha: 0.76))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLyricPreview(
      _LyricWindow window, double currentSize, double nextSize) {
    final upcomingColor = _upcomingLyricColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: nextSize * 1.15,
          child: window.previous == null
              ? null
              : Center(
                  child: Text(
                    window.previous!.text,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppDesignTokens.title(
                      size: nextSize,
                      color: AppDesignTokens.lyricWhite,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: currentSize * 2.16,
          child: Center(
            child: _buildKaraokeText(window.current, currentSize),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: nextSize * 1.15,
          child: window.next == null
              ? null
              : Center(
                  child: Text(
                    window.next!.text,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppDesignTokens.title(
                      size: nextSize,
                      color: upcomingColor,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildKaraokeText(LyricLine line, double size) {
    final style = AppDesignTokens.display(size: size);
    final upcomingColor = _upcomingLyricColor();
    final progress = lyricProgressAt(line, _position.inMilliseconds);
    if (progress <= 0) {
      return Text(line.text,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(color: upcomingColor));
    }
    return _SmoothKaraokeText(
      key: ValueKey(line.startMs),
      text: line.text,
      progress: progress,
      activeStyle: style.copyWith(color: AppDesignTokens.lyricWhite),
      inactiveStyle: style.copyWith(color: upcomingColor),
    );
  }

  Color _upcomingLyricColor() {
    final themeColor = AppDesignTokens.readableAccent(_bgHint);
    return Color.alphaBlend(
      AppDesignTokens.lyricWhite.withValues(alpha: 0.38),
      themeColor,
    );
  }

  Widget _buildSocialActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildActionItem(
            icon: _isFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: '收藏',
            onTap: _toggleFavorite,
            active: _isFavorite,
          ),
          _buildActionItem(
            icon: Icons.queue_music_rounded,
            label: '列表',
            onTap: _showPlaylistSheet,
          ),
          _buildActionItem(
            icon: Icons.search_rounded,
            label: '搜索',
            onTap: _showSearchSameSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final color = active
        ? AppDesignTokens.lyricWhite
        : AppDesignTokens.warmWhite.withValues(alpha: 0.85);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Icon(icon, color: color, size: 36),
        ),
        const SizedBox(height: 5),
        Text(label,
            style: AppDesignTokens.caption(
                size: 10,
                color: AppDesignTokens.warmWhite.withValues(alpha: 0.65))),
      ],
    );
  }

  Widget _buildProgressBar() {
    final max = _duration.inMilliseconds.toDouble();
    final current = _isDragging
        ? _dragValue
        : _position.inMilliseconds.toDouble().clamp(0.0, max);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          activeTrackColor: AppDesignTokens.lyricWhite,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.26),
          thumbColor: AppDesignTokens.lyricWhite,
          overlayColor: Colors.white.withValues(alpha: 0.10),
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
    );
  }

  _LyricWindow _visibleLyricTexts(Song song) {
    if (_parsedLrc.isNotEmpty) {
      final positionMs = _position.inMilliseconds;
      var currentIndex = 0;
      for (var index = 1; index < _parsedLrc.length; index++) {
        if (_parsedLrc[index].startMs > positionMs) break;
        currentIndex = index;
      }
      return _LyricWindow(
        previous: currentIndex > 0 ? _parsedLrc[currentIndex - 1] : null,
        current: _parsedLrc[currentIndex],
        next: currentIndex + 1 < _parsedLrc.length
            ? _parsedLrc[currentIndex + 1]
            : null,
      );
    }
    final first = _firstLyric(song.lyric);
    final fallback = song.album.isNotEmpty ? song.album : '何必沾惹愁滋味';
    return _LyricWindow(
      current: LyricLine(0, 0, [LyricSyllable(0, 0, first)]),
      next: LyricLine(0, 0, [LyricSyllable(0, 0, fallback)]),
    );
  }

  String _firstLyric(String? lyric) {
    if (lyric == null || lyric.isEmpty) return '纵此生也不过百岁';
    final line = lyric
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '纵此生也不过百岁')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'<\d+,\d+,\d+>'), '')
        .trim();
    return line.isEmpty ? '纵此生也不过百岁' : line;
  }
}

class _CoverCacheProgress extends StatelessWidget {
  final double progress;
  final double size;

  const _CoverCacheProgress({
    super.key,
    required this.progress,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final indeterminate = progress < 0;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 14,
          ),
        ],
      ),
      child: CircularProgressIndicator(
        value: indeterminate ? null : progress.clamp(0.0, 1.0),
        strokeWidth: 5,
        strokeCap: StrokeCap.round,
        backgroundColor: Colors.white.withValues(alpha: 0.22),
        valueColor: const AlwaysStoppedAnimation(AppDesignTokens.lyricWhite),
      ),
    );
  }
}

class _LyricWindow {
  final LyricLine? previous;
  final LyricLine current;
  final LyricLine? next;

  const _LyricWindow({
    this.previous,
    required this.current,
    this.next,
  });
}

class _SmoothKaraokeText extends StatelessWidget {
  final String text;
  final double progress;
  final TextStyle activeStyle;
  final TextStyle inactiveStyle;

  const _SmoothKaraokeText({
    super.key,
    required this.text,
    required this.progress,
    required this.activeStyle,
    required this.inactiveStyle,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: inactiveStyle),
          textAlign: TextAlign.center,
          textDirection: Directionality.of(context),
          maxLines: 2,
          ellipsis: '...',
        )..layout(maxWidth: constraints.maxWidth);
        final width = painter.width;
        final height = painter.height;
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 180),
          curve: Curves.linear,
          tween: Tween(end: progress.clamp(0.0, 1.0)),
          builder: (context, animatedProgress, _) {
            final revealWidth = width * animatedProgress;
            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  children: [
                    Text(text,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: inactiveStyle),
                    ClipRect(
                      child: SizedBox(
                        width: revealWidth,
                        height: height,
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: width,
                          maxWidth: width,
                          child: Text(text,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: activeStyle),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PlaylistSheetContent extends StatefulWidget {
  final Color accent;
  final PlayerService player;
  final double height;
  final VoidCallback onClose;

  const _PlaylistSheetContent({
    required this.accent,
    required this.player,
    required this.height,
    required this.onClose,
  });

  @override
  State<_PlaylistSheetContent> createState() => _PlaylistSheetContentState();
}

class _PlaylistSheetContentState extends State<_PlaylistSheetContent> {
  final _scrollController = ScrollController();
  bool _loadingMore = false;

  PlayerService get _player => widget.player;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore) return;
    if (_player.activeMode == null ||
        _player.queueSource != PlaybackQueueSource.listeningMode) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 160) return;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _player.activeMode == null) return;
    setState(() => _loadingMore = true);
    try {
      await _player.loadMoreModeSongs();
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final songs = _player.queue;
    final currentIdx = _player.currentIndex;
    final loading = _loadingMore;
    return _MusicSheet(
      accent: widget.accent,
      title: '播放队列 · ${songs.length} 首',
      child: SizedBox(
        height: widget.height,
        child: songs.isEmpty
            ? MusicEmptyState(
                accent: widget.accent,
                icon: Icons.queue_music_rounded,
                title: '队列是空的',
                message: '去搜索或播放收藏里的歌曲。')
            : ListView.builder(
                controller: _scrollController,
                itemCount: songs.length + (loading ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= songs.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final song = songs[i];
                  return MusicListTile(
                    song: song,
                    index: i,
                    isCurrent: i == currentIdx,
                    accent: widget.accent,
                    margin: const EdgeInsets.only(bottom: 8),
                    onTap: () {
                      if (i == _player.currentIndex) {
                        if (!_player.isPlaying) unawaited(_player.play());
                      } else {
                        unawaited(_player.playAt(i));
                      }
                      widget.onClose();
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _MusicSheet extends StatelessWidget {
  final Color accent;
  final String title;
  final Widget child;

  const _MusicSheet(
      {required this.accent, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeService.bgHint,
      builder: (context, bgHint, _) => SafeArea(
        top: false,
        child: TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          tween: ColorTween(end: bgHint),
          builder: (context, color, child) => Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            decoration: BoxDecoration(
              color: AppDesignTokens.surfaceFor(color ?? bgHint, opacity: 0.86),
              borderRadius: BorderRadius.circular(AppDesignTokens.sheetRadius),
            ),
            child: child,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(999))),
              const SizedBox(height: 16),
              Text(title, style: AppDesignTokens.title(size: 18)),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
