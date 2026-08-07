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

  double get edge => value(36, minimum: 18);

  double get topInset => value(24, minimum: 12);

  double get bottomInset => value(24, minimum: 12);

  double get navigationWidth => value(74, minimum: 48);

  double get navigationGap => value(50, minimum: 18);

  double get pageGap => value(18, minimum: 10);

  double get sectionGap => value(24, minimum: 12);

  int gridColumnCount(double availableWidth) {
    final minimumCardWidth = value(240, minimum: 160);
    return (availableWidth / (minimumCardWidth + pageGap)).floor().clamp(2, 5);
  }
}
