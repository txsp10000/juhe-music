import 'dart:math';
import 'package:flutter/material.dart';
import '../api/music_api.dart';
import '../data/categories.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../utils/toast.dart';
import '../widgets/mode_drawer.dart';
import 'search_result_page.dart';

class SearchPage extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onShowPlayer;
  const SearchPage({super.key, this.embedded = false, this.onShowPlayer});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _player = PlayerService();
  List<String> _history = [];
  bool _modePanelOpen = false;
  Color _accent = AppDesignTokens.lyricWhite;
  Color _bgHint = AppDesignTokens.inkBlack;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _controller.addListener(_refreshChrome);
    _focusNode.addListener(_refreshChrome);
    _onThemeChange();
    ThemeService.accentColor.addListener(_onThemeChange);
    ThemeService.bgHint.addListener(_onThemeChange);
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

  void _refreshChrome() {
    if (mounted) setState(() {});
  }

  void _openModePanel() {
    if (mounted) setState(() => _modePanelOpen = true);
  }

  void _closeModePanel() {
    if (mounted) setState(() => _modePanelOpen = false);
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
      widget.onShowPlayer?.call();
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
    widget.onShowPlayer?.call();
  }

  Future<void> _randomPlay() async {
    final playlists =
        playlistCategories.values.expand((items) => items).toList();
    if (playlists.isEmpty) {
      Toast.show(context, '暂无可随机播放的歌单');
      return;
    }
    final random = Random();
    _loadAndPlay(playlists[random.nextInt(playlists.length)]);
  }

  @override
  void dispose() {
    _controller.removeListener(_refreshChrome);
    _focusNode.removeListener(_refreshChrome);
    _controller.dispose();
    _focusNode.dispose();
    ThemeService.accentColor.removeListener(_onThemeChange);
    ThemeService.bgHint.removeListener(_onThemeChange);
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final h = await SearchHistoryService.load();
    if (mounted) setState(() => _history = h);
  }

  Future<void> _doSearch(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    _focusNode.unfocus();
    await SearchHistoryService.save(trimmed);
    if (!mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SearchResultPage(
                keyword: trimmed, onShowPlayer: widget.onShowPlayer)));
    if (mounted) _loadHistory();
  }

  Future<void> _clearHistory() async {
    for (final kw in List<String>.from(_history)) {
      await SearchHistoryService.removeOne(kw);
    }
    if (mounted) setState(() => _history.clear());
  }

  Future<void> _removeHistory(String kw) async {
    await SearchHistoryService.removeOne(kw);
    if (mounted) setState(() => _history.remove(kw));
  }

  @override
  Widget build(BuildContext context) {
    final panelWidth = min(MediaQuery.of(context).size.width * 0.78, 330.0);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          MusicScaffoldBackground(
            bgHint: _bgHint,
            accent: _accent,
            child: SafeArea(
              bottom: false,
              child: ListView(
                padding:
                    EdgeInsets.fromLTRB(20, 18, 20, widget.embedded ? 106 : 24),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 22),
                  _buildSearchBar(),
                  const SizedBox(height: 30),
                  _buildHistory(),
                ],
              ),
            ),
          ),
          if (_modePanelOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeModePanel,
                child: Container(color: Colors.black.withOpacity(0.40)),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: _modePanelOpen ? 0 : -panelWidth,
            top: 0,
            bottom: 0,
            width: panelWidth,
            child: ModeDrawer(
              onSelectPlaylist: _loadAndPlay,
              onOpenFavorites: _openFavorites,
              onRandomPlay: _randomPlay,
              onClose: _closeModePanel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    if (widget.embedded) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openModePanel,
        child: Row(
          children: [
            const Icon(Icons.menu_rounded,
                color: AppDesignTokens.lyricWhite, size: 34),
            const SizedBox(width: 10),
            Text('模式选择', style: AppDesignTokens.title(size: 26)),
          ],
        ),
      );
    }
    return Row(
      children: [
        GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_rounded,
                color: AppDesignTokens.lyricWhite, size: 30)),
        const SizedBox(width: 10),
        Text('搜索', style: AppDesignTokens.display(size: 30)),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(26)),
      child: Row(
        children: [
          Icon(Icons.search_rounded,
              color: AppDesignTokens.warmWhite.withOpacity(0.65), size: 25),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: !widget.embedded,
              cursorColor: _accent,
              style: AppDesignTokens.body(size: 16, weight: FontWeight.w800),
              textInputAction: TextInputAction.search,
              onSubmitted: _doSearch,
              decoration:
                  const InputDecoration(border: InputBorder.none, hintText: ''),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
                onTap: () => _controller.clear(),
                child: Icon(Icons.close_rounded,
                    color: AppDesignTokens.warmWhite.withOpacity(0.65),
                    size: 20)),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('搜索历史', style: AppDesignTokens.title(size: 19)),
            const Spacer(),
            if (_history.isNotEmpty)
              GestureDetector(
                  onTap: _clearHistory,
                  child: Icon(Icons.delete_outline_rounded,
                      color: AppDesignTokens.warmWhite.withOpacity(0.58),
                      size: 28)),
          ],
        ),
        const SizedBox(height: 16),
        if (_history.isEmpty)
          Text('暂无搜索历史',
              style: AppDesignTokens.body(
                  color: AppDesignTokens.warmWhite.withOpacity(0.55)))
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _history.map((kw) => _historyChip(kw)).toList(),
          ),
      ],
    );
  }

  Widget _historyChip(String kw) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
              onTap: () => _doSearch(kw),
              child: Text(kw,
                  style:
                      AppDesignTokens.body(size: 14, weight: FontWeight.w800))),
          const SizedBox(width: 8),
          GestureDetector(
              onTap: () => _removeHistory(kw),
              child: Icon(Icons.close_rounded,
                  color: AppDesignTokens.warmWhite.withOpacity(0.60),
                  size: 16)),
        ],
      ),
    );
  }
}
