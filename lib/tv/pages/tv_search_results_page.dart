import 'package:flutter/material.dart';

import '../../api/music_api.dart';
import '../../models/song.dart';
import '../../services/player_service.dart';
import '../tv_layout_metrics.dart';
import '../tv_routes.dart';
import '../tv_tokens.dart';
import '../widgets/tv_page_scaffold.dart';
import '../widgets/tv_song_list.dart';

class TvSearchResultsPage extends StatefulWidget {
  final String keyword;

  const TvSearchResultsPage({super.key, required this.keyword});

  @override
  State<TvSearchResultsPage> createState() => _TvSearchResultsPageState();
}

class _TvSearchResultsPageState extends State<TvSearchResultsPage> {
  final _player = PlayerService();
  List<Song> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    try {
      final result = await MusicApi.searchRaw(widget.keyword, num: 30);
      if (!mounted) return;
      setState(() => _results = result.songs);
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playAt(int index) async {
    if (_results.isEmpty) return;
    _player.playlist
      ..clear()
      ..addAll(_results);
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
          Text(
            widget.keyword,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TvTokens.hero(size: metrics.font(48)),
          ),
          SizedBox(height: metrics.sectionGap),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: TvTokens.focus))
                : TvSongList(
                    songs: _results,
                    emptyText: '没有找到相关歌曲。',
                    onPlay: _playAt,
                    dense: true,
                  ),
          ),
        ],
      ),
    );
  }
}
