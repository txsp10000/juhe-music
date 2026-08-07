import 'package:flutter/material.dart';

import '../../api/music_api.dart';
import '../../data/categories.dart';
import '../../models/song.dart';
import '../../services/player_service.dart';
import '../tv_layout_metrics.dart';
import '../tv_routes.dart';
import '../tv_tokens.dart';
import '../widgets/tv_page_scaffold.dart';
import '../widgets/tv_song_list.dart';

class TvPlaylistDetailPage extends StatefulWidget {
  final PlaylistInfo playlist;

  const TvPlaylistDetailPage({super.key, required this.playlist});

  @override
  State<TvPlaylistDetailPage> createState() => _TvPlaylistDetailPageState();
}

class _TvPlaylistDetailPageState extends State<TvPlaylistDetailPage> {
  final _player = PlayerService();
  List<Song> _songs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
  }

  Future<void> _loadPlaylist() async {
    try {
      final songs = await MusicApi.getPlaylist(widget.playlist.id);
      if (!mounted) return;
      setState(() => _songs = songs);
    } catch (_) {
      if (mounted) setState(() => _songs = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playAt(int index) async {
    if (_songs.isEmpty) return;
    _player.playlist
      ..clear()
      ..addAll(_songs);
    await _player.playAt(index);
    if (!mounted) return;
    TvRoutes.requestHomeQueueFocus();
    Navigator.of(context).pushReplacementNamed(TvRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    return TvPageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '歌单 / ${widget.playlist.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.body(
                      size: metrics.font(22), color: TvTokens.muted),
                ),
              ),
              SizedBox(width: metrics.value(18, minimum: 8)),
              Text(
                '${_songs.length} 首歌曲',
                style: TvTokens.body(
                    size: metrics.font(22), color: TvTokens.muted),
              ),
            ],
          ),
          SizedBox(height: metrics.sectionGap),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: TvTokens.focus))
                : TvSongList(
                    songs: _songs,
                    emptyText: '暂时无法加载此歌单。',
                    onPlay: _playAt,
                    dense: true,
                  ),
          ),
        ],
      ),
    );
  }
}
