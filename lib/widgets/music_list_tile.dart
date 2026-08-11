import 'dart:typed_data';

// The nullable index is narrowed by the conditional expression below.
// ignore_for_file: unnecessary_non_null_assertion

import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/cover_cache_service.dart';
import '../theme/app_design_tokens.dart';
import 'sound_halo.dart';

class MusicListTile extends StatefulWidget {
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
  final BorderRadius borderRadius;

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
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
  });

  @override
  State<MusicListTile> createState() => _MusicListTileState();
}

class _MusicListTileState extends State<MusicListTile> {
  Uint8List? _coverBytes;
  String? _cacheKey;
  String? _coverSource;

  @override
  void initState() {
    super.initState();
    _loadCachedCover();
  }

  @override
  void didUpdateWidget(covariant MusicListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final song = widget.song;
    final key = song.picId.isNotEmpty ? song.picId : song.id;
    if (_cacheKey != key ||
        _coverSource != song.cover ||
        oldWidget.showCover != widget.showCover) {
      _coverBytes = null;
      _cacheKey = null;
      _coverSource = null;
      _loadCachedCover();
    }
  }

  Future<void> _loadCachedCover() async {
    final song = widget.song;
    if (!widget.showCover) return;
    final key = song.picId.isNotEmpty ? song.picId : song.id;
    final source = song.cover;
    _cacheKey = key;
    _coverSource = source;
    final bytes = await CoverCacheService().resolve(key, source);
    if (mounted &&
        _cacheKey == key &&
        _coverSource == source &&
        bytes != null) {
      setState(() => _coverBytes = bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final active = widget.isCurrent || widget.selected;
    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: widget.margin,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: active
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.075),
        borderRadius: widget.borderRadius,
      ),
      child: Row(
        children: [
          widget.leadingOverride ?? _buildLeading(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.song.name,
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
          if (widget.trailing != null) ...[
            const SizedBox(width: 8),
            widget.trailing!
          ],
        ],
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: widget.borderRadius,
        onTap: widget.onTap,
        child: row,
      ),
    );
  }

  Widget _buildLeading() {
    if (widget.showCover && _coverBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(_coverBytes!,
            width: 48, height: 48, fit: BoxFit.cover),
      );
    }
    return _fallbackLeading();
  }

  Widget _fallbackLeading() {
    final index = widget.index;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.10)),
      child: Center(
        child: widget.isCurrent
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
