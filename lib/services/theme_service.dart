import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

class ThemeService {
  /// 主强调色（可变，跟随当前封面图的主色调）
  static final ValueNotifier<Color> accentColor = ValueNotifier(Colors.white);
  /// 背景微调色（封面主色的极暗版本）
  static final ValueNotifier<Color> bgHint = ValueNotifier(const Color(0xFF000000));

  static Future<void> updateFromCover(Uint8List bytes) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        size: const Size(50, 50),
        maximumColorCount: 8,
      );
      final raw = palette.dominantColor?.color ?? Colors.white;
      final hsl = HSLColor.fromColor(raw);
      // 保证在暗色背景上清晰可见
      final accent = hsl
          .withLightness(hsl.lightness.clamp(0.35, 0.7))
          .withSaturation(hsl.saturation.clamp(0.0, 0.75))
          .toColor();
      accentColor.value = accent;
      // 背景微调
      bgHint.value = hsl
          .withLightness(hsl.lightness.clamp(0.03, 0.08))
          .withSaturation(hsl.saturation * 0.3)
          .toColor();
    } catch (_) {}
  }

  /// 重置为默认白色
  static void reset() {
    accentColor.value = Colors.white;
    bgHint.value = const Color(0xFF000000);
  }
}
