import 'package:flutter/material.dart';

import '../../api/music_api.dart';
import '../../models/song.dart';
import '../../services/player_service.dart';
import '../tv_layout_metrics.dart';
import '../tv_routes.dart';
import '../tv_tokens.dart';
import '../widgets/tv_load_state.dart';
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
  List<Song> _songs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final songs = await MusicApi.getPlaylistTracks(widget.playlist.id);
      if (mounted) setState(() => _songs = songs);
    } catch (_) {
      if (mounted) setState(() => _error = '网络或接口暂时没有回应。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playAt(int index) async {
    _player.replaceQueue(_songs);
    await _player.playAt(index);
    if (mounted) TvRoutes.returnHome(context);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    return TvPageScaffold(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.playlist.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TvTokens.hero(size: metrics.font(44))),
        SizedBox(height: metrics.value(10, minimum: 6)),
        Text(
            '${widget.playlist.trackCount} 首歌曲${widget.playlist.owner.isEmpty ? '' : ' · ${widget.playlist.owner}'}',
            style:
                TvTokens.body(size: metrics.font(20), color: TvTokens.muted)),
        SizedBox(height: metrics.sectionGap),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: TvTokens.focus));
    }
    if (_error != null) {
      return TvLoadState(
          icon: Icons.wifi_off_rounded,
          title: '歌单加载失败',
          message: _error!,
          actionLabel: '重新加载',
          onAction: _load);
    }
    return TvSongList(
        songs: _songs, emptyText: '这个歌单暂时没有歌曲。', onPlay: _playAt, dense: true);
  }
}
