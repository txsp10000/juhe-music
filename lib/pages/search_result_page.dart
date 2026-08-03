import 'package:flutter/material.dart';
import '../api/music_api.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import '../services/favorites_service.dart';
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

  // ─── Design tokens ───
  static const _bg = Color(0xFF000000);
  static const _surface = Color(0xFF1A1A1A);
  static const _accent = Color(0xFFFFFFFF);
  static const _textPrimary = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF999999);
  static const _textTertiary = Color(0xFF666666);

  @override
  void initState() {
    super.initState();
    _initialLoad();
    _loadFavorites();
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
    _favoriteIds.clear();
    for (final s in favorites) {
      _favoriteIds.add(s.id);
    }
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
    } catch (e) {
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
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          title: Text(
            _loading ? '搜索中...' : widget.keyword,
            style: const TextStyle(color: _textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          leading: _isLoadingMore
              ? const SizedBox()
              : IconButton(
                  icon: const Icon(Icons.arrow_back, color: _textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: [
              if (_loading)
                const Center(child: CircularProgressIndicator(color: _accent))
              else if (_songs.isEmpty && !_isLoadingMore)
                Center(
                    child: Text(_errorMsg.isNotEmpty ? _errorMsg : '无搜索结果',
                        style: const TextStyle(color: _textSecondary, fontSize: 15)))
              else
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollEndNotification &&
                        notification.metrics.pixels >= notification.metrics.maxScrollExtent - 100 &&
                        !_isLoadingMore && _hasMore) {
                      _loadNextPage();
                    }
                    return false;
                  },
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        color: _accent.withOpacity(0.08),
                        child: Text(
                          '共 ${_songs.length} 首歌',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _accent, fontSize: 13),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _songs.length,
                          itemBuilder: (_, i) {
                      final s = _songs[i];
                      final isCurrent = _player.currentSong?.id == s.id;
                      return InkWell(
                        onTap: () => _playAt(i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: isCurrent ? _accent.withOpacity(0.08) : Colors.transparent,
                            border: const Border(bottom: BorderSide(color: Color(0x08FFFFFF))),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 26,
                                child: isCurrent
                                    ? const Icon(Icons.volume_up, color: _accent, size: 18)
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
                                            color: isCurrent ? _accent : _textPrimary,
                                            fontSize: 15),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 3),
                                    Text(s.singer,
                                        style: const TextStyle(color: _textSecondary, fontSize: 12)),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _toggleFavorite(s),
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  child: Icon(
                                    _favoriteIds.contains(s.id)
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 22,
                                    color: _favoriteIds.contains(s.id)
                                        ? Colors.red
                                        : Colors.white,
                                  ),
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
              ),
              if (_isLoadingMore)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: _accent),
                        SizedBox(height: 16),
                        Text('加载中...', style: TextStyle(color: Colors.white, fontSize: 15)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
