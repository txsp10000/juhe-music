import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/categories.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../utils/toast.dart';
import 'glass_panel.dart';

class ModeDrawer extends StatefulWidget {
  final void Function(PlaylistInfo playlist) onSelectPlaylist;
  final VoidCallback onOpenFavorites;
  final VoidCallback onRandomPlay;
  const ModeDrawer({super.key, required this.onSelectPlaylist, required this.onOpenFavorites, required this.onRandomPlay});
  @override
  State<ModeDrawer> createState() => _ModeDrawerState();
}

class _ModeDrawerState extends State<ModeDrawer> {
  static const _pinKey = 'pinned_playlists';
  final List<PlaylistInfo> _pinnedPlaylists = [];
  Color _accent = AppDesignTokens.lyricWhite;
  Color _bgHint = AppDesignTokens.inkBlack;

  final _modes = const [
    (Icons.favorite_rounded, '收藏模式'),
    (Icons.shuffle_rounded, '随机模式'),
    (Icons.nightlight_round, '助眠模式'),
    (Icons.bathtub_rounded, '洗澡'),
    (Icons.directions_run_rounded, '动感健身'),
    (Icons.eco_rounded, 'Chill 放松'),
    (Icons.mood_rounded, '快乐时光'),
    (Icons.equalizer_rounded, '电音'),
    (Icons.filter_vintage_rounded, '国风'),
  ];

  @override
  void initState() {
    super.initState();
    _loadPinned();
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

  @override
  void dispose() {
    ThemeService.accentColor.removeListener(_onThemeChange);
    ThemeService.bgHint.removeListener(_onThemeChange);
    super.dispose();
  }

  static String _encode(PlaylistInfo p) => '${p.id}|${p.name}|${p.coverUrl}';
  static PlaylistInfo? _decode(String s) {
    final parts = s.split('|');
    if (parts.length < 2 || parts[0].isEmpty) return null;
    return PlaylistInfo(parts[1], parts[0], coverUrl: parts.length > 2 ? parts[2] : '');
  }

  Future<void> _loadPinned() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pinKey) ?? [];
    _pinnedPlaylists
      ..clear()
      ..addAll(list.map(_decode).whereType<PlaylistInfo>());
    if (mounted) setState(() {});
  }

  Future<void> _savePinned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinKey, _pinnedPlaylists.map(_encode).toList());
  }

  Future<void> _pinPlaylist(PlaylistInfo p) async {
    if (_pinnedPlaylists.any((e) => e.id == p.id)) return;
    _pinnedPlaylists.add(p);
    await _savePinned();
    if (mounted) { setState(() {}); Toast.show(context, '已置顶「${p.name}」'); }
  }

  Future<void> _unpinPlaylist(PlaylistInfo p) async {
    _pinnedPlaylists.removeWhere((e) => e.id == p.id);
    await _savePinned();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.80,
      backgroundColor: Colors.transparent,
      child: MusicScaffoldBackground(
        bgHint: _bgHint,
        accent: _accent,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 34, 22, 28),
            children: [
              _buildHeader(),
              const SizedBox(height: 34),
              _selectedDefault(),
              const SizedBox(height: 26),
              _buildModeGrid(),
              const SizedBox(height: 28),
              _buildPlaylistAccess(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('听歌模式', style: AppDesignTokens.display(size: 28)),
        const SizedBox(height: 12),
        Text('选择一种方式开始播放', style: AppDesignTokens.body(size: 17, color: AppDesignTokens.warmWhite.withOpacity(0.62), weight: FontWeight.w800)),
      ],
    );
  }

  Widget _selectedDefault() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        height: 76,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppDesignTokens.selectedPill, borderRadius: BorderRadius.circular(18)),
        child: Text('||| 默认模式', style: AppDesignTokens.title(size: 23, color: const Color(0xFF3B2418))),
      ),
    );
  }

  Widget _buildModeGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 26,
      crossAxisSpacing: 8,
      childAspectRatio: 0.86,
      children: _modes.map((m) => _modeTile(m.$1, m.$2, () {
        if (m.$2 == '收藏模式') { Navigator.pop(context); widget.onOpenFavorites(); return; }
        if (m.$2 == '随机模式') { Navigator.pop(context); widget.onRandomPlay(); return; }
        Toast.show(context, '已切换到「${m.$2}」');
      })).toList(),
    );
  }

  Widget _modeTile(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppDesignTokens.lyricWhite.withOpacity(0.90), size: 30),
          const SizedBox(height: 12),
          Text(label, textAlign: TextAlign.center, maxLines: 2, style: AppDesignTokens.body(size: 14, color: AppDesignTokens.warmWhite.withOpacity(0.86), weight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildPlaylistAccess() {
    final tiles = <Widget>[];
    for (final p in _pinnedPlaylists) {
      tiles.add(_playlistTile(Icons.push_pin_rounded, p.name, () { Navigator.pop(context); widget.onSelectPlaylist(p); }, onLongPress: () => _unpinPlaylist(p)));
    }
    for (final entry in playlistCategories.entries) {
      for (final p in entry.value) {
        tiles.add(_playlistTile(_iconForCategory(entry.key), p.name, () { Navigator.pop(context); widget.onSelectPlaylist(p); }, onLongPress: () => _pinPlaylist(p)));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('歌单', style: AppDesignTokens.title(size: 20)),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 22,
          crossAxisSpacing: 8,
          childAspectRatio: 0.86,
          children: tiles,
        ),
      ],
    );
  }

  IconData _iconForCategory(String key) {
    switch (key) {
      case '榜单': return Icons.leaderboard_rounded;
      case '语种': return Icons.language_rounded;
      case '风格': return Icons.style_rounded;
      default: return Icons.queue_music_rounded;
    }
  }

  Widget _playlistTile(IconData icon, String label, VoidCallback onTap, {VoidCallback? onLongPress}) {
    return GestureDetector(onTap: onTap, onLongPress: onLongPress, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: AppDesignTokens.lyricWhite.withOpacity(0.90), size: 30), const SizedBox(height: 12), Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppDesignTokens.body(size: 14, color: AppDesignTokens.warmWhite.withOpacity(0.86), weight: FontWeight.w800))]));
  }
}
