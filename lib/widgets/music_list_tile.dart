import 'package:flutter/material.dart';
import '../models/song.dart';
import '../theme/app_design_tokens.dart';
import 'sound_halo.dart';

class MusicListTile extends StatelessWidget {
  final Song song;
  final int? index;
  final bool isCurrent;
  final bool selected;
  final Color accent;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? leadingOverride;
  final bool showCover;
  final EdgeInsetsGeometry margin;

  const MusicListTile({
    super.key,
    required this.song,
    required this.accent,
    this.index,
    this.isCurrent = false,
    this.selected = false,
    this.onTap,
    this.trailing,
    this.leadingOverride,
    this.showCover = true,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
  });

  @override
  Widget build(BuildContext context) {
    final active = isCurrent || selected;
    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: margin,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: active
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          leadingOverride ?? _buildLeading(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppDesignTokens.body(
                        size: 16,
                        color: active
                            ? AppDesignTokens.lyricWhite
                            : AppDesignTokens.lyricWhite
                                .withValues(alpha: 0.92),
                        weight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(song.singer.isEmpty ? '未知歌手' : song.singer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppDesignTokens.body(
                        size: 13,
                        color:
                            AppDesignTokens.warmWhite.withValues(alpha: 0.58),
                        weight: FontWeight.w600)),
                if (song.album.isNotEmpty || song.source.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                      [
                        if (song.album.isNotEmpty) song.album,
                        if (song.source.isNotEmpty) song.source
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppDesignTokens.caption(
                          size: 10.5,
                          color: AppDesignTokens.warmWhite
                              .withValues(alpha: 0.38))),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: row,
      ),
    );
  }

  Widget _buildLeading() {
    if (showCover && song.cover.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(song.cover,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallbackLeading()),
      );
    }
    return _fallbackLeading();
  }

  Widget _fallbackLeading() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.10)),
      child: Center(
        child: isCurrent
            ? MiniWave(
                playing: true, color: AppDesignTokens.lyricWhite, size: 22)
            : Text(index == null ? '♪' : '${index! + 1}',
                style: AppDesignTokens.caption(
                    size: index == null ? 18 : 13,
                    color: AppDesignTokens.lyricWhite)),
      ),
    );
  }
}

class MusicEmptyState extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const MusicEmptyState(
      {super.key,
      required this.accent,
      required this.icon,
      required this.title,
      required this.message,
      this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10)),
                child: Icon(icon, color: AppDesignTokens.lyricWhite, size: 36)),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: AppDesignTokens.title(size: 22)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: AppDesignTokens.body(
                    size: 14,
                    color: AppDesignTokens.warmWhite.withValues(alpha: 0.62),
                    weight: FontWeight.w600)),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
