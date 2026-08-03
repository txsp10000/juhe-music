import 'dart:math';
import 'package:flutter/material.dart';
import '../services/player_service.dart';
import '../models/song.dart';
import 'player_page.dart';
import 'search_page.dart';
import 'favorites_page.dart';

/// 根页面：播放器 / 收藏 / 搜索 三个 Tab 切换，底部栏常驻
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final _player = PlayerService();
  int _tab = 0; // 0=播放器, 1=收藏, 2=搜索

  @override
  void initState() {
    super.initState();
    _player.addPlayStateListener(_onPlayState);
    _player.addSongChangeListener(_onSongChange);
  }

  void _onPlayState(bool _) { if (mounted) setState(() {}); }
  void _onSongChange(Song _) { if (mounted) setState(() {}); }

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
                FavoritesPage(embedded: true),
                SearchPage(embedded: true),
              ],
            ),
          ),
          SafeArea(top: false, child: _buildTabBar()),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final hasSong = _player.currentSong != null;
    final onPlayerTab = _tab == 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1A1A1A), width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildTextTab('收藏', 1),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPlayerTab
                ? (hasSong ? () => _player.togglePlayPause() : null)
                : () => setState(() => _tab = 0),
            child: SizedBox(
              width: 72,
              height: 52,
              child: Center(
                child: onPlayerTab
                    ? Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: hasSong ? Colors.white : const Color(0xFF666666), width: 2.5),
                        ),
                        child: Center(
                          child: Icon(
                            _player.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: hasSong ? Colors.white : const Color(0xFF666666), size: 22),
                        ),
                      )
                    : _MusicIndicator(playing: _player.isPlaying),
              ),
            ),
          ),
          _buildTextTab('搜索', 2),
        ],
      ),
    );
  }

  Widget _buildTextTab(String label, int tabIndex) {
    final active = _tab == tabIndex;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = _tab == tabIndex ? 0 : tabIndex),
      child: SizedBox(
        width: 88, height: 48,
        child: Center(
          child: Text(label,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF999999),
              fontSize: 16, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}

/// 音乐指示器：三根竖杠 + "音乐"文字，播放中跳动
class _MusicIndicator extends StatefulWidget {
  final bool playing;
  const _MusicIndicator({required this.playing});
  @override
  State<_MusicIndicator> createState() => _MusicIndicatorState();
}

class _MusicIndicatorState extends State<_MusicIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(_MusicIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing) _controller.repeat(); else { _controller.stop(); _controller.value = 0.0; }
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = _controller.value * 2 * pi;
        final heights = [10.0 + 6 * sin(t), 10.0 + 6 * sin(t + 2.1), 10.0 + 6 * sin(t + 4.2)];
        return Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(8)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(3, (i) => Container(
                  width: 3, height: heights[i].clamp(4.0, 14.0),
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1.5)),
                )),
              ),
              const SizedBox(height: 1),
              const Text('音乐', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w500)),
            ],
          ),
        );
      },
    );
  }
}
