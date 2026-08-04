import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_design_tokens.dart';

class GlassPanel extends StatelessWidget {
  final Widget child;
  final Color accent;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool active;
  final double opacity;
  final Color? color;
  final Clip clipBehavior;
  final bool blur;

  const GlassPanel({
    super.key,
    required this.child,
    required this.accent,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppDesignTokens.cardRadius,
    this.active = false,
    this.opacity = 0.64,
    this.color,
    this.clipBehavior = Clip.antiAlias,
    this.blur = false,
  });

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      padding: padding,
      decoration: AppDesignTokens.glassDecoration(
        accent: accent,
        radius: radius,
        active: active,
        opacity: opacity,
        color: color,
      ),
      child: child,
    );
    if (!blur) return panel;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: clipBehavior,
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: panel),
    );
  }
}

class MusicChip extends StatelessWidget {
  final String label;
  final Color accent;
  final IconData? icon;
  final bool active;
  final VoidCallback? onTap;
  final Color? background;
  final Color? foreground;

  const MusicChip({
    super.key,
    required this.label,
    required this.accent,
    this.icon,
    this.active = false,
    this.onTap,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final bg = background ?? (active ? Colors.white.withOpacity(0.16) : Colors.white.withOpacity(0.08));
    final fg = foreground ?? (active ? AppDesignTokens.lyricWhite : AppDesignTokens.warmWhite.withOpacity(0.82));
    final content = Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 10 : 9, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          Text(label, style: AppDesignTokens.caption(size: 12, color: fg)),
        ],
      ),
    );
    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: content);
  }
}

class IconOrbButton extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final bool active;
  final String? label;
  final double size;
  final Color? background;
  final Color? foreground;

  const IconOrbButton({
    super.key,
    required this.icon,
    required this.accent,
    this.onTap,
    this.active = false,
    this.label,
    this.size = 48,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background ?? (active ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.10)),
      ),
      child: Icon(icon, color: foreground ?? AppDesignTokens.lyricWhite, size: size * 0.48),
    );
    final tappable = GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: button);
    if (label == null) return tappable;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tappable,
        const SizedBox(height: 7),
        Text(label!, style: AppDesignTokens.caption(size: 10, color: AppDesignTokens.quietGrey)),
      ],
    );
  }
}
