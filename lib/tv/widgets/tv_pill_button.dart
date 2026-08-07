import 'package:flutter/material.dart';

import '../tv_layout_metrics.dart';
import '../tv_tokens.dart';
import 'tv_focus_card.dart';

class TvPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool autofocus;
  final bool selected;
  final IconData? icon;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final bool fullWidth;
  final Color? borderColor;

  const TvPillButton({
    super.key,
    required this.label,
    this.onTap,
    this.autofocus = false,
    this.selected = false,
    this.icon,
    this.focusNode,
    this.onKeyEvent,
    this.fullWidth = false,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    return TvFocusCard(
      onTap: onTap,
      autofocus: autofocus,
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      radius: metrics.value(999, minimum: 18),
      focusedScale: 1.04,
      color: selected
          ? TvTokens.focus.withValues(alpha: 0.18)
          : Colors.black.withValues(alpha: 0.14),
      borderColor: borderColor ?? Colors.white.withValues(alpha: 0.22),
      padding: EdgeInsets.symmetric(
        horizontal: metrics.value(26, minimum: 14),
        vertical: metrics.value(16, minimum: 10),
      ),
      child: SizedBox(
        width: fullWidth ? double.infinity : null,
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: metrics.value(26, minimum: 18),
                color: selected ? TvTokens.focus : TvTokens.text,
              ),
              SizedBox(width: metrics.value(10, minimum: 6)),
            ],
            Text(
              label,
              style: TvTokens.body(
                size: metrics.font(24),
                weight: FontWeight.w700,
                color: selected ? TvTokens.focus : TvTokens.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
