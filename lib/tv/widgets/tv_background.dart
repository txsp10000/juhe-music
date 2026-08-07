import 'package:flutter/material.dart';

import '../../services/theme_service.dart';

/// Lightweight static background for low-memory TVs.
///
/// Cover palette extraction is intentionally disabled here: quantizing an
/// image on the Dart UI isolate can delay remote-control input for seconds on
/// older 32-bit TV hardware.
class TvBackground extends StatelessWidget {
  final Widget child;

  const TvBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeService.bgHint.value.withValues(alpha: 0.92),
            ThemeService.bgHint.value.withValues(alpha: 0.58),
            const Color(0xFF080D15),
          ],
        ),
      ),
      child: child,
    );
  }
}
