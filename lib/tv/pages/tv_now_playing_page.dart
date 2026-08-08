import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/music_api.dart';
import '../../models/song.dart';
import '../../models/listening_mode.dart';
import '../../services/favorites_service.dart';
import '../../services/player_service.dart';
import '../../services/settings_service.dart';
import '../../services/theme_service.dart';
import '../tv_layout_metrics.dart';
import '../tv_routes.dart';
import '../tv_tokens.dart';
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

enum _TvPlayerMenu { quality, relatedSearch }

class _TvNowPlayingPageState extends State<TvNowPlayingPage> {
  final _player = PlayerService();
  final _queueFocusNode = FocusNode();
  final _queueButtonFocusNode = FocusNode();
  final _qualityButtonFocusNode = FocusNode();
  final _relatedSearchFocusNode = FocusNode();
  final _searchFocusNode = FocusNode();
  final Map<String, FocusNode> _modeFocusNodes = {};
  FocusNode? _queueReturnFocusNode;
  Timer? _timer;
  bool _queueOpen = false;
  bool _isFavorite = false;
  double? _downloadProgress;
  String? _loadingMessage;
  String? _errorMessage;
  _TvPlayerMenu? _activeMenu;
  List<LyricLine> _parsedLrc = [];
  List<StreamQuality> _availableQualities = const [];
  bool _qualitiesLoading = false;
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
    _refreshFavoriteState();
    _syncLyrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (TvRoutes.consumeHomeQueueFocusRequest()) {
        _queueButtonFocusNode.requestFocus();
      } else {
        _searchFocusNode.requestFocus();
      }
    });
    // Keep TV rendering deliberately light. The player emits position events
    // much more frequently than a low-memory TV can repaint the full page.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _syncLyrics();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.removeProgressListener(_onProgress);
    _player.removeSongChangeListener(_onSongChange);
    _player.removePlayStateListener(_onPlayState);
    _player.removeDownloadProgressListener(_onDownloadProgress);
    _player.removePlaybackErrorListener(_onPlaybackError);
    FavoritesService.version.removeListener(_refreshFavoriteState);
    _queueFocusNode.dispose();
    _queueButtonFocusNode.dispose();
    _qualityButtonFocusNode.dispose();
    _relatedSearchFocusNode.dispose();
    _searchFocusNode.dispose();
    for (final node in _modeFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onProgress(Duration _, Duration? __) {
    // The 1-second UI timer above is the sole repaint clock for progress and
    // lyrics; rebuilding on every media-kit position event can starve remote
    // control input and trigger an Android input ANR on low-end TVs.
  }

  void _onSongChange(Song song) {
    _parsedLrc = _parseLrc(song.lyric);
    _availableQualities = const [];
    _refreshFavoriteState();
    if (mounted) setState(() {});
  }

  void _onPlayState(bool _) {
    if (mounted) setState(() {});
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
    if (!mounted) return;
    _closeQueue();
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

  void _openMenu(_TvPlayerMenu menu) {
    if (menu == _TvPlayerMenu.relatedSearch && _player.currentSong == null) {
      setState(() => _errorMessage = '请先播放一首歌曲，再搜索同名歌曲或歌手。');
      return;
    }
    setState(() => _activeMenu = menu);
    if (menu == _TvPlayerMenu.quality) {
      unawaited(_loadAvailableQualities());
    }
  }

  Future<void> _loadAvailableQualities() async {
    final song = _player.currentSong;
    if (song == null) return;
    setState(() => _qualitiesLoading = true);
    try {
      final info = await MusicApi.getStreamInfo(song.id);
      if (mounted && identical(song, _player.currentSong)) {
        setState(() => _availableQualities = info.qualities);
      }
    } catch (_) {
      if (mounted) setState(() => _availableQualities = const []);
    } finally {
      if (mounted) setState(() => _qualitiesLoading = false);
    }
  }

  void _closeMenu() {
    final menu = _activeMenu;
    setState(() => _activeMenu = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (menu == _TvPlayerMenu.quality) {
        _qualityButtonFocusNode.requestFocus();
      } else if (menu == _TvPlayerMenu.relatedSearch) {
        _relatedSearchFocusNode.requestFocus();
      }
    });
  }

  Future<void> _selectQuality(AudioQuality quality) async {
    final oldBr = SettingsService().quality.br;
    await SettingsService().setQuality(quality);
    if (!mounted) return;
    _closeMenu();
    setState(() {});
    if (oldBr != quality.br && _player.currentSong != null) {
      await _player.redownloadCurrentAtNewQuality();
    }
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

  String _qualityLabel() {
    final actual = _player.currentPlayingBr;
    if (actual > 0 && actual < 999) return '${actual}K';
    switch (SettingsService().quality) {
      case AudioQuality.medium:
        return '68K';
      case AudioQuality.higher:
        return '132K';
      case AudioQuality.highest:
        return '260K';
      case AudioQuality.hiRes:
        return '320K';
      case AudioQuality.spatial:
        return '空间音频';
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final interactionBlocked = _queueOpen ||
        _loadingMessage != null ||
        _downloadProgress != null ||
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
                child: _lyricPanel(context),
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
                onPrevious: _player.prev,
                onRewind: () => _seekBy(-10),
                onPlayPause: _player.togglePlayPause,
                onForward: () => _seekBy(10),
                onNext: _player.next,
                onFavorite: _toggleFavorite,
                onQueue: _openQueue,
                onQuality: () => _openMenu(_TvPlayerMenu.quality),
                onRelatedSearch: () => _openMenu(_TvPlayerMenu.relatedSearch),
                isPlaying: _player.isPlaying,
                isFavorite: _isFavorite,
                qualityLabel: _qualityLabel(),
                queueFocusNode: _queueButtonFocusNode,
                qualityFocusNode: _qualityButtonFocusNode,
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
    return TvSectionCard(
      title: '歌词',
      titleAlign: TextAlign.center,
      padding: EdgeInsets.all(metrics.value(18, minimum: 10)),
      child: Center(
        child: lines.isEmpty
            ? Text(song == null ? '播放歌曲后显示歌词' : '正在获取歌词',
                style: TvTokens.body(
                    size: metrics.font(24), color: TvTokens.muted))
            : ListView.separated(
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.value(18, minimum: 10),
                  vertical: metrics.value(8, minimum: 4),
                ),
                itemCount: lines.length,
                separatorBuilder: (_, __) =>
                    SizedBox(height: metrics.value(12, minimum: 6)),
                itemBuilder: (_, index) => Text(
                  lines[index].text,
                  textAlign: TextAlign.center,
                  maxLines: index == 0 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: index == 0
                      ? TvTokens.hero(size: metrics.font(30))
                      : TvTokens.title(
                          size: metrics.font(22),
                          color: index < 3 ? TvTokens.text : TvTokens.muted,
                        ),
                ),
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
        builder: (context, constraints) => GridView.builder(
          padding: EdgeInsets.all(metrics.value(14, minimum: 10)),
          itemCount: listeningModes.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: metrics.gridColumnCount(constraints.maxWidth),
            crossAxisSpacing: metrics.value(18, minimum: 10),
            mainAxisSpacing: metrics.value(18, minimum: 10),
            childAspectRatio: metrics.isCompact ? 1.25 : 1.18,
          ),
          itemBuilder: (_, index) {
            final mode = listeningModes[index];
            final modeFocusNode = _modeFocusNodes.putIfAbsent(
              mode.subQueueType,
              FocusNode.new,
            );
            return TvFocusCard(
              autofocus: false,
              focusNode: modeFocusNode,
              onTap: () => _playMode(mode, modeFocusNode),
              radius: metrics.value(22, minimum: 12),
              padding: EdgeInsets.all(metrics.value(18, minimum: 10)),
              color: Colors.black.withValues(alpha: 0.16),
              borderColor: Colors.white.withValues(alpha: 0.08),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    mode.icon,
                    size: metrics.value(50, minimum: 34),
                    color: TvTokens.focus,
                  ),
                  SizedBox(height: metrics.value(12, minimum: 6)),
                  Text(
                    mode.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.title(size: metrics.font(22)),
                  ),
                ],
              ),
            );
          },
        ),
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
    final menu = _activeMenu!;
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
              child: menu == _TvPlayerMenu.quality
                  ? _qualityMenu(metrics)
                  : _relatedSearchMenu(metrics, song!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _qualityMenu(TvLayoutMetrics metrics) {
    final options = _availableQualities.isEmpty
        ? AudioQuality.values.toList()
        : AudioQuality.values
            .where((quality) => _availableQualities
                .any((item) => item.quality == quality.apiValue))
            .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('音质选择', style: TvTokens.title(size: metrics.font(36))),
        SizedBox(height: metrics.value(8, minimum: 5)),
        Text(
          '切换后会保持当前进度重新播放，TV 端不会写入音乐缓存。',
          style: TvTokens.body(size: metrics.font(20), color: TvTokens.muted),
        ),
        SizedBox(height: metrics.value(20, minimum: 12)),
        if (_qualitiesLoading) ...[
          const Center(child: CircularProgressIndicator(color: TvTokens.focus)),
          SizedBox(height: metrics.value(16, minimum: 10)),
        ],
        for (var index = 0; index < options.length; index++) ...[
          TvPillButton(
            label: _qualityOptionLabel(options[index]),
            icon: SettingsService().quality == options[index]
                ? Icons.check_circle_rounded
                : Icons.circle_outlined,
            selected: SettingsService().quality == options[index],
            fullWidth: true,
            autofocus: index == 0,
            onTap: () => _selectQuality(options[index]),
          ),
          if (index < options.length - 1)
            SizedBox(height: metrics.value(10, minimum: 6)),
        ],
      ],
    );
  }

  String _qualityOptionLabel(AudioQuality quality) {
    final matches = _availableQualities
        .where((item) => item.quality == quality.apiValue)
        .toList();
    if (matches.isEmpty) return quality.label;
    final name = switch (quality) {
      AudioQuality.medium => '标准',
      AudioQuality.higher => '高品质',
      AudioQuality.highest => '最高',
      AudioQuality.hiRes => 'Hi-Res',
      AudioQuality.spatial => '空间音频',
    };
    return '$name · ${matches.first.bitrateKbps}kbps';
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
