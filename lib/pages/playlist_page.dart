import 'package:flutter/material.dart';
import '../services/player_service.dart';
import '../models/song.dart';
import '../models/platform.dart';
import '../widgets/swipe_action_cell.dart';
import 'player_page.dart';

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  final _player = PlayerService();

  void _playAt(int index) {
    _player.playAt(index);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
  }

  String _qualityLabel(String q) {
    return switch (q) {
      'flac' => 'FLAC',
      '320k' => '320k',
      '192k' => '192k',
      '128k' => '128k',
      _ => q,
    };
  }
  String _platformName(String code) {
    final p = Platform.fromCode(code);
    return p?.displayName ?? code;
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
          ? const Center(child: Text('暂无歌曲', style: TextStyle(color: Color(0xFF8F919A), fontSize: 16)))
          : ListView.builder(
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
                                    style: const TextStyle(color: Color(0xFF8F919A), fontSize: 14)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name,
                                    style: TextStyle(
                                        color: isCurrent ? const Color(0xFF6890F9) : Colors.white,
                                        fontSize: 16)),
                                Text('${s.singer} | ${_qualityLabel(s.quality)}',
                                    style: const TextStyle(color: Color(0xFF8F919A), fontSize: 13)),
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
    );
  }
}
