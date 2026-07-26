import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../models/song.dart';
import '../widgets/swipe_action_cell.dart';
import '../utils/toast.dart';
import 'player_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Song> _songs = [];
  final _player = PlayerService();
  bool _editMode = false;
  final Set<int> _selected = {};

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


  Future<void> _removeSong(int index) async {
    final song = _songs[index];
    await FavoritesService.remove(song);
    setState(() => _songs.removeAt(index));
  }

  void _toggleSelectAll() {
    if (_selected.length == _songs.length) {
      _selected.clear();
    } else {
      _selected.clear();
      for (var i = 0; i < _songs.length; i++) {
        _selected.add(i);
      }
    }
    setState(() {});
  }

  Future<void> _deleteSelected() async {
    final toDelete = _selected.toList()..sort((a, b) => b.compareTo(a));
    for (final i in toDelete) {
      await FavoritesService.remove(_songs[i]);
    }
    final remaining = <Song>[];
    for (var i = 0; i < _songs.length; i++) {
      if (!_selected.contains(i)) remaining.add(_songs[i]);
    }
    setState(() {
      _songs = remaining;
      _selected.clear();
      _editMode = false;
    });
    Toast.show(context, '已删除 ${toDelete.length} 首');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF171B26),
        title: Text(_editMode ? '已选 ${_selected.length} 首' : '我的收藏 (${_songs.length}首)',
            style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (_editMode) {
              setState(() { _editMode = false; _selected.clear(); });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          if (!_editMode && _songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
              onPressed: () => setState(() => _editMode = true),
            ),
          if (_editMode) ...[
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(
                _selected.length == _songs.length ? '取消全选' : '全选',
                style: const TextStyle(color: Color(0xFF6890F9), fontSize: 14),
              ),
            ),
            TextButton(
              onPressed: _selected.isEmpty ? null : _deleteSelected,
              child: Text('删除', style: TextStyle(
                color: _selected.isEmpty ? const Color(0xFF8F919A) : Colors.red,
                fontSize: 14,
              )),
            ),
          ],
        ],
      ),
      body: _songs.isEmpty
          ? const Center(
              child: Text('还没有收藏歌曲', style: TextStyle(color: Color(0xFF8F919A), fontSize: 16)))
          : ListView.builder(
              itemCount: _songs.length,
              itemBuilder: (_, i) {
                final s = _songs[i];
                if (_editMode) {
                  return InkWell(
                    onTap: () => setState(() {
                      _selected.contains(i) ? _selected.remove(i) : _selected.add(i);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0x15FFFFFF))),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _selected.contains(i) ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: _selected.contains(i) ? const Color(0xFF6890F9) : const Color(0xFF8F919A),
                            size: 22,
                          ),
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
                        ],
                      ),
                    ),
                  );
                }
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