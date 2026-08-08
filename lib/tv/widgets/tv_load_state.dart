import 'package:flutter/material.dart';

import '../tv_layout_metrics.dart';
import '../tv_tokens.dart';
import 'tv_pill_button.dart';

class TvLoadState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const TvLoadState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: metrics.value(720, minimum: 420)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: TvTokens.muted, size: metrics.value(64, minimum: 40)),
            SizedBox(height: metrics.value(18, minimum: 10)),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TvTokens.title(size: metrics.font(32)),
            ),
            SizedBox(height: metrics.value(10, minimum: 6)),
            Text(
              message,
              textAlign: TextAlign.center,
              style:
                  TvTokens.body(size: metrics.font(22), color: TvTokens.muted),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: metrics.value(22, minimum: 12)),
              TvPillButton(
                label: actionLabel!,
                icon: Icons.refresh_rounded,
                autofocus: true,
                onTap: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
