import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';

class AppDesignTokens {
  static const inkBlack = Color(0xFF08090D);
  static const stageBlack = Color(0xFF101218);
  static const glassBlack = Color(0xFF171A22);
  static const queueBackground = Color(0xFF241A14);
  static const mistLine = Color(0x1FFFFFFF);
  static const lyricWhite = Color(0xFFF8F2EC);
  static const warmWhite = Color(0xFFF5F5F5);
  static const quietGrey = Color(0xFFD1D1D1);
  static const dimGrey = Color(0xFFA8A8A8);
  static const danger = Color(0xFFFF5E6C);
  static const selectedPill = Color(0xFFFBF6EF);

  static const pagePadding = 20.0;
  static const densePadding = 16.0;
  static const cardRadius = 28.0;
  static const controlRadius = 18.0;
  static const sheetRadius = 28.0;

  static Color readableAccent(Color color) {
    final hsl = HSLColor.fromColor(color);
    if (hsl.saturation < 0.08) return lyricWhite;
    final lightness = hsl.lightness.clamp(0.48, 0.72).toDouble();
    final saturation = hsl.saturation.clamp(0.30, 0.86).toDouble();
    return hsl.withLightness(lightness).withSaturation(saturation).toColor();
  }

  static Color surfaceFor(Color bgHint, {double opacity = 0.58}) {
    return Color.alphaBlend(
        bgHint.withValues(alpha: opacity), const Color(0xFF111114));
  }

  static Color softPill(Color bgHint) {
    return Color.alphaBlend(
        bgHint.withValues(alpha: 0.46), const Color(0xFF1C1C20));
  }

  static LinearGradient albumWashGradient(Color bgHint) {
    final hsl = HSLColor.fromColor(bgHint);
    final top = hsl
        .withLightness((hsl.lightness + 0.06).clamp(0.42, 0.62).toDouble())
        .toColor();
    final bottom = hsl
        .withLightness((hsl.lightness - 0.07).clamp(0.34, 0.50).toDouble())
        .toColor();
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top, bgHint, bottom],
      stops: const [0.0, 0.52, 1.0],
    );
  }

  static LinearGradient pageGradient(Color bgHint) => albumWashGradient(bgHint);

  static BoxDecoration glassDecoration({
    required Color accent,
    Color? color,
    double radius = cardRadius,
    double opacity = 0.64,
    bool active = false,
  }) {
    final base = color ?? surfaceFor(accent, opacity: 0.18);
    return BoxDecoration(
      color: base.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: active
            ? Colors.white.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.08),
        width: 0.8,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: active ? 0.24 : 0.16),
          blurRadius: active ? 24 : 16,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  static TextStyle display({double size = 30, Color color = lyricWhite}) {
    return TextStyle(
        color: color,
        fontSize: size,
        height: 1.08,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
        decoration: TextDecoration.none);
  }

  static TextStyle title({double size = 20, Color color = lyricWhite}) {
    return TextStyle(
        color: color,
        fontSize: size,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.25,
        decoration: TextDecoration.none);
  }

  static TextStyle body(
      {double size = 15,
      Color color = lyricWhite,
      FontWeight weight = FontWeight.w500}) {
    return TextStyle(
        color: color,
        fontSize: size,
        height: 1.35,
        fontWeight: weight,
        decoration: TextDecoration.none);
  }

  static TextStyle caption({double size = 12, Color color = quietGrey}) {
    return TextStyle(
        color: color,
        fontSize: size,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        decoration: TextDecoration.none);
  }
}

class MusicScaffoldBackground extends StatelessWidget {
  final Color bgHint;
  final Widget child;
  final Color? accent;
  final Uint8List? coverBytes;
  final bool useCoverBlur;
  final bool neutralize;

  const MusicScaffoldBackground({
    super.key,
    required this.bgHint,
    required this.child,
    this.accent,
    this.coverBytes,
    this.useCoverBlur = false,
    this.neutralize = false,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = neutralize
        ? Color.alphaBlend(
            bgHint.withValues(alpha: 0.28), AppDesignTokens.queueBackground)
        : bgHint;
    return TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      tween: ColorTween(end: backgroundColor),
      builder: (context, color, child) => DecoratedBox(
        decoration: BoxDecoration(
            gradient:
                AppDesignTokens.albumWashGradient(color ?? backgroundColor)),
        child: child,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (useCoverBlur && coverBytes != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
              child: Opacity(
                opacity: 0.36,
                child: Image.memory(coverBytes!, fit: BoxFit.cover),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
