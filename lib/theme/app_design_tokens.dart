import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';

class AppDesignTokens {
  static const inkBlack = Color(0xFF08090D);
  static const stageBlack = Color(0xFF101218);
  static const glassBlack = Color(0xFF171A22);
  static const mistLine = Color(0x1FFFFFFF);
  static const lyricWhite = Color(0xFFF8F2EC);
  static const warmWhite = Color(0xFFE9D8CA);
  static const quietGrey = Color(0xFFB9ACA2);
  static const dimGrey = Color(0xFF7B7069);
  static const danger = Color(0xFFFF5E6C);
  static const selectedPill = Color(0xFFFBF6EF);

  static const pagePadding = 20.0;
  static const densePadding = 16.0;
  static const cardRadius = 28.0;
  static const controlRadius = 18.0;
  static const sheetRadius = 28.0;

  static Color readableAccent(Color color) {
    final hsl = HSLColor.fromColor(color);
    final lightness = hsl.lightness.clamp(0.48, 0.72).toDouble();
    final saturation = hsl.saturation.clamp(0.30, 0.86).toDouble();
    return hsl.withLightness(lightness).withSaturation(saturation).toColor();
  }

  static Color surfaceFor(Color bgHint, {double opacity = 0.58}) {
    return Color.alphaBlend(bgHint.withOpacity(opacity), const Color(0xFF17100C));
  }

  static Color softPill(Color bgHint) {
    return Color.alphaBlend(bgHint.withOpacity(0.46), const Color(0xFF2B211B));
  }

  static LinearGradient albumWashGradient(Color bgHint) {
    final hsl = HSLColor.fromColor(bgHint);
    final top = hsl.withLightness((hsl.lightness + 0.10).clamp(0.16, 0.34).toDouble()).toColor();
    final mid = hsl.withLightness((hsl.lightness + 0.02).clamp(0.12, 0.28).toDouble()).toColor();
    final bottom = hsl.withLightness((hsl.lightness - 0.08).clamp(0.06, 0.18).toDouble()).toColor();
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top, mid, bottom],
      stops: const [0.0, 0.48, 1.0],
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
      color: base.withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: active ? Colors.white.withOpacity(0.22) : Colors.white.withOpacity(0.08),
        width: 0.8,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(active ? 0.24 : 0.16),
          blurRadius: active ? 24 : 16,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  static TextStyle display({double size = 30, Color color = lyricWhite}) {
    return TextStyle(color: color, fontSize: size, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -0.7);
  }

  static TextStyle title({double size = 20, Color color = lyricWhite}) {
    return TextStyle(color: color, fontSize: size, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.25);
  }

  static TextStyle body({double size = 15, Color color = lyricWhite, FontWeight weight = FontWeight.w500}) {
    return TextStyle(color: color, fontSize: size, height: 1.35, fontWeight: weight);
  }

  static TextStyle caption({double size = 12, Color color = quietGrey}) {
    return TextStyle(color: color, fontSize: size, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: 0.2);
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
    final backgroundColor = neutralize ? Color.alphaBlend(bgHint.withOpacity(0.18), AppDesignTokens.inkBlack) : bgHint;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppDesignTokens.albumWashGradient(backgroundColor)),
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
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.12),
                  Colors.black.withOpacity(0.18),
                  Colors.black.withOpacity(0.46),
                ],
                stops: const [0.0, 0.48, 1.0],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
