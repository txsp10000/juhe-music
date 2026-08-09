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

  const PlayerPage({super.key, this.onOpenDrawer});

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
    setState(() {
      if (changedSong) {
        _dragOffset = 0.0;
        _isSwitchingSong = false;
      }
    });
    _checkFavorite();
    _loadCover(s);
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
      builder: (ctx) {
        final songs = _player.queue;
        final currentIdx = _player.currentIndex;
        return _MusicSheet(
          accent: _accent,
          title: '播放队列 · ${songs.length} 首',
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.46,
            child: songs.isEmpty
                ? MusicEmptyState(
                    accent: _accent,
                    icon: Icons.queue_music_rounded,
                    title: '队列是空的',
                    message: '去搜索或播放收藏里的歌曲。')
                : ListView.builder(
                    itemCount: songs.length,
                    itemBuilder: (_, i) => MusicListTile(
                      song: songs[i],
                      index: i,
                      isCurrent: i == currentIdx,
                      accent: _accent,
                      margin: const EdgeInsets.only(bottom: 8),
                      onTap: () {
                        if (i == _player.currentIndex) {
                          if (!_player.isPlaying) unawaited(_player.play());
                        } else {
                          unawaited(_player.playAt(i));
                        }
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = _player.currentSong;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MusicScaffoldBackground(
        bgHint: _bgHint,
        accent: _accent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(song),
              Expanded(
                  child: song != null
                      ? _buildSwipeableContent(song)
                      : _buildEmptyState()),
              const SizedBox(height: 106),
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
        final slideOffset = _isSwitchingSong
            ? Offset(0, _swipeDirection < 0 ? -1.05 : 1.05)
            : Offset(0, _dragOffset / max(height, 1.0));
        final opacity = _isSwitchingSong
            ? 0.0
            : (1.0 - dragProgress * 0.72).clamp(0.28, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            if (_isSwitchingSong) return;
            setState(() => _dragOffset = (_dragOffset + details.delta.dy)
                .clamp(-height * 0.58, height * 0.58));
          },
          onVerticalDragEnd: (details) =>
              _finishSongDrag(details.primaryVelocity ?? 0, height),
          onVerticalDragCancel: () {
            if (!_isSwitchingSong) setState(() => _dragOffset = 0.0);
          },
          child: ClipRect(
            child: AnimatedSlide(
              offset: slideOffset,
              duration: Duration(milliseconds: _isSwitchingSong ? 260 : 80),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: opacity,
                duration: Duration(milliseconds: _isSwitchingSong ? 240 : 80),
                child: _buildPlayerContent(song),
              ),
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

  Widget _buildPlayerContent(Song song) {
    return LayoutBuilder(
      key: ValueKey(song.id),
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final width = constraints.maxWidth;
        final compact = availableHeight < 640;
        final coverWidth = min(width * 0.92, compact ? 340.0 : 380.0);
        final coverHeight = min(coverWidth * 0.92, availableHeight * 0.34)
            .clamp(compact ? 188.0 : 220.0, compact ? 258.0 : 300.0);
        final lyricWindow = _visibleLyricTexts(song);
        final titleSize = compact ? 22.0 : 25.0;
        final singerSize = compact ? 17.0 : 18.0;
        final lyricSize = compact ? 22.0 : 25.0;
        final nextLyricSize = compact ? 17.0 : 19.0;
        final topGap = compact ? 0.0 : 6.0;
        final coverToInfoGap = compact ? 12.0 : 20.0;
        final infoToLyricGap = compact ? 14.0 : 22.0;
        final lyricToActionsGap = compact ? 18.0 : 30.0;
        final actionsToProgressGap = compact ? 18.0 : 24.0;
        return Padding(
          padding: const EdgeInsets.fromLTRB(26, 0, 26, 0),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: availableHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: topGap),
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
                      child: _coverBytes != null
                          ? Image.memory(_coverBytes!, fit: BoxFit.cover)
                          : Icon(Icons.music_note_rounded,
                              color: AppDesignTokens.lyricWhite
                                  .withValues(alpha: 0.72),
                              size: coverHeight * 0.26),
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
                          const SizedBox(height: 8),
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
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: compact ? 128.0 : 156.0),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: _buildLyricPreview(
                              lyricWindow, lyricSize, nextLyricSize),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: lyricToActionsGap),
                  _buildSocialActions(),
                  if (_downloadProgress != null) ...[
                    const SizedBox(height: 8),
                    _buildDownloadProgress()
                  ],
                  SizedBox(height: actionsToProgressGap),
                  _buildProgressBar(),
                  SizedBox(height: compact ? 10 : 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLyricPreview(
      _LyricWindow window, double currentSize, double nextSize) {
    final upcomingColor = AppDesignTokens.readableAccent(_bgHint);
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
    final upcomingColor = AppDesignTokens.readableAccent(_bgHint);
    final progress = lyricProgressAt(line, _position.inMilliseconds);
    if (progress <= 0) {
      return Text(line.text,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(color: upcomingColor));
    }
    return _SmoothKaraokeText(
      text: line.text,
      progress: progress,
      activeStyle: style.copyWith(color: AppDesignTokens.lyricWhite),
      inactiveStyle: style.copyWith(color: upcomingColor),
    );
  }

  Widget _buildSocialActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
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

  Widget _buildDownloadProgress() {
    final preparing = _downloadProgress != null && _downloadProgress! < 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _accent,
                value: preparing ? null : _downloadProgress)),
        const SizedBox(width: 9),
        Text(preparing ? '正在准备播放' : '缓存中',
            style: AppDesignTokens.caption(
                color: AppDesignTokens.warmWhite.withValues(alpha: 0.72))),
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
