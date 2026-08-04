import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import 'favorites_page.dart';
import 'player_page.dart';
import 'search_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final _player = PlayerService();
  int _tab = 0;
  Color _accent = Colors.white;
  Color _bgHint = AppDesignTokens.inkBlack;

  @override
  void initState() {
    super.initState();
    _player.addPlayStateListener(_onPlayState);
    _player.addSongChangeListener(_onSongChange);
    _onThemeChange();
    ThemeService.accentColor.addListener(_onThemeChange);
    ThemeService.bgHint.addListener(_onThemeChange);
  }

  void _onThemeChange() {
    if (mounted) {
      setState(() {
        _accent = AppDesignTokens.readableAccent(ThemeService.accentColor.value);
        _bgHint = ThemeService.bgHint.value;
      });
    }
  }

  void _onPlayState(bool _) { if (mounted) setState(() {}); }
  void _onSongChange(Song _) { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _player.removePlayStateListener(_onPlayState);
    _player.removeSongChangeListener(_onSongChange);
    ThemeService.accentColor.removeListener(_onThemeChange);
    ThemeService.bgHint.removeListener(_onThemeChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.inkBlack,
      extendBody: true,
      body: MusicScaffoldBackground(
        bgHint: _bgHint,
        accent: _accent,
        child: IndexedStack(
          index: _tab,
          children: const [
            PlayerPage(isRoot: true),
            SearchPage(embedded: true),
            FavoritesPage(embedded: true),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(top: false, child: _buildBottomNav()),
    );
  }

  Widget _buildBottomNav() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 0, 26, 12),
      child: SizedBox(
        height: 74,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _navLabel('发现', 0),
                  _navLabel('听抖音', 1),
                  const SizedBox(width: 70),
                  _navLabel('福利', 2),
                  _navLabel('我的', 2),
                ],
              ),
            ),
            Positioned(
              bottom: 0,
              child: GestureDetector(
                onTap: _tab == 0 && _player.currentSong != null
                    ? () => _player.togglePlayPause()
                    : () => setState(() => _tab = 0),
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    color: Colors.white.withOpacity(0.05),
                  ),
                  child: Icon(
                    _player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navLabel(String label, int tabIndex) {
    final active = _tab == tabIndex && (label == '发现' || label == '听抖音' || label == '我的');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = tabIndex),
      child: SizedBox(
        width: 64,
        height: 40,
        child: Center(
          child: Text(
            label,
            style: AppDesignTokens.body(
              size: 14,
              color: active ? AppDesignTokens.lyricWhite : AppDesignTokens.warmWhite.withOpacity(0.46),
              weight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
