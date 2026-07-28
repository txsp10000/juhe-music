import 'package:flutter/material.dart';
import '../services/player_service.dart';
import '../models/song.dart';
import '../widgets/swipe_action_cell.dart';
import 'player_page.dart';

class PlaylistPage extends StatefulWidget {
  final bool fromPlayer;
  const PlaylistPage({super.key, this.fromPlayer = false});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  final _player = PlayerService();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _player.addSongChangeListener(_onSongChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPlaying());
  }

  void _scrollToPlaying() {
    final idx = _player.currentIndex;
    if (idx > 0 && _scrollController.hasClients) {
      final offset = (idx * 62.0).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(offset, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _onSongChange(Song _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _player.removeSongChangeListener(_onSongChange);
    super.dispose();
  }

  void _playAt(int index) {
    if (_player.currentSong?.id == _player.playlist[index].id) {
      if (widget.fromPlayer) {
        Navigator.pop(context);
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
      }
      return;
    }
    _player.playAt(index);
    if (widget.fromPlayer) {
      Navigator.pop(context);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
    }
  }


  @override
  Widget build(BuildContext context) {
    final songs = _player.playlist;
    final currentIdx = _player.currentIndex;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF171B26),
        title: Text('播放列表 (${songs.length}首)',
            style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: songs.isEmpty
          ? const Center(child: Text('暂无歌曲', style: TextStyle(color: Color(0xFF8F919A), fontSize: 18)))
          : ListView.builder(
              controller: _scrollController,
              itemCount: songs.length,
              itemBuilder: (_, i) {
                final s = songs[i];
                final isCurrent = i == currentIdx;
                return SwipeActionCell(
                  actionLabel: '删除',
                  actionColor: Colors.red,
                  onAction: () {
                    setState(() => _player.playlist.removeAt(i));
                  },
                  child: InkWell(
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
                                    style: const TextStyle(color: Color(0xFF8F919A), fontSize: 16)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name,
                                    style: TextStyle(
                                        color: isCurrent ? const Color(0xFF6890F9) : Colors.white,
                                        fontSize: 18)),
                                Text(s.singer,
                                    style: const TextStyle(color: Color(0xFF8F919A), fontSize: 15)),
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
    );
  }
}


