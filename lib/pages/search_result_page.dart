import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/music_api.dart';
import '../models/song.dart';
import '../models/platform.dart';
import '../models/search_result.dart';
import '../services/player_service.dart';
import 'player_page.dart';

class SearchResultPage extends StatefulWidget {
  final String keyword;
  const SearchResultPage({super.key, required this.keyword});

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  final _player = PlayerService();
  bool _loading = true;
  List<PlatformResult> _results = [];
  List<Song> _songs = [];
  String _selectedPlatform = '';

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    final platforms = Platform.searchablePlatforms;
    final futures = platforms.map((p) async {
      try {
        final r = await MusicApi.searchByPlatform(p, widget.keyword);
        return PlatformResult(platform: p, songs: r.list, total: r.total);
      } catch (e) {
        return PlatformResult(platform: p, songs: [], total: 0, error: e.toString());
      }
    });
    final all = await Future.wait(futures);
    final valid = all.where((r) => r.songs.isNotEmpty).toList();
    if (!mounted) return;
    setState(() { _results = valid; _loading = false; });
    if (valid.isNotEmpty) {
      _showPlatformPicker();
    }
  }

  void _showPlatformPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171B26),
        title: Text('选择音源 — "${widget.keyword}"',
            style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _results.map((r) {
            final label = '${r.platform.displayName} (${r.songs.length}首)';
            return Focus(
              autofocus: _results.indexOf(r) == 0,
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _songs = r.songs;
                    _selectedPlatform = r.platform.displayName;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x1A6890F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x336890F9)),
                  ),
                  child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
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
        title: Text(
          _selectedPlatform.isNotEmpty
              ? '搜索结果 · $_selectedPlatform'
              : '搜索中...',
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6890F9)))
          : _songs.isEmpty
              ? const Center(child: Text('所有平台均无搜索结果',
                  style: TextStyle(color: Color(0xFF8F919A), fontSize: 16)))
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
                                  Icon(Icons.music_note,
                                      color: hasFocus ? const Color(0xFF6890F9) : const Color(0xFF8F919A), size: 22),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(s.name,
                                            style: TextStyle(color: hasFocus ? Colors.white : const Color(0xFFE0E0E0), fontSize: 16)),
                                        Text(s.singer, style: const TextStyle(color: Color(0xFF8F919A), fontSize: 13)),
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
