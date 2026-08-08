import 'dart:math';

import 'package:flutter/material.dart';

import '../models/listening_mode.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';

class ModeDrawer extends StatefulWidget {
  final ValueChanged<ListeningMode> onSelectMode;
  final VoidCallback onOpenCurrentMode;
  final VoidCallback onOpenFavorites;
  final VoidCallback onRandomPlay;
  final VoidCallback onClose;
  final ListeningMode? currentMode;

  const ModeDrawer({
    super.key,
    required this.onSelectMode,
    required this.onOpenCurrentMode,
    required this.onOpenFavorites,
    required this.onRandomPlay,
    required this.onClose,
    this.currentMode,
  });

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
    if (!mounted) return;
    setState(() {
      _accent = AppDesignTokens.readableAccent(ThemeService.accentColor.value);
      _bgHint = ThemeService.bgHint.value;
    });
  }

  @override
  void dispose() {
    ThemeService.accentColor.removeListener(_onThemeChange);
    ThemeService.bgHint.removeListener(_onThemeChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: min(MediaQuery.of(context).size.width * 0.78, 330.0),
        child: MusicScaffoldBackground(
          bgHint: _bgHint,
          accent: _accent,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 34, 22, 28),
              children: [
                Text('听歌模式', style: AppDesignTokens.display(size: 28)),
                const SizedBox(height: 10),
                Text('选择一种方式开始播放',
                    style: AppDesignTokens.body(
                      size: 16,
                      color: AppDesignTokens.warmWhite.withValues(alpha: 0.62),
                      weight: FontWeight.w800,
                    )),
                const SizedBox(height: 28),
                _modeButton(
                  widget.currentMode?.icon ?? Icons.graphic_eq_rounded,
                  '当前模式',
                  widget.currentMode?.name ?? '返回播放页面',
                  () {
                    widget.onClose();
                    widget.onOpenCurrentMode();
                  },
                ),
                const SizedBox(height: 12),
                _modeButton(Icons.favorite_rounded, '收藏模式', '播放收藏里的歌曲', () {
                  widget.onClose();
                  widget.onOpenFavorites();
                }),
                const SizedBox(height: 12),
                _modeButton(Icons.shuffle_rounded, '随机场景', '从当前场景中随机开始', () {
                  widget.onClose();
                  widget.onRandomPlay();
                }),
                const SizedBox(height: 28),
                Text('常用模式', style: AppDesignTokens.title(size: 20)),
                const SizedBox(height: 14),
                _modeGrid(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: listeningModes.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.94,
      ),
      itemBuilder: (_, index) => _modeTile(listeningModes[index]),
    );
  }

  Widget _modeTile(ListeningMode mode) {
    return GestureDetector(
      onTap: () {
        widget.onClose();
        widget.onSelectMode(mode);
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(mode.icon, color: _accent, size: 26),
          ),
          const SizedBox(height: 8),
          Text(mode.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppDesignTokens.caption(color: AppDesignTokens.warmWhite)),
        ],
      ),
    );
  }

  Widget _modeButton(
      IconData icon, String title, String subtitle, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppDesignTokens.lyricWhite, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppDesignTokens.title(size: 19)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: AppDesignTokens.caption(
                          color: AppDesignTokens.warmWhite
                              .withValues(alpha: 0.62))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
