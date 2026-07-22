import 'package:flutter/material.dart';
import '../api/music_api.dart';
import '../models/song.dart';
import '../models/platform.dart';
import '../models/search_result.dart';
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
  bool _allFavorited = false;
  List<PlatformResult> _results = [];
  List<Song> _songs = [];
  String _selectedPlatform = '';
  final Set<String> _favoritedIds = {};

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    final platforms = Platform.searchablePlatforms;
    final futures = platforms.map((p) async {
      try {
        final r = await MusicApi.searchByPlatform(p, widget.keyword);
        return PlatformResult(platform: p, songs: r.list, total: r.total);
      } catch (e) {
        return PlatformResult(platform: p, songs: [], total: 0, error: e.toString());
      }
    });
    final all = await Future.wait(futures);
    final valid = all.where((r) => r.songs.isNotEmpty).toList();
    if (!mounted) return;
    setState(() { _results = valid; _loading = false; });
    if (valid.isNotEmpty) {
      _showPlatformPicker();
    }
  }

  void _showPlatformPicker() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('选择音源 — "${widget.keyword}"',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _results.map((r) {
            final label = '${r.platform.displayName} (${r.songs.length}首)';
            return ListTile(
              title: Text(label, style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() { _songs = r.songs; _selectedPlatform = r.platform.displayName; });
                _checkFavoriteStates();
              },
            );
          }).toList(),
        ),
      ),
    ).then((value) {
      if (value == null && _songs.isEmpty && mounted) {
        Navigator.pop(context);
      }
    });
  }

  void _playAt(int index) {
    _player.playlist.clear();
    _player.playlist.addAll(_songs);
    _player.playAt(index);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
  }

  String _platformName(String code) {
    final p = Platform.fromCode(code);
    return p?.displayName ?? code;
  }

  Future<void> _favoriteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('确认收藏全部 ${_songs.length} 首歌曲？', style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认', style: TextStyle(color: Color(0xFF6890F9)))),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final s in _songs) {
      await FavoritesService.save(s);
    }
    if (mounted) {
      setState(() => _allFavorited = true);
      Toast.show(context, '已收藏全部 ${_songs.length} 首');
      _checkFavoriteStates();
    }
  }

  Future<void> _unfavoriteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('确认取消收藏全部 ${_songs.length} 首？', style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    await FavoritesService.removeAll(_songs);
    if (mounted) {
      setState(() => _allFavorited = false);
      Toast.show(context, '已取消收藏');
    }
  }

  Future<void> _checkFavoriteStates() async {
    _favoritedIds.clear();
    for (final s in _songs) {
      if (await FavoritesService.isFavorite(s)) {
        _favoritedIds.add('${s.id}_${s.source}');
      }
    }
    if (mounted) setState(() {});
  }

  String _songKey(Song s) => '${s.id}_${s.source}';

  Future<void> _favoriteSong(Song song) async {
    final key = _songKey(song);
    if (_favoritedIds.contains(key)) {
      await FavoritesService.remove(song);
      _favoritedIds.remove(key);
      if (mounted) {
        setState(() {});
        Toast.show(context, '已取消收藏: ${song.name}');
      }
    } else {
      await FavoritesService.save(song);
      _favoritedIds.add(key);
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
          _selectedPlatform.isNotEmpty
              ? '搜索结果 · $_selectedPlatform'
              : '搜索中...',
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
              label: const Text('全部收藏', style: TextStyle(color: Colors.red, fontSize: 13)),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF6890F9)))
            : _songs.isEmpty
                ? const Center(child: Text('所有平台均无搜索结果',
                    style: TextStyle(color: Color(0xFF8F919A), fontSize: 16)))
                : ListView.builder(
                    itemCount: _songs.length,
                    itemBuilder: (_, i) {
                      final s = _songs[i];
                      final isFav = _favoritedIds.contains(_songKey(s));
                      return SwipeActionCell(
                        key: ValueKey('${s.id}_${s.source}_$isFav'),
                        actionLabel: isFav ? '取消收藏' : '收藏',
                        actionColor: isFav ? Colors.red : const Color(0xFF6890F9),
                        onAction: () => _favoriteSong(s),
                        child: InkWell(
                          onTap: () => _playAt(i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0x15FFFFFF))),
                            ),
                            child: Row(
                              children: [
                                Text('${i + 1}', style: const TextStyle(color: Color(0xFF8F919A), fontSize: 14)),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.name, style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text(s.singer, style: const TextStyle(color: Color(0xFF8F919A), fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0x226890F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(_platformName(s.source),
                                      style: const TextStyle(color: Color(0xFF6890F9), fontSize: 11)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
  }
}
