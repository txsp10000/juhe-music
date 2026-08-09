import 'package:flutter/material.dart';

import '../../api/music_api.dart';
import '../../models/song.dart';
import '../../services/favorites_service.dart';
import '../../services/player_service.dart';
import '../tv_layout_metrics.dart';
import '../tv_routes.dart';
import '../tv_tokens.dart';
import '../widgets/tv_page_scaffold.dart';
import '../widgets/tv_pill_button.dart';
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
    final song = _favorites[index];
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final metrics = TvLayoutMetrics.of(dialogContext);
        return AlertDialog(
          backgroundColor: TvTokens.panel,
          title: Text('移除收藏', style: TvTokens.title(size: metrics.font(32))),
          content: Text(
            '确定从收藏中移除“${song.name}”吗？',
            style: TvTokens.body(size: metrics.font(22)),
          ),
          actions: [
            TvPillButton(
              label: '取消',
              autofocus: true,
              onTap: () => Navigator.of(dialogContext).pop(false),
            ),
            TvPillButton(
              label: '确认移除',
              icon: Icons.delete_outline_rounded,
              onTap: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await FavoritesService.remove(song);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已移除 ${song.name}')),
        );
      }
    }
  }

  Future<void> _playAt(int index) async {
    final songs = List<Song>.of(_favorites);
    var selected = songs[index];
    // Favorites created before cover hydration may only contain song metadata.
    // Resolve the cover before returning to the player so the TV art is ready.
    if (selected.cover.isEmpty || selected.picId.isEmpty) {
      try {
        final details = await MusicApi.getTrackDetails(
            selected.lyricId.isNotEmpty ? selected.lyricId : selected.id);
        if (details.song.cover.isNotEmpty || details.song.picId.isNotEmpty) {
          details.song.lyric = selected.lyric;
          if (details.song.cover.isEmpty) details.song.cover = selected.cover;
          songs[index] = details.song;
          selected = details.song;
        }
      } catch (_) {}
    }
    _player.replaceQueue(
      songs,
      source: PlaybackQueueSource.favorites,
    );
    await _player.playAt(index);
    if (!mounted) return;
    TvRoutes.returnHome(context, openQueue: true);
  }

  @override
  Widget build(BuildContext context) {
    return TvPageScaffold(
      child: TvSongList(
        title: '我的收藏',
        subtitle: '${_favorites.length} 首歌曲 · 长按确认键可移除收藏',
        songs: _favorites,
        emptyText: '还没有收藏歌曲。播放时按收藏按钮即可加入这里。',
        onPlay: _playAt,
        onLongPress: _removeAt,
        autofocusFirstItem: true,
      ),
    );
  }
}
