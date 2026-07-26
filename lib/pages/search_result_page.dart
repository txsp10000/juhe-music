import 'package:flutter/material.dart';
import '../api/music_api.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import '../services/favorites_service.dart';
import '../utils/toast.dart';
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
    _player.addSongChangeListener(_onSongChange);
  }


  void _onSongChange(Song _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player.removeSongChangeListener(_onSongChange);
    super.dispose();
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
    // 过滤掉已收藏的
    final notFav = _songs.where((s) => !_favoritedIds.contains(s.id)).toList();
    if (notFav.isEmpty) {
      if (mounted) Toast.show(context, '全部歌曲已收藏');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('确认收藏 ${notFav.length} 首歌曲？（共${_songs.length}首，已收藏${_songs.length - notFav.length}首）',
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
    for (final s in notFav) {
      await FavoritesService.save(s);
    }
    if (mounted) {
      _checkFavoriteStates();
      Toast.show(context, '已收藏 ${notFav.length} 首');
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
                      final isCurrent = _player.currentSong?.id == s.id;
                      return InkWell(
                        onTap: () => _playAt(i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: isCurrent ? const Color(0x1A6890F9) : Colors.transparent,
                            border: isCurrent
                                ? const Border(bottom: BorderSide(color: Color(0xFF6890F9), width: 2))
                                : const Border(bottom: BorderSide(color: Color(0x15FFFFFF))),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                child: isCurrent
                                    ? const Icon(Icons.volume_up, color: Color(0xFF6890F9), size: 22)
                                    : Text('${i + 1}', textAlign: TextAlign.center,
                                        style: const TextStyle(color: Color(0xFF8F919A), fontSize: 14)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.name,
                                        style: TextStyle(
                                            color: isCurrent ? const Color(0xFF6890F9) : Colors.white,
                                            fontSize: 16),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    Text(s.singer,
                                        style: const TextStyle(color: Color(0xFF8F919A), fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}