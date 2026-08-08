import 'package:flutter/material.dart';

import '../../api/music_api.dart';
import '../../models/song.dart';
import '../../services/player_service.dart';
import '../tv_layout_metrics.dart';
import '../tv_routes.dart';
import '../tv_tokens.dart';
import '../widgets/tv_focus_card.dart';
import '../widgets/tv_load_state.dart';
import '../widgets/tv_page_scaffold.dart';
import '../widgets/tv_pill_button.dart';
import '../widgets/tv_song_list.dart';
import 'tv_playlist_detail_page.dart';

enum _SearchType { tracks, playlists }

class TvSearchResultsPage extends StatefulWidget {
  final String keyword;
  const TvSearchResultsPage({super.key, required this.keyword});

  @override
  State<TvSearchResultsPage> createState() => _TvSearchResultsPageState();
}

class _TvSearchResultsPageState extends State<TvSearchResultsPage> {
  final _player = PlayerService();
  List<Song> _songs = const [];
  List<PlaylistInfo> _playlists = const [];
  _SearchType _type = _SearchType.tracks;
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
      final results = await Future.wait([
        MusicApi.searchTracks(widget.keyword),
        MusicApi.searchPlaylists(widget.keyword)
      ]);
      if (!mounted) return;
      setState(() {
        _songs = (results[0] as SearchTracksResult).songs;
        _playlists = (results[1] as SearchPlaylistsResult).playlists;
      });
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
        Text(widget.keyword,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TvTokens.hero(size: metrics.font(48))),
        SizedBox(height: metrics.value(16, minimum: 10)),
        Row(children: [
          TvPillButton(
              label: '歌曲 ${_songs.length}',
              icon: Icons.music_note_rounded,
              selected: _type == _SearchType.tracks,
              autofocus: true,
              onTap: () => setState(() => _type = _SearchType.tracks)),
          SizedBox(width: metrics.value(14, minimum: 8)),
          TvPillButton(
              label: '歌单 ${_playlists.length}',
              icon: Icons.queue_music_rounded,
              selected: _type == _SearchType.playlists,
              onTap: () => setState(() => _type = _SearchType.playlists)),
        ]),
        SizedBox(height: metrics.sectionGap),
        Expanded(child: _body(metrics)),
      ]),
    );
  }

  Widget _body(TvLayoutMetrics metrics) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: TvTokens.focus));
    }
    if (_error != null) {
      return TvLoadState(
          icon: Icons.wifi_off_rounded,
          title: '搜索失败',
          message: _error!,
          actionLabel: '重新搜索',
          onAction: _load);
    }
    if (_type == _SearchType.tracks) {
      return TvSongList(
          songs: _songs, emptyText: '没有找到相关歌曲。', onPlay: _playAt, dense: true);
    }
    if (_playlists.isEmpty) {
      return const TvLoadState(
          icon: Icons.search_off_rounded,
          title: '没有找到相关歌单',
          message: '换个关键词试试。');
    }
    return GridView.builder(
      itemCount: _playlists.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: metrics.gridColumnCount(metrics.size.width),
          crossAxisSpacing: metrics.value(18, minimum: 10),
          mainAxisSpacing: metrics.value(18, minimum: 10),
          childAspectRatio: 2.15),
      itemBuilder: (_, index) {
        final playlist = _playlists[index];
        return TvFocusCard(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TvPlaylistDetailPage(playlist: playlist))),
          padding: EdgeInsets.all(metrics.value(16, minimum: 10)),
          color: Colors.black.withValues(alpha: 0.16),
          child: Row(children: [
            AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: playlist.coverUrl.isEmpty
                        ? const Icon(Icons.queue_music_rounded,
                            color: TvTokens.focus)
                        : Image.network(playlist.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.queue_music_rounded,
                                color: TvTokens.focus)))),
            SizedBox(width: metrics.value(14, minimum: 8)),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(playlist.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.title(size: metrics.font(22))),
                  SizedBox(height: metrics.value(8, minimum: 4)),
                  Text('${playlist.trackCount} 首',
                      style: TvTokens.body(
                          size: metrics.font(17), color: TvTokens.muted)),
                ])),
          ]),
        );
      },
    );
  }
}
