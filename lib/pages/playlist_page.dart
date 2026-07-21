import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/player_service.dart';
import '../models/song.dart';
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

  String _fmt(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  String _qualityLabel(String q) {
    return switch (q) {
      'flac' => 'FLAC',
      '320k' => '320k',
      '192k' => '192k',
      '128k' => '128k',
      _ => q,
    };
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
                return Focus(
                  autofocus: isCurrent,
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                      _playAt(i);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (ctx) {
                      final hasFocus = Focus.of(ctx).hasFocus;
                      return GestureDetector(
                        onTap: () => _playAt(i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? const Color(0x1A6890F9)
                                : (hasFocus ? const Color(0x1A6890F9) : Colors.transparent),
                            border: hasFocus || isCurrent
                                ? const Border(bottom: BorderSide(color: Color(0xFF6890F9), width: 2))
                                : const Border(bottom: BorderSide(color: Color(0x15FFFFFF))),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isCurrent ? Icons.volume_up : Icons.music_note,
                                color: isCurrent ? const Color(0xFF6890F9) : const Color(0xFF8F919A),
                                size: 22,
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
                              Text(_fmt(s.duration),
                                  style: const TextStyle(color: Color(0xFF8F919A), fontSize: 13)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
