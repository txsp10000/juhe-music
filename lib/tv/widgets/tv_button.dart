import 'package:flutter/material.dart';

import '../tv_layout_metrics.dart';
import '../tv_tokens.dart';
import 'tv_focus_card.dart';

class TvButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final bool primary;
  final bool compact;
  final bool alwaysShowLabel;

  const TvButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.onKeyEvent,
    this.primary = false,
    this.compact = false,
    this.alwaysShowLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final iconOnly = compact || (!alwaysShowLabel && metrics.isCompact);
    return Semantics(
      button: true,
      label: label,
      enabled: onTap != null,
      excludeSemantics: true,
      child: TvFocusCard(
        onTap: onTap,
        autofocus: autofocus,
        focusNode: focusNode,
        onKeyEvent: onKeyEvent,
        radius: iconOnly
            ? metrics.value(18, minimum: 12)
            : metrics.value(999, minimum: 18),
        focusedScale: 1.04,
        color: Colors.black.withValues(alpha: 0.20),
        borderColor: Colors.white.withValues(alpha: 0.10),
        padding: EdgeInsets.symmetric(
          horizontal: metrics.value(iconOnly ? 20 : 28, minimum: 12),
          vertical: metrics.value(iconOnly ? 14 : 18, minimum: 9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: primary ? TvTokens.accent : TvTokens.text,
              size: metrics.value(iconOnly ? 34 : 32, minimum: 22),
            ),
            if (!iconOnly) ...[
              SizedBox(width: metrics.value(12, minimum: 6)),
              Text(
                label,
                style: TvTokens.body(
                  size: metrics.font(26),
                  weight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
