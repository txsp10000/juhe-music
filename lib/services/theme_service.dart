import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

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
      final rawValue = await Isolate.run(() => _extractCoverColor(bytes));
      if (rawValue == null || generation != _coverGeneration) return;

      final raw = Color(rawValue);
      if (generation != _coverGeneration) return;

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

  static void reset() {
    invalidateCover();
    accentColor.value = AppDesignTokens.lyricWhite;
    bgHint.value = AppDesignTokens.queueBackground;
  }
}

int? _extractCoverColor(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
    return null;
  }

  final source = _resizeForPalette(decoded);
  final buckets = <int, _ColorBucket>{};
  _ColorBucket? dominant;

  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final pixel = source.getPixel(x, y);
      final alpha = pixel.a.toInt();
      if (alpha < 32) continue;

      final red = pixel.r.toInt();
      final green = pixel.g.toInt();
      final blue = pixel.b.toInt();
      final key = (red >> 3) << 10 | (green >> 3) << 5 | (blue >> 3);
      final bucket = buckets.putIfAbsent(key, _ColorBucket.new);
      bucket.add(red, green, blue);
      if (dominant == null || bucket.count > dominant.count) {
        dominant = bucket;
      }
    }
  }

  if (buckets.isEmpty) return null;

  _ColorCandidate? selected;
  for (final bucket in buckets.values) {
    final candidate = bucket.toCandidate();
    if (candidate.saturation < 0.08 ||
        candidate.lightness < 0.10 ||
        candidate.lightness > 0.90) {
      continue;
    }
    if (selected == null || candidate.score > selected.score) {
      selected = candidate;
    }
  }

  return (selected ?? dominant?.toCandidate())?.argb;
}

img.Image _resizeForPalette(img.Image decoded) {
  const maxDimension = 64;
  if (decoded.width <= maxDimension && decoded.height <= maxDimension) {
    return decoded;
  }

  if (decoded.width >= decoded.height) {
    return img.copyResize(decoded, width: maxDimension);
  }
  return img.copyResize(decoded, height: maxDimension);
}

class _ColorBucket {
  int count = 0;
  int redTotal = 0;
  int greenTotal = 0;
  int blueTotal = 0;

  void add(int red, int green, int blue) {
    count++;
    redTotal += red;
    greenTotal += green;
    blueTotal += blue;
  }

  _ColorCandidate toCandidate() {
    final red = (redTotal / count).round().clamp(0, 255);
    final green = (greenTotal / count).round().clamp(0, 255);
    final blue = (blueTotal / count).round().clamp(0, 255);
    final hsl = _rgbToHsl(red, green, blue);

    final lightnessWeight = 1 - (hsl.lightness - 0.50).abs().clamp(0.0, 0.50);
    final saturationWeight = 1 - (hsl.saturation - 0.32).abs().clamp(0.0, 0.68);
    final score = math.sqrt(count) * lightnessWeight * saturationWeight;
    return _ColorCandidate(
      0xFF000000 | red << 16 | green << 8 | blue,
      hsl.saturation,
      hsl.lightness,
      score,
    );
  }
}

class _ColorCandidate {
  final int argb;
  final double saturation;
  final double lightness;
  final double score;

  const _ColorCandidate(
    this.argb,
    this.saturation,
    this.lightness,
    this.score,
  );
}

class _HslParts {
  final double saturation;
  final double lightness;

  const _HslParts(this.saturation, this.lightness);
}

_HslParts _rgbToHsl(int red, int green, int blue) {
  final r = red / 255.0;
  final g = green / 255.0;
  final b = blue / 255.0;
  final maxChannel = math.max(r, math.max(g, b));
  final minChannel = math.min(r, math.min(g, b));
  final lightness = (maxChannel + minChannel) / 2.0;

  if (maxChannel == minChannel) {
    return _HslParts(0, lightness);
  }

  final delta = maxChannel - minChannel;
  final saturation = lightness > 0.5
      ? delta / (2.0 - maxChannel - minChannel)
      : delta / (maxChannel + minChannel);
  return _HslParts(saturation, lightness);
}
