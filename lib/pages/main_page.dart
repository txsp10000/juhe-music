import 'dart:async';
import 'package:flutter/material.dart';
import '../api/music_api.dart';
import '../models/listening_mode.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import '../services/favorites_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../utils/toast.dart';
import '../widgets/mode_drawer.dart';
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

  bool _drawerOpen = false;
  int _modeLoadGeneration = 0;

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
        _accent = AppDesignTokens.readableAccent(
          ThemeService.accentColor.value,
        );
        _bgHint = ThemeService.bgHint.value;
      });
    }
  }

  void _onPlayState(bool _) {
    if (mounted) setState(() {});
  }

  void _onSongChange(Song _) {
    if (mounted) setState(() {});
  }

  void _showPlayer() {
    if (mounted) setState(() => _tab = 0);
  }

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
    final panelWidth =
        (MediaQuery.of(context).size.width * 0.84).clamp(0.0, 380.0);
    final bottomControlHeight = 56.0 + MediaQuery.of(context).padding.bottom;

    return MusicScaffoldBackground(
      bgHint: _bgHint,
      accent: _accent,
      child: Stack(
        children: [
          Scaffold(
            // The themed wrapper paints the area reserved for the bottom nav
            // as well, so Android does not fall back to a black strip.
            backgroundColor: Colors.transparent,
            // Keep the page viewport above the persistent nav. This avoids
            // platform-specific safe-area overlap on both iOS and Android.
            extendBody: false,
            body: Padding(
              padding: EdgeInsets.only(bottom: bottomControlHeight),
              child: IndexedStack(
                index: _tab,
                children: [
                  PlayerPage(
                      embedded: true, onOpenDrawer: () => _openDrawer(0)),
                  SearchPage(
                    embedded: true,
                    onShowPlayer: _showPlayer,
                    onOpenDrawer: () => _openDrawer(1),
                  ),
                  FavoritesPage(embedded: true, onShowPlayer: _showPlayer),
                ],
              ),
            ),
          ),
          // Render the controls directly in the shared background stack.
          // Keeping them outside Scaffold's bottomNavigationBar slot removes
          // the platform Material surface that was still tinting this area.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _buildBottomNav(),
            ),
          ),
          if (_drawerOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _drawerOpen = false),
                child: Container(color: Colors.black.withValues(alpha: 0.40)),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: _drawerOpen ? 0 : -panelWidth,
            top: 0,
            bottom: 0,
            width: panelWidth,
            child: ModeDrawer(
              onSelectMode: _loadAndPlay,
              onOpenFavorites: _openFavorites,
              onRandomPlay: _randomPlay,
              onClose: _closeDrawer,
              currentMode: _player.activeMode,
              queueSource: _player.queueSource,
            ),
          ),
        ],
      ),
    );
  }

  void _openDrawer(int source) {
    if (mounted) setState(() => _drawerOpen = true);
  }

  void _closeDrawer() {
    if (mounted) setState(() => _drawerOpen = false);
  }

  void _loadAndPlay(ListeningMode mode) {
    unawaited(_loadAndPlayAsync(mode));
  }

  Future<void> _loadAndPlayAsync(ListeningMode mode) async {
    final generation = ++_modeLoadGeneration;
    _closeDrawer();
    if (mounted) setState(() => _tab = 0);
    Toast.show(context, '正在加载「${mode.name}」...');
    try {
      final songs = await MusicApi.getModeTracks(mode.sceneModeId);
      if (!mounted || generation != _modeLoadGeneration) return;
      if (songs.isEmpty) {
        Toast.show(context, '这个模式暂时没有歌曲');
        return;
      }
      _player.replaceQueue(songs, mode: mode);
      await _player.playAt(0);
    } catch (_) {
      if (mounted && generation == _modeLoadGeneration) {
        Toast.show(context, '网络或接口异常，模式加载失败');
      }
    }
  }

  Future<void> _openFavorites() async {
    _closeDrawer();
    final songs = await FavoritesService.load();
    if (!mounted) return;
    if (songs.isEmpty) {
      Toast.show(context, '收藏里还没有歌曲');
      return;
    }
    _player.replaceQueue(songs, source: PlaybackQueueSource.favorites);
    await _player.playAt(0);
    if (mounted) setState(() => _tab = 0);
  }

  void _randomPlay() {
    final mode = listeningModes[
        DateTime.now().microsecondsSinceEpoch % listeningModes.length];
    _loadAndPlay(mode);
  }

  Widget _buildBottomNav() {
    final hasSong = _player.currentSong != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: SizedBox(
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Row(
                children: [
                  Expanded(child: _navLabel('搜索', 1)),
                  const SizedBox(width: 58),
                  Expanded(child: _navLabel('收藏', 2)),
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
                child: SizedBox(
                  width: 72,
                  height: 52,
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.6),
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      child: Center(
                        child: _tab == 0
                            ? hasSong
                                ? Icon(
                                    _player.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  )
                                : MiniWave(
                                    playing: false,
                                    color: Colors.white,
                                    size: 20,
                                  )
                            : hasSong
                                ? Opacity(
                                    opacity: _player.isPlaying ? 1.0 : 0.8,
                                    child: MiniWave(
                                      playing: _player.isPlaying,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  )
                                : const MiniWave(
                                    playing: false,
                                    color: Color(0x61FFFFFF),
                                    size: 20,
                                  ),
                      ),
                    ),
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
        width: double.infinity,
        height: 52,
        child: Center(
          child: Text(
            label,
            style: AppDesignTokens.body(
              size: 14,
              color: active
                  ? AppDesignTokens.lyricWhite
                  : AppDesignTokens.warmWhite.withValues(alpha: 0.46),
              weight: FontWeight.w800,
            ).copyWith(
              decoration: TextDecoration.none,
              decorationColor: Colors.transparent,
              decorationThickness: 0,
            ),
          ),
        ),
      ),
    );
  }
}
