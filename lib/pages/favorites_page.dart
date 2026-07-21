import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../models/song.dart';
import 'player_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Song> _songs = [];
  final _player = PlayerService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final songs = await FavoritesService.load();
    if (mounted) setState(() => _songs = songs);
  }

  void _playAt(int index) {
    _player.playlist.clear();
    _player.playlist.addAll(_songs);
    _player.playAt(index);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
  }

  String _fmt(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF171B26),
        title: const Text('我的收藏', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _songs.isEmpty
          ? const Center(
              child: Text('还没有收藏歌曲', style: TextStyle(color: Color(0xFF8F919A), fontSize: 16)))
          : ListView.builder(
              itemCount: _songs.length,
              itemBuilder: (_, i) {
                final s = _songs[i];
                return Focus(
                  autofocus: i == 0,
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
                            color: hasFocus ? const Color(0x1A6890F9) : Colors.transparent,
                            border: hasFocus
                                ? const Border(bottom: BorderSide(color: Color(0xFF6890F9), width: 2))
                                : const Border(bottom: BorderSide(color: Color(0x15FFFFFF))),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.music_note, color: hasFocus ? const Color(0xFF6890F9) : const Color(0xFF8F919A), size: 22),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.name, style: TextStyle(color: hasFocus ? Colors.white : const Color(0xFFE0E0E0), fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text(s.singer, style: const TextStyle(color: Color(0xFF8F919A), fontSize: 13)),
                                  ],
                                ),
                              ),
                              Text(_fmt(s.duration), style: const TextStyle(color: Color(0xFF8F919A), fontSize: 13)),
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
