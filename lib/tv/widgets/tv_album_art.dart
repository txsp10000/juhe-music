import 'dart:io';

import 'package:flutter/material.dart';

import '../tv_layout_metrics.dart';
import '../tv_tokens.dart';

class TvAlbumArt extends StatelessWidget {
  final String cover;
  final double size;
  final double? width;
  final double? height;
  final double radius;
  final bool border;

  const TvAlbumArt({
    super.key,
    required this.cover,
    required this.size,
    this.width,
    this.height,
    this.radius = 28,
    this.border = true,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final resolvedWidth = width ?? size;
    final resolvedHeight = height ?? size;
    final art = ClipRRect(
      borderRadius: BorderRadius.circular(metrics.value(radius, minimum: 12)),
      child: SizedBox(
        width: resolvedWidth.isFinite ? resolvedWidth : double.infinity,
        height: resolvedHeight.isFinite ? resolvedHeight : double.infinity,
        child: _content(
          metrics,
          resolvedWidth.isFinite && resolvedHeight.isFinite,
          resolvedWidth < resolvedHeight ? resolvedWidth : resolvedHeight,
        ),
      ),
    );

    return border
        ? Container(
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(metrics.value(radius, minimum: 12)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: art,
          )
        : art;
  }

  Widget _content(
    TvLayoutMetrics metrics,
    bool hasBoundedSize,
    double shortestSide,
  ) {
    if (cover.isNotEmpty) {
      final uri = Uri.tryParse(cover);
      if (uri != null && uri.scheme == 'file') {
        return Image.file(File(uri.toFilePath()), fit: BoxFit.cover);
      }
      if (uri == null || uri.scheme.isEmpty) {
        final file = File(cover);
        if (file.existsSync()) {
          return Image.file(file, fit: BoxFit.cover);
        }
      }
      return Image.network(
        cover,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            _fallback(metrics, hasBoundedSize, shortestSide),
      );
    }
    return _fallback(metrics, hasBoundedSize, shortestSide);
  }

  Widget _fallback(
    TvLayoutMetrics metrics,
    bool hasBoundedSize,
    double shortestSide,
  ) {
    return Container(
      color: TvTokens.panelSoft,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        size: hasBoundedSize
            ? metrics.value(shortestSide * 0.32, minimum: 34)
            : metrics.value(72, minimum: 42),
        color: TvTokens.focus,
      ),
    );
  }
}
