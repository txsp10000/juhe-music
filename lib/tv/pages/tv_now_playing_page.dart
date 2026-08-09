import 'package:flutter/material.dart';

import '../../api/music_api.dart';
import '../../models/song.dart';
import '../../models/listening_mode.dart';
import '../../services/favorites_service.dart';
import '../../services/audio_cache_service.dart';
import '../../services/player_service.dart';
import '../../services/theme_service.dart';
import '../tv_layout_metrics.dart';
import '../tv_routes.dart';
import '../tv_tokens.dart';
import '../widgets/tv_album_art.dart';
import '../widgets/tv_focus_card.dart';
import '../widgets/tv_page_scaffold.dart';
import '../widgets/tv_pill_button.dart';
import '../widgets/tv_player_controls.dart';
import '../widgets/tv_queue_panel.dart';
import '../widgets/tv_section_card.dart';
import '../../utils/lyric_parser.dart';

class TvNowPlayingPage extends StatefulWidget {
  const TvNowPlayingPage({super.key});

  @override
  State<TvNowPlayingPage> createState() => _TvNowPlayingPageState();
}

enum _TvPlayerMenu { relatedSearch }

class _TvNowPlayingPageState extends State<TvNowPlayingPage> {
  final _player = PlayerService();
  final _queueFocusNode = FocusNode();
  final _previousFocusNode = FocusNode();
  final _nextFocusNode = FocusNode();
  final _queueButtonFocusNode = FocusNode();
  final _relatedSearchFocusNode = FocusNode();
  final _searchFocusNode = FocusNode();
  final _favoritesFocusNode = FocusNode();
  final _cacheFocusNode = FocusNode();
  final Map<String, FocusNode> _modeFocusNodes = {};
  FocusNode? _queueReturnFocusNode;
  bool _queueOpen = false;
  bool _isFavorite = false;
  int _audioCacheBytes = 0;
  bool _cacheBusy = false;
  double? _downloadProgress;
  String? _loadingMessage;
  String? _errorMessage;
  _TvPlayerMenu? _activeMenu;
  List<LyricLine> _parsedLrc = [];
  int _modeLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _player.addProgressListener(_onProgress);
    _player.addSongChangeListener(_onSongChange);
    _player.addPlayStateListener(_onPlayState);
    _player.addDownloadProgressListener(_onDownloadProgress);
    _player.addPlaybackErrorListener(_onPlaybackError);
    FavoritesService.version.addListener(_refreshFavoriteState);
    TvRoutes.homeRouteVersion.addListener(_onHomeRouteRequest);
    _refreshFavoriteState();
    _syncLyrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (TvRoutes.consumeHomeQueueFocusRequest()) {
        _queueButtonFocusNode.requestFocus();
      } else {
        _searchFocusNode.requestFocus();
      }
      if (TvRoutes.consumeHomeQueueOpenRequest()) {
        _openQueue(returnFocusNode: _queueButtonFocusNode);
      }
    });
  }

  @override
  void dispose() {
    _player.removeProgressListener(_onProgress);
    _player.removeSongChangeListener(_onSongChange);
    _player.removePlayStateListener(_onPlayState);
    _player.removeDownloadProgressListener(_onDownloadProgress);
    _player.removePlaybackErrorListener(_onPlaybackError);
    FavoritesService.version.removeListener(_refreshFavoriteState);
    TvRoutes.homeRouteVersion.removeListener(_onHomeRouteRequest);
    _queueFocusNode.dispose();
    _previousFocusNode.dispose();
    _nextFocusNode.dispose();
    _queueButtonFocusNode.dispose();
    _relatedSearchFocusNode.dispose();
    _searchFocusNode.dispose();
    _favoritesFocusNode.dispose();
    _cacheFocusNode.dispose();
    for (final node in _modeFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onProgress(Duration _, Duration? __) {
    if (!mounted) return;
    _syncLyrics();
    setState(() {});
  }

  void _onSongChange(Song song) {
    _parsedLrc = _parseLrc(song.lyric);
    _refreshFavoriteState();
    _refreshCacheSize();
    if (mounted) setState(() {});
  }

  void _onPlayState(bool _) {
    if (mounted) setState(() {});
  }

  void _onHomeRouteRequest() {
    if (!mounted || !TvRoutes.consumeHomeQueueOpenRequest()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openQueue(returnFocusNode: _queueButtonFocusNode);
    });
  }

  void _onDownloadProgress(double? progress) {
    if (mounted) setState(() => _downloadProgress = progress);
  }

  void _onPlaybackError(String message) {
    if (!mounted) return;
    setState(() {
      _downloadProgress = null;
      _loadingMessage = null;
      _errorMessage = message;
    });
  }

  void _syncLyrics() {
    final song = _player.currentSong;
    if (song == null) {
      if (_parsedLrc.isNotEmpty) _parsedLrc = [];
      return;
    }
    if (song.lyric.isNotEmpty && _parsedLrc.isEmpty) {
      _parsedLrc = _parseLrc(song.lyric);
    }
  }

  Future<void> _playQueueAt(int index) async {
    await _player.playAt(index);
  }

  Future<void> _loadMoreQueue() async {
    await _player.loadMoreModeSongs();
    if (mounted) setState(() {});
  }

  void _changeTrack(VoidCallback action, FocusNode focusNode) {
    focusNode.requestFocus();
    action();
  }

  void _openQueue({FocusNode? returnFocusNode}) {
    _queueReturnFocusNode = returnFocusNode ?? _queueButtonFocusNode;
    setState(() => _queueOpen = true);
  }

  void _closeQueue() {
    final returnFocusNode = _queueReturnFocusNode;
    _queueReturnFocusNode = null;
    setState(() => _queueOpen = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (returnFocusNode != null && returnFocusNode.canRequestFocus) {
        returnFocusNode.requestFocus();
      } else {
        _queueButtonFocusNode.requestFocus();
      }
    });
  }

  Future<void> _playMode(ListeningMode mode, FocusNode modeFocusNode) async {
    final generation = ++_modeLoadGeneration;
    setState(() => _loadingMessage = '正在加载「${mode.name}」');
    try {
      final songs = await MusicApi.getModeTracks(mode.sceneModeId);
      if (!mounted || generation != _modeLoadGeneration) return;
      if (songs.isEmpty) throw StateError('empty mode');
      _player.replaceQueue(songs, mode: mode);
      await _player.playAt(0);
    } catch (_) {
      if (mounted && generation == _modeLoadGeneration) {
        setState(() => _errorMessage = '“${mode.name}”加载失败，请检查网络后重试。');
      }
      return;
    } finally {
      if (mounted && generation == _modeLoadGeneration) {
        setState(() => _loadingMessage = null);
      }
    }
    if (mounted) {
      _openQueue(returnFocusNode: modeFocusNode);
    }
  }

  Future<void> _refreshFavoriteState() async {
    final song = _player.currentSong;
    final favorite =
        song == null ? false : await FavoritesService.isFavorite(song);
    if (mounted && identical(_player.currentSong, song)) {
      setState(() => _isFavorite = favorite);
    }
  }

  Future<void> _toggleFavorite() async {
    final song = _player.currentSong;
    if (song == null) return;
    if (_isFavorite) {
      await FavoritesService.remove(song);
    } else {
      await FavoritesService.save(song);
    }
    await _refreshFavoriteState();
  }

  Future<void> _refreshCacheSize() async {
    final bytes = await AudioCacheService().getCacheSizeBytes();
    if (mounted) setState(() => _audioCacheBytes = bytes);
  }

  String _formatCacheSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _confirmClearCache() async {
    if (_cacheBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final metrics = TvLayoutMetrics.of(dialogContext);
        return AlertDialog(
          backgroundColor: TvTokens.panel,
          title: Text('清理歌曲缓存', style: TvTokens.title(size: metrics.font(32))),
          content: Text(
            '将清理 ${_formatCacheSize(_audioCacheBytes)} 歌曲缓存，歌词和专辑图不会删除。确定继续吗？',
            style: TvTokens.body(size: metrics.font(22)),
          ),
          actions: [
            TvPillButton(
              label: '取消',
              autofocus: true,
              onTap: () => Navigator.of(dialogContext).pop(false),
            ),
            TvPillButton(
              label: '确认清理',
              icon: Icons.delete_outline_rounded,
              onTap: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cacheBusy = true);
    await AudioCacheService().clearCache();
    if (!mounted) return;
    setState(() {
      _cacheBusy = false;
      _audioCacheBytes = 0;
    });
  }

  void _openMenu(_TvPlayerMenu menu) {
    if (menu == _TvPlayerMenu.relatedSearch && _player.currentSong == null) {
      setState(() => _errorMessage = '请先播放一首歌曲，再搜索同名歌曲或歌手。');
      return;
    }
    setState(() => _activeMenu = menu);
  }

  void _closeMenu() {
    final menu = _activeMenu;
    setState(() => _activeMenu = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (menu == _TvPlayerMenu.relatedSearch) {
        _relatedSearchFocusNode.requestFocus();
      }
    });
  }

  void _searchRelated(String keyword) {
    _closeMenu();
    Navigator.of(context).pushNamed(TvRoutes.searchResults, arguments: keyword);
  }

  Future<void> _retryPlayback() async {
    final index = _player.currentIndex;
    setState(() => _errorMessage = null);
    if (index >= 0) await _player.playAt(index);
  }

  void _seekBy(int seconds) {
    _player.seekRelative(Duration(seconds: seconds));
  }

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final interactionBlocked = _queueOpen ||
        _loadingMessage != null ||
        _errorMessage != null ||
        _activeMenu != null;
    return PopScope(
      canPop: !interactionBlocked,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_queueOpen) {
          _closeQueue();
        } else if (_activeMenu != null) {
          _closeMenu();
        } else if (_errorMessage != null) {
          setState(() => _errorMessage = null);
        } else if (_loadingMessage != null) {
          _modeLoadGeneration++;
          setState(() => _loadingMessage = null);
        }
      },
      child: Stack(
        children: [
          ExcludeFocus(
            excluding: interactionBlocked,
            child: TvPageScaffold(
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: TvPillButton(
                      label: '搜索',
                      icon: Icons.search_rounded,
                      fullWidth: true,
                      autofocus: true,
                      focusNode: _searchFocusNode,
                      borderColor: Colors.white.withValues(alpha: 0.32),
                      onTap: () =>
                          Navigator.of(context).pushNamed(TvRoutes.search),
                    ),
                  ),
                  SizedBox(height: metrics.value(26, minimum: 12)),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 38, child: _leftPanel(context)),
                        SizedBox(width: metrics.value(24, minimum: 12)),
                        Expanded(
                          flex: 62,
                          child: _modePanel(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_queueOpen)
            Positioned.fill(
              child: Material(
                color: Colors.black.withValues(alpha: 0.64),
                child: FocusScope(
                  autofocus: true,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _closeQueue,
                        ),
                      ),
                      TvQueuePanel(
                        songs: _player.queue,
                        currentIndex: _player.currentIndex,
                        currentFocusNode: _queueFocusNode,
                        backgroundColor: ThemeService.bgHint.value,
                        onPlay: _playQueueAt,
                        onReachEnd:
                            _player.activeMode == null ? null : _loadMoreQueue,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_loadingMessage != null || _downloadProgress != null)
            _loadingOverlay(context),
          if (_errorMessage != null) _errorOverlay(context),
          if (_activeMenu != null) _menuOverlay(context),
        ],
      ),
    );
  }

  Widget _leftPanel(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final song = _player.currentSong;
    return LayoutBuilder(
      builder: (context, constraints) {
        final alignedWidth =
            constraints.maxWidth.clamp(320.0, 520.0).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SizedBox(
                width: alignedWidth,
                child: Column(
                  children: [
                    TvAlbumArt(
                      cover: song?.cover ?? '',
                      size: alignedWidth,
                      width: alignedWidth,
                      height: metrics.value(150, minimum: 82),
                      radius: 18,
                    ),
                    SizedBox(height: metrics.value(18, minimum: 10)),
                    Expanded(child: _lyricPanel(context)),
                  ],
                ),
              ),
            ),
            SizedBox(height: metrics.value(18, minimum: 8)),
            SizedBox(
              width: alignedWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song?.name ?? '还没有播放歌曲',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.hero(size: metrics.font(34)),
                  ),
                  SizedBox(height: metrics.value(8, minimum: 4)),
                  Text(
                    song?.singer ?? '从场景或搜索开始',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.body(
                        size: metrics.font(23), color: TvTokens.muted),
                  ),
                ],
              ),
            ),
            SizedBox(height: metrics.value(18, minimum: 8)),
            SizedBox(width: alignedWidth, child: _homeProgress(metrics)),
            SizedBox(height: metrics.value(18, minimum: 8)),
            SizedBox(
              width: alignedWidth,
              child: TvPlayerControls(
                onPrevious: () =>
                    _changeTrack(_player.prev, _previousFocusNode),
                onRewind: () => _seekBy(-10),
                onPlayPause: _player.togglePlayPause,
                onForward: () => _seekBy(10),
                onNext: () => _changeTrack(_player.next, _nextFocusNode),
                onFavorite: _toggleFavorite,
                onQueue: _openQueue,
                onRelatedSearch: () => _openMenu(_TvPlayerMenu.relatedSearch),
                isPlaying: _player.isPlaying,
                isFavorite: _isFavorite,
                previousFocusNode: _previousFocusNode,
                nextFocusNode: _nextFocusNode,
                queueFocusNode: _queueButtonFocusNode,
                relatedSearchFocusNode: _relatedSearchFocusNode,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _lyricPanel(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final song = _player.currentSong;
    final lines = song == null
        ? <LyricLine>[]
        : _visibleLyricTexts(song, metrics.isCompact ? 4 : 6);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.value(12, minimum: 7),
        metrics.value(10, minimum: 6),
        metrics.value(12, minimum: 7),
        0,
      ),
      child: Center(
        child: lines.isEmpty
            ? Text(song == null ? '播放歌曲后显示歌词' : '正在获取歌词',
                style: TvTokens.body(
                    size: metrics.font(24), color: TvTokens.muted))
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.value(18, minimum: 10),
                  vertical: metrics.value(8, minimum: 4),
                ),
                itemCount: lines.length,
                separatorBuilder: (_, __) =>
                    SizedBox(height: metrics.value(12, minimum: 6)),
                itemBuilder: (_, index) {
                  final line = lines[index];
                  if (index == 0) {
                    final nextLine =
                        lines.length > 1 ? lines[1] : _nextLyricLine(line);
                    return _TvKaraokeText(
                      key: ValueKey(line.startMs),
                      text: line.text,
                      progress: _lineProgress(line, nextLine),
                      activeStyle: TvTokens.hero(size: metrics.font(30)),
                      inactiveStyle: TvTokens.hero(
                        size: metrics.font(30),
                      ).copyWith(color: TvTokens.muted),
                    );
                  }
                  return Text(
                    line.text,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.title(
                      size: metrics.font(22),
                      color: index < 3 ? TvTokens.text : TvTokens.muted,
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _modePanel(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    return TvSectionCard(
      title: '常用模式',
      titleAlign: TextAlign.center,
      padding: EdgeInsets.all(metrics.value(24, minimum: 14)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final spacing = metrics.value(12, minimum: 7);
          final gridPadding = metrics.value(12, minimum: 7);
          final availableRowsHeight =
              constraints.maxHeight - gridPadding * 2 - spacing * 2;
          final rowExtent = (availableRowsHeight / 3).clamp(68.0, 150.0);
          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.all(gridPadding),
            itemCount: listeningModes.length + 2,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              mainAxisExtent: rowExtent,
            ),
            itemBuilder: (_, index) {
              if (index == 0) {
                return TvFocusCard(
                  autofocus: false,
                  focusNode: _favoritesFocusNode,
                  onTap: () =>
                      Navigator.of(context).pushNamed(TvRoutes.favorites),
                  radius: metrics.value(22, minimum: 12),
                  padding: EdgeInsets.all(metrics.value(10, minimum: 6)),
                  color: Colors.black.withValues(alpha: 0.16),
                  borderColor: Colors.white.withValues(alpha: 0.08),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.favorite_rounded,
                        size: metrics.value(34, minimum: 24),
                        color: TvTokens.focus,
                      ),
                      SizedBox(height: metrics.value(7, minimum: 4)),
                      Text(
                        '收藏',
                        textAlign: TextAlign.center,
                        style: TvTokens.title(size: metrics.font(18)),
                      ),
                    ],
                  ),
                );
              }
              if (index == listeningModes.length + 1) {
                return TvFocusCard(
                  autofocus: false,
                  focusNode: _cacheFocusNode,
                  onTap: _confirmClearCache,
                  radius: metrics.value(22, minimum: 12),
                  padding: EdgeInsets.all(metrics.value(10, minimum: 6)),
                  color: Colors.black.withValues(alpha: 0.16),
                  borderColor: Colors.white.withValues(alpha: 0.08),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cleaning_services_rounded,
                        size: metrics.value(34, minimum: 24),
                        color: TvTokens.focus,
                      ),
                      SizedBox(height: metrics.value(7, minimum: 4)),
                      Text(
                        '清理缓存',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvTokens.title(size: metrics.font(18)),
                      ),
                      SizedBox(height: metrics.value(3, minimum: 2)),
                      Text(
                        _formatCacheSize(_audioCacheBytes),
                        textAlign: TextAlign.center,
                        style: TvTokens.label(size: metrics.font(14)),
                      ),
                    ],
                  ),
                );
              }
              final mode = listeningModes[index - 1];
              final modeFocusNode = _modeFocusNodes.putIfAbsent(
                mode.subQueueType,
                FocusNode.new,
              );
              return TvFocusCard(
                autofocus: false,
                focusNode: modeFocusNode,
                onTap: () => _playMode(mode, modeFocusNode),
                radius: metrics.value(22, minimum: 12),
                padding: EdgeInsets.all(metrics.value(10, minimum: 6)),
                color: Colors.black.withValues(alpha: 0.16),
                borderColor: Colors.white.withValues(alpha: 0.08),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      mode.icon,
                      size: metrics.value(34, minimum: 24),
                      color: TvTokens.focus,
                    ),
                    SizedBox(height: metrics.value(7, minimum: 4)),
                    Text(
                      mode.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.title(size: metrics.font(18)),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _loadingOverlay(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final preparing = _downloadProgress != null && _downloadProgress! < 0;
    final text = _loadingMessage ?? (preparing ? '正在准备播放' : '正在缓存音乐');
    final progress =
        _downloadProgress == null || preparing ? null : _downloadProgress;
    return Positioned.fill(
      child: AbsorbPointer(
        child: Material(
          color: Colors.black.withValues(alpha: 0.28),
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.value(34, minimum: 20),
                vertical: metrics.value(24, minimum: 16),
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius:
                    BorderRadius.circular(metrics.value(26, minimum: 16)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: metrics.value(34, minimum: 22),
                    height: metrics.value(34, minimum: 22),
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: metrics.value(3, minimum: 2),
                      color: TvTokens.focus,
                    ),
                  ),
                  SizedBox(width: metrics.value(18, minimum: 10)),
                  Text(text, style: TvTokens.title(size: metrics.font(26))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorOverlay(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final canRetry = _player.currentIndex >= 0;
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.82),
        child: FocusScope(
          autofocus: true,
          child: Center(
            child: Container(
              width: metrics.value(760, minimum: 430),
              padding: EdgeInsets.all(metrics.value(34, minimum: 20)),
              decoration: BoxDecoration(
                color: ThemeService.bgHint.value,
                borderRadius:
                    BorderRadius.circular(metrics.value(28, minimum: 16)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: TvTokens.danger,
                      size: metrics.value(58, minimum: 38)),
                  SizedBox(height: metrics.value(16, minimum: 9)),
                  Text('操作未完成', style: TvTokens.title(size: metrics.font(34))),
                  SizedBox(height: metrics.value(10, minimum: 6)),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TvTokens.body(
                        size: metrics.font(23), color: TvTokens.muted),
                  ),
                  SizedBox(height: metrics.value(24, minimum: 14)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (canRetry) ...[
                        TvPillButton(
                          label: '重试播放',
                          icon: Icons.refresh_rounded,
                          autofocus: true,
                          onTap: _retryPlayback,
                        ),
                        SizedBox(width: metrics.value(16, minimum: 8)),
                      ],
                      TvPillButton(
                        label: '关闭',
                        icon: Icons.close_rounded,
                        autofocus: !canRetry,
                        onTap: () => setState(() => _errorMessage = null),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuOverlay(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final song = _player.currentSong;
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.78),
        child: FocusScope(
          autofocus: true,
          child: Center(
            child: Container(
              width: metrics.value(820, minimum: 460),
              constraints: BoxConstraints(
                  maxHeight: metrics.size.height - metrics.topInset * 2),
              padding: EdgeInsets.all(metrics.value(30, minimum: 18)),
              decoration: BoxDecoration(
                color: ThemeService.bgHint.value,
                borderRadius:
                    BorderRadius.circular(metrics.value(30, minimum: 18)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: _relatedSearchMenu(metrics, song!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _relatedSearchMenu(TvLayoutMetrics metrics, Song song) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('搜索同名歌曲或歌手', style: TvTokens.title(size: metrics.font(36))),
        SizedBox(height: metrics.value(20, minimum: 12)),
        TvPillButton(
          label: '歌曲名：${song.name}',
          icon: Icons.music_note_rounded,
          fullWidth: true,
          autofocus: true,
          onTap: () => _searchRelated(song.name),
        ),
        SizedBox(height: metrics.value(12, minimum: 7)),
        TvPillButton(
          label: '歌手：${song.singer}',
          icon: Icons.person_rounded,
          fullWidth: true,
          onTap: () => _searchRelated(song.singer),
        ),
      ],
    );
  }

  Widget _homeProgress(TvLayoutMetrics metrics) {
    final duration = _player.liveDuration;
    final position = _player.livePosition;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return Row(
      children: [
        Text(_formatDuration(position),
            style:
                TvTokens.label(size: metrics.font(17), color: TvTokens.text)),
        SizedBox(width: metrics.value(12, minimum: 6)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: metrics.value(7, minimum: 4),
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(TvTokens.focus),
            ),
          ),
        ),
        SizedBox(width: metrics.value(12, minimum: 6)),
        Text(_formatDuration(duration),
            style:
                TvTokens.label(size: metrics.font(17), color: TvTokens.text)),
      ],
    );
  }

  List<LyricLine> _parseLrc(String? lyric) => parseLyrics(lyric);

  int _currentLrcIndex() {
    if (_parsedLrc.isEmpty) return -1;
    final posMs = _player.livePosition.inMilliseconds;
    var left = 0;
    var right = _parsedLrc.length - 1;
    var idx = -1;
    while (left <= right) {
      final mid = (left + right) ~/ 2;
      if (_parsedLrc[mid].startMs <= posMs) {
        idx = mid;
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }
    return idx;
  }

  LyricLine? _nextLyricLine(LyricLine line) {
    final index = _parsedLrc.indexOf(line);
    return index >= 0 && index + 1 < _parsedLrc.length
        ? _parsedLrc[index + 1]
        : null;
  }

  double _lineProgress(LyricLine line, LyricLine? nextLine) {
    final positionMs = _player.livePosition.inMilliseconds;
    if (line.syllables.length > 1 || line.durationMs > 0) {
      return lyricProgressAt(line, positionMs);
    }
    if (positionMs <= line.startMs) return 0;
    final endMs = nextLine?.startMs ?? line.startMs + 4000;
    final durationMs = (endMs - line.startMs).clamp(1, 12000);
    return ((positionMs - line.startMs) / durationMs).clamp(0.0, 1.0);
  }

  List<LyricLine> _visibleLyricTexts(Song song, int count) {
    final idx = _currentLrcIndex();
    if (idx >= 0 && idx < _parsedLrc.length) {
      final lines = _parsedLrc
          .skip(idx)
          .take(count)
          .where((line) => line.text.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) return lines;
    }
    final first = _firstLyric(song.lyric);
    final fallback = song.album.isNotEmpty ? song.album : '歌词加载后会显示在这里';
    return [
      LyricLine(0, 0, [LyricSyllable(0, 0, first)]),
      LyricLine(0, 0, [LyricSyllable(0, 0, fallback)])
    ];
  }

  String _firstLyric(String? lyric) {
    if (lyric == null || lyric.isEmpty) return '正在获取歌词';
    final line = lyric
        .split('\n')
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '正在获取歌词')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'<\d+,\d+,\d+>'), '')
        .trim();
    return line.isEmpty ? '正在获取歌词' : line;
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _TvKaraokeText extends StatelessWidget {
  final String text;
  final double progress;
  final TextStyle activeStyle;
  final TextStyle inactiveStyle;

  const _TvKaraokeText({
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
        final width =
            (painter.width.ceilToDouble() + 6).clamp(0.0, constraints.maxWidth);
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
                  fit: StackFit.expand,
                  children: [
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: inactiveStyle,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ClipRect(
                        child: SizedBox(
                          width: revealWidth,
                          height: height,
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: width,
                            maxWidth: width,
                            minHeight: height,
                            maxHeight: height,
                            child: Text(
                              text,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: activeStyle,
                            ),
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
      },
    );
  }
}
