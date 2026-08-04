import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/sound_halo.dart';
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
    final hasSong = _player.currentSong != null;
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
                  const SizedBox(width: 70),
                  _navLabel('收藏', 2),
                ],
              ),
            ),
            Positioned(
              bottom: 0,
              child: GestureDetector(
                onTap: () {
                  if (_tab == 0 && hasSong) {
                    _player.togglePlayPause();
                  } else {
                    setState(() => _tab = 0);
                  }
                },
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: hasSong ? Colors.white : Colors.white38, width: 3),
                    color: Colors.white.withOpacity(hasSong ? 0.05 : 0.02),
                  ),
                  child: Center(
                    child: _tab == 0
                        ? Icon(
                            hasSong
                                ? (_player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded)
                                : Icons.play_arrow_rounded,
                            color: hasSong ? Colors.white : Colors.white38,
                            size: 34,
                          )
                        : hasSong
                            ? Opacity(opacity: _player.isPlaying ? 1.0 : 0.8, child: MiniWave(playing: _player.isPlaying, color: Colors.white, size: 24))
                            : Icon(Icons.play_arrow_rounded, color: Colors.white24, size: 34),
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
    final active = _tab == tabIndex;
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
