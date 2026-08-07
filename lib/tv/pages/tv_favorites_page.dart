import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../../services/favorites_service.dart';
import '../../services/player_service.dart';
import '../tv_routes.dart';
import '../widgets/tv_page_scaffold.dart';
import '../widgets/tv_song_list.dart';

class TvFavoritesPage extends StatefulWidget {
  const TvFavoritesPage({super.key});

  @override
  State<TvFavoritesPage> createState() => _TvFavoritesPageState();
}

class _TvFavoritesPageState extends State<TvFavoritesPage> {
  final _player = PlayerService();
  List<Song> _favorites = [];

  @override
  void initState() {
    super.initState();
    FavoritesService.version.addListener(_loadFavorites);
    _loadFavorites();
  }

  @override
  void dispose() {
    FavoritesService.version.removeListener(_loadFavorites);
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final songs = await FavoritesService.load();
    if (mounted) setState(() => _favorites = songs);
  }

  Future<void> _removeAt(int index) async {
    if (index < 0 || index >= _favorites.length) return;
    await FavoritesService.remove(_favorites[index]);
  }

  Future<void> _playAt(int index) async {
    _player.playlist
      ..clear()
      ..addAll(_favorites);
    await _player.playAt(index);
    if (!mounted) return;
    TvRoutes.requestHomeQueueFocus();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(TvRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TvPageScaffold(
      child: TvSongList(
        title: '我的收藏',
        subtitle: '${_favorites.length} 首歌曲',
        songs: _favorites,
        emptyText: '还没有收藏歌曲。播放时按收藏按钮即可加入这里。',
        onPlay: _playAt,
        onLongPress: _removeAt,
        autofocusFirstItem: false,
      ),
    );
  }
}
