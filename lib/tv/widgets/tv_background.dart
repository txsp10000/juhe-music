import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import '../../theme/app_design_tokens.dart';

/// A lightweight color-only background which follows the active cover palette.
class TvBackground extends StatelessWidget {
  final Widget child;

  const TvBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeService.bgHint,
      builder: (context, bgHint, _) => TweenAnimationBuilder<Color?>(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        tween: ColorTween(end: bgHint),
        builder: (context, color, child) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppDesignTokens.albumWashGradient(color ?? bgHint),
          ),
          child: child,
        ),
        child: child,
      ),
    );
  }
}
