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

  // ─── Design tokens ───
  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFFFFFFFF);
  static const _textPrimary = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF999999);
  static const _textTertiary = Color(0xFF666666);

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
      _scrollController.animateTo(offset,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text('播放列表 (${songs.length})',
            style: const TextStyle(color: _textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: songs.isEmpty
          ? const Center(
              child: Text('暂无歌曲', style: TextStyle(color: _textSecondary, fontSize: 15)))
          : ListView.builder(
              controller: _scrollController,
              itemCount: songs.length,
              itemBuilder: (_, i) {
                final s = songs[i];
                final isCurrent = i == currentIdx;
                return SwipeActionCell(
                  actionLabel: '删除',
                  actionColor: const Color(0xFFFF5E5E),
                  onAction: () {
                    _player.removeAt(i).then((_) {
                      if (mounted) setState(() {});
                    });
                  },
                  child: InkWell(
                    onTap: () => _playAt(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: isCurrent ? _accent.withOpacity(0.08) : Colors.transparent,
                        border: const Border(bottom: BorderSide(color: Color(0x08FFFFFF))),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 26,
                            child: isCurrent
                                ? const Icon(Icons.volume_up, color: _accent, size: 18)
                                : Text('${i + 1}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: _textTertiary, fontSize: 13)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name,
                                    style: TextStyle(
                                        color: isCurrent ? _accent : _textPrimary, fontSize: 15)),
                                const SizedBox(height: 3),
                                Text(s.singer,
                                    style: const TextStyle(color: _textSecondary, fontSize: 12)),
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
