import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../models/song.dart';
import '../models/platform.dart';
import '../widgets/swipe_action_cell.dart';
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

  String _platformName(String code) {
    final p = Platform.fromCode(code);
    return p?.displayName ?? code;
  }

  Future<void> _removeSong(int index) async {
    final song = _songs[index];
    await FavoritesService.remove(song);
    setState(() => _songs.removeAt(index));
  }

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
                return SwipeActionCell(
                  actionLabel: '删除',
                  actionColor: Colors.red,
                  onAction: () => _removeSong(i),
                  child: InkWell(
                    onTap: () => _playAt(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0x15FFFFFF))),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.music_note, color: Color(0xFF8F919A), size: 22),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name, style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 16)),
                                const SizedBox(height: 4),
                                Text(s.singer, style: const TextStyle(color: Color(0xFF8F919A), fontSize: 13)),
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
