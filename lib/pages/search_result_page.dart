import 'package:flutter/material.dart';
import '../api/music_api.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import '../services/favorites_service.dart';
import '../utils/toast.dart';
import '../widgets/swipe_action_cell.dart';
import 'player_page.dart';

class SearchResultPage extends StatefulWidget {
  final String keyword;
  const SearchResultPage({super.key, required this.keyword});

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  final _player = PlayerService();
  bool _loading = true;
  List<Song> _songs = [];
  String _errorMsg = '';
  final Set<String> _favoritedIds = {};

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    try {
      final result = await MusicApi.searchRaw(widget.keyword);
      if (!mounted) return;
      if (result.songs.isNotEmpty) {
        // 后台加载封面
        final picIds =
            result.songs.map((s) => s.picId.isNotEmpty ? s.picId : s.id).toList();
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
          _songs = result.songs;
          _loading = false;
        });
        _checkFavoriteStates();
      } else {
        setState(() {
          _loading = false;
          _errorMsg = '重试30次后仍无结果\nAPI返回:\n${result.rawBody.isEmpty ? "空列表" : result.rawBody.substring(0, result.rawBody.length > 200 ? 200 : result.rawBody.length)}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = '搜索失败: $e';
      });
    }
  }

  void _playAt(int index) {
    _player.playlist.clear();
    _player.playlist.addAll(_songs);
    _player.playAt(index);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
  }

  Future<void> _favoriteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('确认收藏全部 ${_songs.length} 首歌曲？',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认',
                  style: TextStyle(color: Color(0xFF6890F9)))),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final s in _songs) {
      await FavoritesService.save(s);
    }
    if (mounted) {
      _checkFavoriteStates();
      Toast.show(context, '已收藏全部 ${_songs.length} 首');
    }
  }

  Future<void> _checkFavoriteStates() async {
    _favoritedIds.clear();
    for (final s in _songs) {
      if (await FavoritesService.isFavorite(s)) {
        _favoritedIds.add(s.id);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _favoriteSong(Song song) async {
    if (_favoritedIds.contains(song.id)) {
      await FavoritesService.remove(song);
      _favoritedIds.remove(song.id);
      if (mounted) {
        setState(() {});
        Toast.show(context, '已取消收藏: ${song.name}');
      }
    } else {
      await FavoritesService.save(song);
      _favoritedIds.add(song.id);
      if (mounted) {
        setState(() {});
        Toast.show(context, '已收藏: ${song.name}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF171B26),
        title: Text(
          _loading ? '搜索中...' : '搜索结果 · 网易云音乐',
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_songs.isNotEmpty)
            TextButton.icon(
              onPressed: _favoriteAll,
              icon: const Icon(Icons.favorite, color: Colors.red, size: 20),
              label: const Text('全部收藏',
                  style: TextStyle(color: Colors.red, fontSize: 13)),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF6890F9)))
            : _songs.isEmpty
                ? Center(
                    child: Text(_errorMsg.isNotEmpty ? _errorMsg : '无搜索结果',
                        style: const TextStyle(
                            color: Color(0xFF8F919A), fontSize: 16),
                        textAlign: TextAlign.center))
                : ListView.builder(
                    itemCount: _songs.length,
                    itemBuilder: (_, i) {
                      final s = _songs[i];
                      final isFav = _favoritedIds.contains(s.id);
                      return SwipeActionCell(
                        key: ValueKey('${s.id}_$isFav'),
                        actionLabel: isFav ? '取消收藏' : '收藏',
                        actionColor:
                            isFav ? Colors.red : const Color(0xFF6890F9),
                        onAction: () => _favoriteSong(s),
                        child: InkWell(
                          onTap: () => _playAt(i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            decoration: const BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: Color(0x15FFFFFF))),
                            ),
                            child: Row(
                              children: [
                                Text('${i + 1}',
                                    style: const TextStyle(
                                        color: Color(0xFF8F919A),
                                        fontSize: 14)),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(s.name,
                                          style: const TextStyle(
                                              color: Color(0xFFE0E0E0),
                                              fontSize: 16),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      Text(s.singer,
                                          style: const TextStyle(
                                              color: Color(0xFF8F919A),
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
