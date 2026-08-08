import 'package:flutter/material.dart';

import '../../services/player_service.dart';
import '../tv_routes.dart';
import '../widgets/tv_page_scaffold.dart';
import '../widgets/tv_song_list.dart';

class TvQueuePage extends StatefulWidget {
  const TvQueuePage({super.key});

  @override
  State<TvQueuePage> createState() => _TvQueuePageState();
}

class _TvQueuePageState extends State<TvQueuePage> {
  final _player = PlayerService();

  @override
  void initState() {
    super.initState();
    _player.addSongChangeListener(_onChanged);
  }

  @override
  void dispose() {
    _player.removeSongChangeListener(_onChanged);
    super.dispose();
  }

  void _onChanged(dynamic _) {
    if (mounted) setState(() {});
  }

  Future<void> _playAt(int index) async {
    await _player.playAt(index);
    if (!mounted) return;
    TvRoutes.returnHome(context);
  }

  @override
  Widget build(BuildContext context) {
    return TvPageScaffold(
      child: TvSongList(
        title: '播放队列',
        subtitle: '${_player.queue.length} 首歌曲',
        songs: _player.queue,
        emptyText: '还没有播放队列，先去场景或搜索选择歌曲。',
        onPlay: _playAt,
      ),
    );
  }
}
