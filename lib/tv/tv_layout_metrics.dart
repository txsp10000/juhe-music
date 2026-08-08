import 'package:flutter/material.dart';

class TvLayoutMetrics {
  final Size size;
  final EdgeInsets safePadding;
  final double scale;

  const TvLayoutMetrics._({
    required this.size,
    required this.safePadding,
    required this.scale,
  });

  factory TvLayoutMetrics.of(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableWidth =
        mediaQuery.size.width - mediaQuery.padding.horizontal;
    final availableHeight =
        mediaQuery.size.height - mediaQuery.padding.vertical;
    final rawScale = (availableWidth / 1920) < (availableHeight / 1080)
        ? availableWidth / 1920
        : availableHeight / 1080;
    return TvLayoutMetrics._(
      size: Size(availableWidth, availableHeight),
      safePadding: mediaQuery.padding,
      scale: rawScale.clamp(0.62, 1.0).toDouble(),
    );
  }

  bool get isCompact => size.width < 1280 || size.height < 760;

  bool get isNarrow => size.width < 980;

  double value(double base, {double minimum = 0}) {
    return (base * scale).clamp(minimum, double.infinity).toDouble();
  }

  double font(double base) => value(base, minimum: base * 0.62);

  /// TV content must remain visible on panels that still apply overscan.
  double get edge => (size.width * 0.05).clamp(36.0, 96.0).toDouble();

  double get topInset => (size.height * 0.05).clamp(24.0, 54.0).toDouble();

  double get bottomInset => (size.height * 0.05).clamp(24.0, 54.0).toDouble();

  double get navigationWidth => value(74, minimum: 48);

  double get navigationGap => value(50, minimum: 18);

  double get pageGap => value(18, minimum: 10);

  double get sectionGap => value(24, minimum: 12);

  int gridColumnCount(double availableWidth) {
    final minimumCardWidth = value(240, minimum: 160);
    return (availableWidth / (minimumCardWidth + pageGap)).floor().clamp(2, 5);
  }
}
