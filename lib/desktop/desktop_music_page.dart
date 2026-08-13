import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/music_api.dart';
import '../models/listening_mode.dart';
import '../models/song.dart';
import '../services/cover_cache_service.dart';
import '../services/favorites_service.dart';
import '../services/playback_history_service.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../utils/lyric_parser.dart';

enum _DesktopSection { nowPlaying, modes, search, favorites, history, queue }

class DesktopMusicPage extends StatefulWidget {
  const DesktopMusicPage({super.key});

  @override
  State<DesktopMusicPage> createState() => _DesktopMusicPageState();
}

class _DesktopMusicPageState extends State<DesktopMusicPage> {
  final PlayerService _player = PlayerService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  _DesktopSection _section = _DesktopSection.modes;
  List<Song> _searchResults = const [];
  List<Song> _favorites = const [];
  List<Song> _history = const [];
  bool _loadingSearch = false;
  bool _loadingFavorites = false;
  bool _loadingHistory = false;
  int? _loadingModeId;
  String? _searchError;
  String _searchKeyword = '';
  Color _bgHint = AppDesignTokens.queueBackground;

  static const _window = Color(0xFF0B0C0E);
  static const _sidebar = Color(0xFF191A1D);
  static const _surface = Color(0xFF111214);
  static const _surfaceRaised = Color(0xFF1D1F22);
  static const _text = Color(0xFFF3F1F2);
  static const _muted = Color(0xFFA6A2A5);
  static const _faint = Color(0xFF6D696D);

  @override
  void initState() {
    super.initState();
    _player.addSongChangeListener(_onSongChanged);
    _player.addPlayStateListener(_onPlayStateChanged);
    _player.addProgressListener(_onProgressChanged);
    FavoritesService.version.addListener(_onFavoritesChanged);
    ThemeService.bgHint.addListener(_onThemeChanged);
    _bgHint = ThemeService.bgHint.value;
    unawaited(_loadFavorites());
    unawaited(_loadHistory());
  }

  void _onSongChanged(Song _) {
    ThemeService.reset();
    if (mounted) setState(() {});
    unawaited(_loadHistory());
  }

  void _onPlayStateChanged(bool _) {
    if (mounted) setState(() {});
  }

  void _onProgressChanged(Duration _, Duration? __) {
    if (mounted) setState(() {});
  }

  void _onFavoritesChanged() {
    unawaited(_loadFavorites());
  }

  void _onThemeChanged() {
    if (mounted) setState(() => _bgHint = ThemeService.bgHint.value);
  }

  @override
  void dispose() {
    _player.removeSongChangeListener(_onSongChanged);
    FavoritesService.version.removeListener(_onFavoritesChanged);
    ThemeService.bgHint.removeListener(_onThemeChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Color get _themeAccent => AppDesignTokens.readableAccent(_bgHint);

  Color get _themeWindow => Color.alphaBlend(
        _bgHint.withValues(alpha: 0.10),
        _window,
      );

  Color get _themeSidebar => Color.alphaBlend(
        _bgHint.withValues(alpha: 0.18),
        _sidebar,
      );

  Color get _themeSurface => Color.alphaBlend(
        _bgHint.withValues(alpha: 0.16),
        _surface,
      );

  Color get _themeRaised => Color.alphaBlend(
        _bgHint.withValues(alpha: 0.26),
        _surfaceRaised,
      );

  Future<void> _loadFavorites() async {
    if (mounted) setState(() => _loadingFavorites = true);
    final songs = await FavoritesService.load();
    if (!mounted) return;
    setState(() {
      _favorites = songs;
      _loadingFavorites = false;
    });
  }

  Future<void> _loadHistory() async {
    if (mounted) setState(() => _loadingHistory = true);
    final songs = await PlaybackHistoryService.load();
    if (!mounted) return;
    setState(() {
      _history = songs;
      _loadingHistory = false;
    });
  }

  Future<void> _search(String raw) async {
    final keyword = raw.trim();
    setState(() {
      _section = _DesktopSection.search;
      _searchKeyword = keyword;
      _searchError = null;
      _loadingSearch = keyword.isNotEmpty;
      if (keyword.isEmpty) _searchResults = const [];
    });
    if (keyword.isEmpty) return;
    await SearchHistoryService.save(keyword);
    try {
      final result = await MusicApi.searchTracks(keyword);
      if (mounted) setState(() => _searchResults = result.songs);
    } catch (_) {
      if (mounted) setState(() => _searchError = '搜索失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _loadingSearch = false);
    }
  }

  Future<void> _selectMode(ListeningMode mode) async {
    setState(() => _loadingModeId = mode.sceneModeId);
    try {
      final songs = await MusicApi.getModeTracks(sceneModeId: mode.sceneModeId);
      if (songs.isEmpty) {
        _showMessage('「${mode.name}」暂时没有歌曲');
        return;
      }
      _player.replaceQueue(songs, mode: mode);
      await _player.playAt(0);
      if (mounted) setState(() => _section = _DesktopSection.nowPlaying);
    } catch (_) {
      _showMessage('听歌场景加载失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loadingModeId = null);
    }
  }

  Future<void> _playSongs(
    List<Song> songs,
    int index, {
    PlaybackQueueSource source = PlaybackQueueSource.regular,
  }) async {
    if (songs.isEmpty) return;
    _player.replaceQueue(songs, source: source);
    await _player.playAt(index);
  }

  Future<void> _toggleFavorite(Song song) async {
    if (_isFavorite(song)) {
      await FavoritesService.remove(song);
    } else {
      await FavoritesService.save(song);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _themeRaised,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _themeWindow,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          return Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSidebar(compact),
                    Expanded(
                      child: Column(
                        children: [
                          _buildTopBar(compact),
                          Divider(
                            height: 1,
                            color: _themeAccent.withValues(alpha: 0.18),
                          ),
                          Expanded(child: _buildContent()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildTransportBar(compact),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebar(bool compact) {
    final width = compact ? 76.0 : 216.0;
    return Container(
      width: width,
      color: _themeSidebar,
      padding:
          EdgeInsets.fromLTRB(compact ? 10 : 16, 20, compact ? 10 : 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment:
                  compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                const Icon(Icons.graphic_eq_rounded, color: _text, size: 25),
                if (!compact) ...[
                  const SizedBox(width: 10),
                  const Text(
                    '音乐',
                    style: TextStyle(
                      color: _text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          _navItem(Icons.play_arrow_rounded, '正在播放', _DesktopSection.nowPlaying,
              compact),
          _navItem(
              Icons.explore_outlined, '听歌场景', _DesktopSection.modes, compact),
          _navItem(Icons.search_rounded, '搜索', _DesktopSection.search, compact),
          if (!compact) ...[
            const SizedBox(height: 28),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '我的音乐',
                style: TextStyle(
                  color: _faint,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 18),
          _navItem(Icons.favorite_border_rounded, '我的收藏',
              _DesktopSection.favorites, compact),
          _navItem(
              Icons.history_rounded, '历史播放', _DesktopSection.history, compact),
          _navItem(Icons.queue_music_rounded, '当前队列', _DesktopSection.queue,
              compact),
          const Spacer(),
          if (!compact)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'Windows 客户端',
                style: TextStyle(color: _faint, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _navItem(
    IconData icon,
    String label,
    _DesktopSection section,
    bool compact,
  ) {
    final selected = _section == section;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: compact ? label : '',
        child: Material(
          color: selected ? _themeRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: () {
              setState(() => _section = section);
              if (section == _DesktopSection.search) {
                _searchFocus.requestFocus();
              }
              if (section == _DesktopSection.history) unawaited(_loadHistory());
            },
            borderRadius: BorderRadius.circular(6),
            hoverColor: _themeAccent.withValues(alpha: 0.16),
            child: SizedBox(
              height: 40,
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  if (!compact) const SizedBox(width: 10),
                  Icon(
                    icon,
                    color: selected ? _text : _muted,
                    size: 19,
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? _text : _muted,
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool compact) {
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Text(
              _sectionTitle,
              style: const TextStyle(
                color: _text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: compact ? 260 : 360,
              height: 38,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onSubmitted: _search,
                style: const TextStyle(color: _text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '搜索歌曲、歌手或专辑',
                  hintStyle: const TextStyle(color: _faint, fontSize: 13),
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: _muted, size: 18),
                  suffixIcon: IconButton(
                    tooltip: '搜索',
                    onPressed: () => _search(_searchController.text),
                    icon: const Icon(
                      Icons.arrow_forward_rounded,
                      color: _muted,
                      size: 18,
                    ),
                  ),
                  filled: true,
                  fillColor: _themeRaised,
                  contentPadding: EdgeInsets.zero,
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: _themeAccent, width: 1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _sectionTitle => switch (_section) {
        _DesktopSection.nowPlaying => '正在播放',
        _DesktopSection.modes => '听歌场景',
        _DesktopSection.search => '搜索',
        _DesktopSection.favorites => '我的收藏',
        _DesktopSection.history => '历史播放',
        _DesktopSection.queue => '当前队列',
      };

  Widget _buildContent() {
    return ColoredBox(
      color: _themeSurface,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: switch (_section) {
          _DesktopSection.nowPlaying => _buildNowPlaying(),
          _DesktopSection.modes => _buildModes(),
          _DesktopSection.search => _buildSearchResults(),
          _DesktopSection.favorites => _buildSongCollection(
              key: const ValueKey('favorites'),
              title: '我的收藏',
              subtitle: '${_favorites.length} 首歌曲',
              songs: _favorites,
              loading: _loadingFavorites,
              emptyIcon: Icons.favorite_border_rounded,
              emptyTitle: '还没有收藏歌曲',
              emptyMessage: '播放歌曲时点亮爱心，歌曲会出现在这里。',
              source: PlaybackQueueSource.favorites,
            ),
          _DesktopSection.history => _buildSongCollection(
              key: const ValueKey('history'),
              title: '历史播放',
              subtitle: '最近播放的 ${_history.length} 首歌曲',
              songs: _history,
              loading: _loadingHistory,
              emptyIcon: Icons.history_rounded,
              emptyTitle: '还没有播放记录',
              emptyMessage: '播放过的歌曲会自动保存在这里。',
            ),
          _DesktopSection.queue => _buildSongCollection(
              key: const ValueKey('queue'),
              title: '当前队列',
              subtitle: '${_player.queue.length} 首歌曲',
              songs: _player.queue,
              emptyIcon: Icons.queue_music_rounded,
              emptyTitle: '当前队列是空的',
              emptyMessage: '选择听歌场景或搜索歌曲后开始播放。',
              queueMode: true,
            ),
        },
      ),
    );
  }

  Widget _buildModes() {
    final featuredIds = <int>[33, 1, 5, 2, 6, 3, 40, 21];
    final featured = [
      for (final id in featuredIds)
        ...listeningModes.where((mode) => mode.sceneModeId == id),
    ];
    final remaining = listeningModes
        .where((mode) => !featuredIds.contains(mode.sceneModeId))
        .toList();

    return CustomScrollView(
      key: const ValueKey('modes'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(30, 28, 30, 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '常用场景',
                  style: TextStyle(
                    color: _text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '选择一个场景，立即生成播放队列。',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: featured.map(_buildFeaturedMode).toList(),
                ),
                const SizedBox(height: 32),
                const Text(
                  '更多听歌场景',
                  style: TextStyle(
                    color: _text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 34),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 250,
              mainAxisExtent: 108,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: remaining.length,
            itemBuilder: (context, index) => _buildModeCard(remaining[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturedMode(ListeningMode mode) {
    final selected = identical(_player.activeMode, mode);
    final loading = _loadingModeId == mode.sceneModeId;
    return SizedBox(
      width: 176,
      height: 48,
      child: Material(
        color: selected ? _themeAccent.withValues(alpha: 0.24) : _themeRaised,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: loading ? null : () => unawaited(_selectMode(mode)),
          borderRadius: BorderRadius.circular(7),
          hoverColor: _themeAccent.withValues(alpha: 0.16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                if (loading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _themeAccent,
                    ),
                  )
                else
                  Icon(
                    mode.icon,
                    size: 20,
                    color: selected ? _themeAccent : _text,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    mode.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard(ListeningMode mode) {
    final selected = identical(_player.activeMode, mode);
    final loading = _loadingModeId == mode.sceneModeId;
    return Material(
      color: selected ? _themeAccent.withValues(alpha: 0.19) : _themeRaised,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: loading ? null : () => unawaited(_selectMode(mode)),
        borderRadius: BorderRadius.circular(7),
        hoverColor: _themeAccent.withValues(alpha: 0.16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? _themeAccent.withValues(alpha: 0.24)
                      : const Color(0xFF2A2C30),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: loading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _themeAccent,
                        ),
                      )
                    : Icon(
                        mode.icon,
                        color: selected ? _themeAccent : _text,
                        size: 23,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '点按后开始播放',
                      style: TextStyle(color: _muted, fontSize: 12),
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

  Widget _buildSearchResults() {
    if (_loadingSearch) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: _themeAccent),
      );
    }
    if (_searchError != null) {
      return _EmptyView(
        key: const ValueKey('search-error'),
        icon: Icons.wifi_off_rounded,
        title: _searchError!,
        message: '请检查网络后重新搜索。',
      );
    }
    if (_searchKeyword.isEmpty) {
      return const _EmptyView(
        key: ValueKey('search-empty'),
        icon: Icons.search_rounded,
        title: '搜索你想听的歌',
        message: '在顶部输入歌曲、歌手或专辑名称。',
      );
    }
    return _buildSongCollection(
      key: ValueKey('search-$_searchKeyword'),
      title: '“$_searchKeyword”的搜索结果',
      subtitle: '${_searchResults.length} 首歌曲',
      songs: _searchResults,
      emptyIcon: Icons.search_off_rounded,
      emptyTitle: '没有找到相关歌曲',
      emptyMessage: '试试其他关键词。',
    );
  }

  Widget _buildSongCollection({
    required Key key,
    required String title,
    required String subtitle,
    required List<Song> songs,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyMessage,
    bool loading = false,
    bool queueMode = false,
    PlaybackQueueSource source = PlaybackQueueSource.regular,
  }) {
    if (loading) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: _themeAccent),
      );
    }
    if (songs.isEmpty) {
      return _EmptyView(
        key: key,
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(30, 28, 26, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => unawaited(
                  queueMode
                      ? _player.playAt(0)
                      : _playSongs(songs, 0, source: source),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('播放全部'),
                style: FilledButton.styleFrom(
                  backgroundColor: _text,
                  foregroundColor: _window,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _TrackHeader(),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              itemCount: songs.length,
              itemExtent: 58,
              itemBuilder: (context, index) {
                final song = songs[index];
                return _TrackRow(
                  song: song,
                  index: index,
                  active: _player.currentSong?.id == song.id,
                  favorite: _isFavorite(song),
                  removable: queueMode,
                  onTap: () => unawaited(
                    queueMode
                        ? _player.playAt(index)
                        : _playSongs(songs, index, source: source),
                  ),
                  onFavorite: () => unawaited(_toggleFavorite(song)),
                  onRemove: queueMode
                      ? () => unawaited(_player.removeAt(index))
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNowPlaying() {
    final song = _player.currentSong;
    if (song == null) {
      return const _EmptyView(
        key: ValueKey('now-playing-empty'),
        icon: Icons.music_note_rounded,
        title: '还没有正在播放的歌曲',
        message: '从听歌场景、搜索或收藏中选择一首歌曲。',
      );
    }
    final lyrics = parseLyrics(song.lyric);
    final lyricIndex =
        _activeLyricIndex(lyrics, _player.livePosition.inMilliseconds);
    return LayoutBuilder(
      key: ValueKey('now-playing-${song.id}'),
      builder: (context, constraints) {
        final artSize = (constraints.maxHeight * 0.48).clamp(220.0, 420.0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(44, 36, 44, 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: artSize,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DesktopAlbumArt(
                      song: song,
                      size: artSize,
                      radius: 8,
                      onBytesLoaded: (bytes) =>
                          unawaited(ThemeService.updateFromCover(bytes)),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      song.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 22,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            song.singer.isEmpty ? '未知歌手' : song.singer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _muted, fontSize: 14),
                          ),
                        ),
                        IconButton(
                          tooltip: _isFavorite(song) ? '取消收藏' : '收藏',
                          onPressed: () => unawaited(_toggleFavorite(song)),
                          icon: Icon(
                            _isFavorite(song)
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: _isFavorite(song) ? _themeAccent : _muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 52),
              Expanded(
                child: _Lyrics(
                  lines: lyrics,
                  currentIndex: lyricIndex,
                  positionMs: _player.livePosition.inMilliseconds,
                  accent: _themeAccent,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTransportBar(bool compact) {
    final song = _player.currentSong;
    final duration = _player.liveDuration;
    final position = _player.livePosition;
    final maximum = duration.inMilliseconds.toDouble();
    final value = maximum <= 0
        ? 0.0
        : position.inMilliseconds.toDouble().clamp(0.0, maximum);

    return Container(
      height: 92,
      decoration: BoxDecoration(
        color: Color.alphaBlend(_bgHint.withValues(alpha: 0.30), _themeSurface),
        border: Border(
          top: BorderSide(color: _themeAccent.withValues(alpha: 0.48)),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 14,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 3.5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: _text,
                inactiveTrackColor: _themeAccent.withValues(alpha: 0.30),
                thumbColor: _text,
              ),
              child: Slider(
                value: value,
                max: maximum <= 0 ? 1 : maximum,
                onChanged: maximum <= 0
                    ? null
                    : (next) => unawaited(
                          _player.seek(Duration(milliseconds: next.round())),
                        ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: compact ? 220 : 320,
                    child: song == null
                        ? const Text(
                            '未选择歌曲',
                            style: TextStyle(color: Color(0xFFCDB8C1)),
                          )
                        : Row(
                            children: [
                              DesktopAlbumArt(
                                song: song,
                                size: 50,
                                radius: 5,
                                onBytesLoaded: (bytes) => unawaited(
                                    ThemeService.updateFromCover(bytes)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _text,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      song.singer,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFCDB8C1),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: _isFavorite(song) ? '取消收藏' : '收藏',
                                onPressed: () =>
                                    unawaited(_toggleFavorite(song)),
                                icon: Icon(
                                  _isFavorite(song)
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: _isFavorite(song)
                                      ? _text
                                      : const Color(0xFFCDB8C1),
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                  ),
                  const Spacer(),
                  _TransportButton(
                    icon: Icons.skip_previous_rounded,
                    tooltip: '上一首',
                    onTap: _player.prev,
                  ),
                  const SizedBox(width: 10),
                  _TransportButton(
                    icon: _player.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip: _player.isPlaying ? '暂停' : '播放',
                    primary: true,
                    onTap: () => unawaited(_player.togglePlayPause()),
                  ),
                  const SizedBox(width: 10),
                  _TransportButton(
                    icon: Icons.skip_next_rounded,
                    tooltip: '下一首',
                    onTap: _player.next,
                  ),
                  const Spacer(),
                  SizedBox(
                    width: compact ? 220 : 320,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _formatTime(position),
                          style: const TextStyle(
                            color: Color(0xFFCDB8C1),
                            fontSize: 11,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 5),
                          child: Text(
                            '/',
                            style: TextStyle(color: Color(0xFF9D7788)),
                          ),
                        ),
                        Text(
                          _formatTime(duration),
                          style: const TextStyle(
                            color: Color(0xFFCDB8C1),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Tooltip(
                          message: '当前队列',
                          child: IconButton(
                            onPressed: () => setState(
                              () => _section = _DesktopSection.queue,
                            ),
                            icon: const Icon(
                              Icons.queue_music_rounded,
                              color: _text,
                              size: 21,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isFavorite(Song song) => _favorites
      .any((item) => item.id == song.id && item.source == song.source);

  int _activeLyricIndex(List<LyricLine> lines, int milliseconds) {
    if (lines.isEmpty) return -1;
    for (var index = lines.length - 1; index >= 0; index--) {
      if (milliseconds >= lines[index].startMs) return index;
    }
    return 0;
  }

  String _formatTime(Duration value) {
    final seconds = value.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: _DesktopMusicPageState._faint,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          SizedBox(width: 38, child: Text('#', style: style)),
          Expanded(flex: 5, child: Text('歌曲', style: style)),
          Expanded(flex: 3, child: Text('歌手', style: style)),
          Expanded(flex: 3, child: Text('专辑', style: style)),
          SizedBox(width: 64, child: Text('时长', style: style)),
          SizedBox(width: 96),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  final Song song;
  final int index;
  final bool active;
  final bool favorite;
  final bool removable;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback? onRemove;

  const _TrackRow({
    required this.song,
    required this.index,
    required this.active,
    required this.favorite,
    required this.removable,
    required this.onTap,
    required this.onFavorite,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final themeAccent =
        AppDesignTokens.readableAccent(ThemeService.bgHint.value);
    final titleColor = active ? themeAccent : _DesktopMusicPageState._text;
    return Material(
      color: active ? themeAccent.withValues(alpha: 0.11) : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        hoverColor: AppDesignTokens.readableAccent(ThemeService.bgHint.value)
            .withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                child: active
                    ? Icon(
                        Icons.graphic_eq_rounded,
                        color: themeAccent,
                        size: 17,
                      )
                    : Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: _DesktopMusicPageState._faint,
                          fontSize: 11,
                        ),
                      ),
              ),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    DesktopAlbumArt(song: song, size: 38, radius: 4),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  song.singer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _DesktopMusicPageState._muted,
                    fontSize: 12,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  song.album.isEmpty ? '—' : song.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _DesktopMusicPageState._muted,
                    fontSize: 12,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  _formatSeconds(song.duration),
                  style: const TextStyle(
                    color: _DesktopMusicPageState._muted,
                    fontSize: 11,
                  ),
                ),
              ),
              SizedBox(
                width: 96,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: favorite ? '取消收藏' : '收藏',
                      onPressed: onFavorite,
                      icon: Icon(
                        favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: favorite
                            ? themeAccent
                            : _DesktopMusicPageState._muted,
                        size: 18,
                      ),
                    ),
                    if (removable)
                      IconButton(
                        tooltip: '从队列移除',
                        onPressed: onRemove,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: _DesktopMusicPageState._muted,
                          size: 18,
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

  static String _formatSeconds(int value) {
    if (value <= 0) return '--:--';
    return '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
  }
}

class _Lyrics extends StatelessWidget {
  final List<LyricLine> lines;
  final int currentIndex;
  final int positionMs;
  final Color accent;

  const _Lyrics({
    required this.lines,
    required this.currentIndex,
    required this.positionMs,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(color: _DesktopMusicPageState._muted, fontSize: 16),
        ),
      );
    }
    final start = (currentIndex - 4).clamp(0, lines.length - 1);
    final end = (currentIndex + 6).clamp(0, lines.length - 1);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = start; index <= end; index++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: index == currentIndex
                ? _DesktopKaraokeText(
                    line: lines[index],
                    positionMs: positionMs,
                    lineEndMs: index + 1 < lines.length
                        ? lines[index + 1].startMs
                        : null,
                    activeColor: _DesktopMusicPageState._text,
                    inactiveColor: accent.withValues(alpha: 0.52),
                  )
                : Text(
                    lines[index].text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent.withValues(
                        alpha: index == currentIndex - 1 ||
                                index == currentIndex + 1
                            ? 0.72
                            : 0.4,
                      ),
                      fontSize: 18,
                      height: 1.22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
      ],
    );
  }
}

class _DesktopKaraokeText extends StatelessWidget {
  final LyricLine line;
  final int positionMs;
  final int? lineEndMs;
  final Color activeColor;
  final Color inactiveColor;

  const _DesktopKaraokeText({
    required this.line,
    required this.positionMs,
    required this.lineEndMs,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 25,
      height: 1.22,
      fontWeight: FontWeight.w800,
    );
    final progress = _progress();
    final text = line.text;
    final count = text.runes.length;
    if (count == 0) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 140),
      curve: Curves.linear,
      tween: Tween(end: progress),
      builder: (context, animatedProgress, _) {
        final highlighted = (count * animatedProgress).floor().clamp(0, count);
        var index = 0;
        return Text.rich(
          TextSpan(
            children: [
              for (final rune in text.runes)
                TextSpan(
                  text: String.fromCharCode(rune),
                  style: style.copyWith(
                    color: index++ < highlighted ? activeColor : inactiveColor,
                  ),
                ),
            ],
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  double _progress() {
    if (line.syllables.length > 1 || line.syllables.single.durationMs > 0) {
      return lyricProgressAt(line, positionMs);
    }
    final end = lineEndMs;
    if (end == null || end <= line.startMs) return 1;
    return ((positionMs - line.startMs) / (end - line.startMs))
        .clamp(0.0, 1.0)
        .toDouble();
  }
}

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _DesktopMusicPageState._faint, size: 44),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _DesktopMusicPageState._text,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _DesktopMusicPageState._muted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool primary;

  const _TransportButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppDesignTokens.readableAccent(ThemeService.bgHint.value);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: primary ? accent.withValues(alpha: 0.42) : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          hoverColor: accent.withValues(alpha: 0.30),
          child: SizedBox(
            width: primary ? 48 : 38,
            height: primary ? 48 : 38,
            child: Icon(
              icon,
              color: _DesktopMusicPageState._text,
              size: primary ? 27 : 22,
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopAlbumArt extends StatefulWidget {
  final Song song;
  final double size;
  final double radius;
  final ValueChanged<Uint8List>? onBytesLoaded;

  const DesktopAlbumArt({
    super.key,
    required this.song,
    required this.size,
    this.radius = 8,
    this.onBytesLoaded,
  });

  @override
  State<DesktopAlbumArt> createState() => _DesktopAlbumArtState();
}

class _DesktopAlbumArtState extends State<DesktopAlbumArt> {
  Uint8List? _bytes;
  String? _cacheKey;
  String? _coverSource;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DesktopAlbumArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    final song = widget.song;
    final key = song.picId.isNotEmpty ? song.picId : song.id;
    if (_cacheKey != key || _coverSource != song.cover) {
      _bytes = null;
      _cacheKey = null;
      _coverSource = null;
      _load();
    }
  }

  Future<void> _load() async {
    final key =
        widget.song.picId.isNotEmpty ? widget.song.picId : widget.song.id;
    final source = widget.song.cover;
    _cacheKey = key;
    _coverSource = source;
    final bytes = await CoverCacheService().resolve(key, source);
    if (mounted &&
        _cacheKey == key &&
        _coverSource == source &&
        bytes != null) {
      setState(() => _bytes = bytes);
      widget.onBytesLoaded?.call(bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Container(
        width: widget.size,
        height: widget.size,
        color: const Color(0xFF292B2F),
        child: _bytes != null
            ? Image.memory(_bytes!, fit: BoxFit.cover)
            : const Center(
                child: Icon(
                  Icons.music_note_rounded,
                  color: _DesktopMusicPageState._faint,
                  size: 30,
                ),
              ),
      ),
    );
  }
}
