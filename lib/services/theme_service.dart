import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../theme/app_design_tokens.dart';

class ThemeService {
  static final ValueNotifier<Color> accentColor =
      ValueNotifier(AppDesignTokens.lyricWhite);

  static final ValueNotifier<Color> bgHint =
      ValueNotifier(AppDesignTokens.queueBackground);

  static int _coverGeneration = 0;

  static void invalidateCover() {
    _coverGeneration++;
  }

  static Future<void> updateFromCover(Uint8List bytes) async {
    final generation = ++_coverGeneration;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        size: const Size(64, 64),
        maximumColorCount: 12,
      );
      final raw = _selectPaletteColor(palette);
      if (raw == null || generation != _coverGeneration) return;

      final hsl = HSLColor.fromColor(raw);
      final softened = hsl
          .withSaturation(hsl.saturation.clamp(0.16, 0.42).toDouble())
          .withLightness(hsl.lightness.clamp(0.44, 0.56).toDouble());
      bgHint.value = softened.toColor();
      accentColor.value = AppDesignTokens.lyricWhite;
    } catch (_) {
      // Keep the last stable theme if extracting this cover fails.
    }
  }

  static Color? _selectPaletteColor(PaletteGenerator palette) {
    final candidates = <Color?>[
      palette.mutedColor?.color,
      palette.darkMutedColor?.color,
      palette.vibrantColor?.color,
      palette.darkVibrantColor?.color,
      palette.dominantColor?.color,
      palette.lightMutedColor?.color,
      palette.lightVibrantColor?.color,
    ];
    for (final color in candidates) {
      if (color == null) continue;
      final hsl = HSLColor.fromColor(color);
      if (hsl.saturation >= 0.08 &&
          hsl.lightness >= 0.10 &&
          hsl.lightness <= 0.90) {
        return color;
      }
    }
    return palette.dominantColor?.color;
  }

  static void reset() {
    invalidateCover();
    accentColor.value = AppDesignTokens.lyricWhite;
    bgHint.value = AppDesignTokens.queueBackground;
  }
}
