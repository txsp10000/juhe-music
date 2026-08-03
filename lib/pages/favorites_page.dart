import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../models/song.dart';
import '../widgets/swipe_action_cell.dart';
import '../utils/toast.dart';
import 'player_page.dart';

class FavoritesPage extends StatefulWidget {
  final bool fromPlayer;
  const FavoritesPage({super.key, this.fromPlayer = false});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Song> _songs = [];
  final _player = PlayerService();
  bool _editMode = false;
  final Set<int> _selected = {};
  final ScrollController _scrollController = ScrollController();

  // ─── Design tokens ───
  static const _bg = Color(0xFF000000);
  static const _surface = Color(0xFF1A1A1A);
  static const _accent = Color(0xFFFFFFFF);
  static const _textPrimary = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF999999);
  static const _textTertiary = Color(0xFF666666);

  @override
  void initState() {
    super.initState();
    _load();
    _player.addSongChangeListener(_onSongChange);
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

  Future<void> _load() async {
    final songs = await FavoritesService.load();
    if (mounted) {
      setState(() => _songs = songs);
      _scrollToPlaying();
    }
  }

  void _scrollToPlaying() {
    final current = _player.currentSong;
    if (current == null) return;
    final idx = _songs.indexWhere((s) => s.id == current.id);
    if (idx > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final offset = (idx * 62.0).clamp(0.0, _scrollController.position.maxScrollExtent);
          _scrollController.animateTo(offset,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });
    }
  }

  void _playAt(int index) {
    if (_player.currentSong?.id == _songs[index].id) {
      if (widget.fromPlayer) {
        Navigator.pop(context);
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
      }
      return;
    }
    _player.playlist.clear();
    _player.playlist.addAll(_songs);
    _player.playAt(index);
    if (widget.fromPlayer) {
      Navigator.pop(context);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
    }
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
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text(
          _editMode ? '已选 ${_selected.length} 首' : '我的收藏 (${_songs.length})',
          style: const TextStyle(color: _textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textSecondary),
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
              icon: const Icon(Icons.delete_outline, color: _textSecondary, size: 22),
              onPressed: () => setState(() => _editMode = true),
            ),
          if (_editMode) ...[
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(
                _selected.length == _songs.length ? '取消全选' : '全选',
                style: const TextStyle(color: _accent, fontSize: 14),
              ),
            ),
            TextButton(
              onPressed: _selected.isEmpty ? null : _deleteSelected,
              child: Text('删除',
                  style: TextStyle(
                      color: _selected.isEmpty ? _textTertiary : const Color(0xFFFF5E5E),
                      fontSize: 14)),
            ),
          ],
        ],
      ),
      body: _songs.isEmpty
          ? const Center(
              child: Text('还没有收藏歌曲', style: TextStyle(color: _textSecondary, fontSize: 15)))
          : ListView.builder(
              controller: _scrollController,
              itemCount: _songs.length,
              itemBuilder: (_, i) {
                final s = _songs[i];
                if (_editMode) {
                  return InkWell(
                    onTap: () => setState(() {
                      _selected.contains(i) ? _selected.remove(i) : _selected.add(i);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0x08FFFFFF))),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _selected.contains(i) ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: _selected.contains(i) ? _accent : _textTertiary,
                            size: 20,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name, style: const TextStyle(color: _textPrimary, fontSize: 15)),
                                const SizedBox(height: 3),
                                Text(s.singer, style: const TextStyle(color: _textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final isCurrent = _player.currentSong?.id == s.id;
                return SwipeActionCell(
                  actionLabel: '删除',
                  actionColor: const Color(0xFFFF5E5E),
                  onAction: () => _removeSong(i),
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
