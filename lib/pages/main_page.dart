import 'dart:math';
import 'package:flutter/material.dart';
import '../api/music_api.dart';
import '../data/categories.dart';
import '../models/song.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
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
        _accent =
            AppDesignTokens.readableAccent(ThemeService.accentColor.value);
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
        MediaQuery.of(context).size.width * 0.78.clamp(0.0, 330.0);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppDesignTokens.inkBlack,
          extendBody: true,
          body: MusicScaffoldBackground(
            bgHint: _bgHint,
            accent: _accent,
            child: IndexedStack(
              index: _tab,
              children: [
                PlayerPage(onOpenDrawer: () => _openDrawer(0)),
                SearchPage(
                    embedded: true,
                    onShowPlayer: _showPlayer,
                    onOpenDrawer: () => _openDrawer(1)),
                FavoritesPage(embedded: true, onShowPlayer: _showPlayer),
              ],
            ),
          ),
          bottomNavigationBar:
              SafeArea(top: false, child: _buildBottomNav()),
        ),
        if (_drawerOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _drawerOpen = false),
              child: Container(color: Colors.black.withOpacity(0.40)),
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
            onSelectPlaylist: _loadAndPlay,
            onOpenFavorites: _openFavorites,
            onRandomPlay: _randomPlay,
            onClose: _closeDrawer,
          ),
        ),
      ],
    );
  }

  void _openDrawer(int source) {
    if (mounted) setState(() => _drawerOpen = true);
  }

  void _closeDrawer() {
    if (mounted) setState(() => _drawerOpen = false);
  }

  void _loadAndPlay(PlaylistInfo pl) {
    _closeDrawer();
    Toast.show(context, '正在加载「${pl.name}」...');
    MusicApi.getPlaylist(pl.id).then((songs) {
      if (!mounted) return;
      if (songs.isEmpty) {
        Toast.show(context, '未找到歌曲');
        return;
      }
      _player.playlist.clear();
      _player.playlist.addAll(songs);
      _player.playAt(0);
    }).catchError((_) {
      if (mounted) Toast.show(context, '加载失败，请重试');
    });
  }

  Future<void> _openFavorites() async {
    _closeDrawer();
    final songs = await FavoritesService.load();
    if (!mounted) return;
    if (songs.isEmpty) {
      Toast.show(context, '收藏列表为空');
      return;
    }
    _player.playlist.clear();
    _player.playlist.addAll(songs);
    _player.playAt(0);
  }

  void _randomPlay() {
    final playlists =
        playlistCategories.values.expand((items) => items).toList();
    if (playlists.isEmpty) {
      _closeDrawer();
      Toast.show(context, '暂无可随机播放的歌单');
      return;
    }
    final random = Random();
    _loadAndPlay(playlists[random.nextInt(playlists.length)]);
  }

  Widget _buildBottomNav() {
    final hasSong = _player.currentSong != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: SizedBox(
        height: 70,
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
                  _navLabel('搜索', 1),
                  const SizedBox(width: 82),
                  _navLabel('收藏', 2),
                ],
              ),
            ),
            Positioned(
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_tab == 0 && hasSong) {
                    _player.togglePlayPause();
                  } else {
                    setState(() => _tab = 0);
                  }
                },
                child: SizedBox(
                  width: 80,
                  height: 68,
                  child: Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white,
                            width: 2.6),
                        color: Colors.white.withOpacity(0.05),
                      ),
                      child: Center(
                        child: _tab == 0
                            ? Icon(
                                hasSong
                                    ? (_player.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded)
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 28,
                              )
                            : hasSong
                                ? Opacity(
                                    opacity: _player.isPlaying ? 1.0 : 0.8,
                                    child: MiniWave(
                                        playing: _player.isPlaying,
                                        color: Colors.white,
                                        size: 20))
                                : Icon(Icons.play_arrow_rounded,
                                    color: Colors.white24, size: 34),
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
        width: 112,
        height: 64,
        child: Center(
          child: Text(
            label,
            style: AppDesignTokens.body(
              size: 14,
              color: active
                  ? AppDesignTokens.lyricWhite
                  : AppDesignTokens.warmWhite.withOpacity(0.46),
              weight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
