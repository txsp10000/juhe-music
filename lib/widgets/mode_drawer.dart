import 'dart:math';
import 'package:flutter/material.dart';
import '../data/categories.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';

class ModeDrawer extends StatefulWidget {
  final void Function(PlaylistInfo playlist) onSelectPlaylist;
  final VoidCallback onOpenFavorites;
  final VoidCallback onRandomPlay;
  final VoidCallback onClose;
  const ModeDrawer({super.key, required this.onSelectPlaylist, required this.onOpenFavorites, required this.onRandomPlay, required this.onClose});
  @override
  State<ModeDrawer> createState() => _ModeDrawerState();
}

class _ModeDrawerState extends State<ModeDrawer> {
  Color _accent = AppDesignTokens.lyricWhite;
  Color _bgHint = AppDesignTokens.inkBlack;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: min(MediaQuery.of(context).size.width * 0.78, 330.0),
      child: MusicScaffoldBackground(
        bgHint: _bgHint,
        accent: _accent,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 34, 22, 28),
            children: [
              _buildHeader(),
              const SizedBox(height: 34),
              _buildQuickModes(),
              const SizedBox(height: 28),
              _buildPlaylistAccess(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('听歌模式', style: AppDesignTokens.display(size: 28)),
              const SizedBox(height: 12),
              Text('选择一种方式开始播放', style: AppDesignTokens.body(size: 17, color: AppDesignTokens.warmWhite.withOpacity(0.62), weight: FontWeight.w800)),
            ],
          ),
        ),
        GestureDetector(
          onTap: widget.onClose,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.close_rounded, color: AppDesignTokens.lyricWhite, size: 24),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickModes() {
    return Column(
      children: [
        _modeButton(Icons.favorite_rounded, '收藏模式', '播放收藏列表里的歌曲', () { widget.onClose(); widget.onOpenFavorites(); }),
        const SizedBox(height: 12),
        _modeButton(Icons.shuffle_rounded, '随机模式', '从所有歌单中随机播放', () { widget.onClose(); widget.onRandomPlay(); }),
      ],
    );
  }

  Widget _modeButton(IconData icon, String title, String subtitle, VoidCallback onTap, {bool selected = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? AppDesignTokens.selectedPill : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? const Color(0xFF3B2418) : AppDesignTokens.lyricWhite.withOpacity(0.90), size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppDesignTokens.title(size: 20, color: selected ? const Color(0xFF3B2418) : AppDesignTokens.lyricWhite)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: AppDesignTokens.caption(color: selected ? const Color(0xFF3B2418).withOpacity(0.72) : AppDesignTokens.warmWhite.withOpacity(0.62))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistAccess() {
    final tiles = <Widget>[];
    for (final entry in playlistCategories.entries) {
      for (final p in entry.value) {
        tiles.add(_playlistTile(_iconForCategory(entry.key), p.name, () { widget.onClose(); widget.onSelectPlaylist(p); }));
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

  Widget _playlistTile(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: AppDesignTokens.lyricWhite.withOpacity(0.90), size: 30), const SizedBox(height: 12), Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppDesignTokens.body(size: 14, color: AppDesignTokens.warmWhite.withOpacity(0.86), weight: FontWeight.w800))]));
  }
}
