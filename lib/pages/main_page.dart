import 'package:flutter/material.dart';
import '../services/player_service.dart';
import '../models/song.dart';
import 'player_page.dart';
import 'search_page.dart';
import 'favorites_page.dart';

/// 根页面：播放器 / 搜索 / 收藏 三个 Tab 切换，底部栏常驻
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final _player = PlayerService();
  int _tab = 0; // 0=播放器, 1=搜索, 2=收藏

  @override
  void initState() {
    super.initState();
    _player.addPlayStateListener(_onPlayState);
    _player.addSongChangeListener(_onSongChange);
  }

  void _onPlayState(bool _) {
    if (mounted) setState(() {});
  }

  void _onSongChange(Song _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player.removePlayStateListener(_onPlayState);
    _player.removeSongChangeListener(_onSongChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [
                PlayerPage(isRoot: true),
                SearchPage(embedded: true),
                FavoritesPage(embedded: true),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: _buildTabBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final hasSong = _player.currentSong != null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1A1A1A), width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: () => setState(() => _tab = _tab == 1 ? 0 : 1),
            child: Text('搜索',
                style: TextStyle(
                    color: _tab == 1 ? Colors.white : const Color(0xFF999999),
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: hasSong ? () => _player.togglePlayPause() : null,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: hasSong ? Colors.white : const Color(0xFF666666),
                    width: 2.5),
              ),
              child: Center(
                child: Icon(
                  _player.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: hasSong ? Colors.white : const Color(0xFF666666),
                  size: 26,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _tab = _tab == 2 ? 0 : 2),
            child: Text('收藏',
                style: TextStyle(
                    color: _tab == 2 ? Colors.white : const Color(0xFF999999),
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
