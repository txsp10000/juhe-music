import 'package:flutter/material.dart';
import '../api/music_api.dart';
import '../models/song.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/glass_panel.dart';
import '../widgets/music_list_tile.dart';
import 'player_page.dart';

class SearchResultPage extends StatefulWidget {
  final String keyword;
  final bool fromPlayer;
  const SearchResultPage({super.key, required this.keyword, this.fromPlayer = false});

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  final _player = PlayerService();
  bool _loading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  List<Song> _songs = [];
  final Set<String> _favoriteIds = {};
  String _errorMsg = '';
  Color _accent = AppDesignTokens.lyricWhite;
  Color _bgHint = AppDesignTokens.inkBlack;

  @override
  void initState() {
    super.initState();
    _initialLoad();
    _loadFavorites();
    _onThemeChange();
    ThemeService.accentColor.addListener(_onThemeChange);
    ThemeService.bgHint.addListener(_onThemeChange);
  }

  void _onThemeChange() {
    if (mounted) {
      setState(() {
        _accent = AppDesignTokens.readableAccent(ThemeService.accentColor.value);
        _bgHint = ThemeService.bgHint.value;
      });
    }
  }

  @override
  void dispose() {
    ThemeService.accentColor.removeListener(_onThemeChange);
    ThemeService.bgHint.removeListener(_onThemeChange);
    super.dispose();
  }

  Future<void> _initialLoad() async {
    await _search();
    if (_hasMore && mounted) {
      _currentPage++;
      await _search(append: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadFavorites() async {
    final favorites = await FavoritesService.load();
    _favoriteIds
      ..clear()
      ..addAll(favorites.map((s) => s.id));
    if (mounted) setState(() {});
  }

  Future<void> _search({bool append = false}) async {
    try {
      final result = await MusicApi.searchRaw(widget.keyword, num: 20, page: _currentPage);
      if (!mounted) return;
      if (result.songs.isNotEmpty) {
        final picIds = result.songs.map((s) => s.picId.isNotEmpty ? s.picId : s.id).toList();
        MusicApi.getCovers(picIds).then((covers) {
          if (!mounted) return;
          for (final s in result.songs) {
            final key = s.picId.isNotEmpty ? s.picId : s.id;
            final cover = covers[key];
            if (cover != null && cover.isNotEmpty) s.cover = cover;
          }
          setState(() {});
        });
        setState(() {
          if (append) {
            _songs.addAll(result.songs);
          } else {
            _songs = result.songs;
          }
          _hasMore = result.songs.length >= 20;
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          if (!append) _errorMsg = '未找到结果';
          _hasMore = false;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasMore = false;
        _isLoadingMore = false;
        if (!append) _errorMsg = '搜索失败';
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (!_hasMore || _isLoadingMore) return;
    _currentPage++;
    setState(() => _isLoadingMore = true);
    await _search(append: true);
  }

  void _playAt(int index) {
    if (_player.currentSong?.id == _songs[index].id) {
      if (widget.fromPlayer) {
        Navigator.pop(context);
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
      }
      return;
    }
    _player.playlist.clear();
    _player.playlist.addAll(_songs);
    _player.playAt(index);
    if (widget.fromPlayer) {
      Navigator.pop(context);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
    }
  }

  Future<void> _toggleFavorite(Song song) async {
    if (_favoriteIds.contains(song.id)) {
      await FavoritesService.remove(song);
      _favoriteIds.remove(song.id);
    } else {
      await FavoritesService.save(song);
      _favoriteIds.add(song.id);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoadingMore,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: MusicScaffoldBackground(
          bgHint: _bgHint,
          accent: _accent,
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      child: Row(
        children: [
          IconOrbButton(icon: Icons.arrow_back_rounded, accent: _accent, size: 42, onTap: _isLoadingMore ? null : () => Navigator.pop(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_loading ? '搜索中' : widget.keyword, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppDesignTokens.title(size: 22)),
                const SizedBox(height: 4),
                Text(_loading ? '正在翻找音乐房间' : '共 ${_songs.length} 首歌', style: AppDesignTokens.caption(color: _accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return MusicEmptyState(accent: _accent, icon: Icons.graphic_eq_rounded, title: '正在搜索', message: '把相关歌曲从云端唱片箱里找出来。');
    }
    if (_songs.isEmpty && !_isLoadingMore) {
      return MusicEmptyState(
        accent: _accent,
        icon: _errorMsg == '搜索失败' ? Icons.wifi_off_rounded : Icons.search_off_rounded,
        title: _errorMsg.isNotEmpty ? _errorMsg : '没有找到相关歌曲',
        message: _errorMsg == '搜索失败' ? '网络或接口暂时没有回应，稍后再试。' : '换个歌名或歌手试试。',
      );
    }
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollEndNotification &&
                notification.metrics.pixels >= notification.metrics.maxScrollExtent - 100 &&
                !_isLoadingMore &&
                _hasMore) {
              _loadNextPage();
            }
            return false;
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
            itemCount: _songs.length + (_hasMore ? 1 : 0),
            itemBuilder: (_, i) {
              if (i >= _songs.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2.4)),
                );
              }
              final s = _songs[i];
              final isCurrent = _player.currentSong?.id == s.id;
              final favored = _favoriteIds.contains(s.id);
              return MusicListTile(
                song: s,
                index: i,
                isCurrent: isCurrent,
                accent: _accent,
                onTap: () => _playAt(i),
                trailing: GestureDetector(
                  onTap: () => _toggleFavorite(s),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(favored ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: favored ? AppDesignTokens.danger : AppDesignTokens.quietGrey, size: 23),
                  ),
                ),
              );
            },
          ),
        ),
        if (_isLoadingMore)
          Positioned.fill(
            child: Container(
              color: AppDesignTokens.inkBlack.withOpacity(0.42),
              child: Center(
                child: GlassPanel(
                  accent: _accent,
                  radius: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: _accent, strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Text('加载更多', style: AppDesignTokens.body(size: 14, color: AppDesignTokens.quietGrey)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
