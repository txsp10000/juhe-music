import 'package:flutter/material.dart';

import '../tv_layout_metrics.dart';
import '../tv_tokens.dart';
import 'tv_focus_card.dart';

class TvQrCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? qr;

  const TvQrCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.qr,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    return Container(
      decoration: BoxDecoration(
        color: TvTokens.panel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(metrics.value(32, minimum: 18)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: EdgeInsets.all(metrics.value(28, minimum: 16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TvTokens.title(size: metrics.font(32)),
                ),
                SizedBox(height: metrics.value(10, minimum: 6)),
                Text(
                  subtitle,
                  style: TvTokens.body(
                      size: metrics.font(20), color: TvTokens.muted),
                ),
              ],
            ),
          ),
          SizedBox(width: metrics.value(22, minimum: 12)),
          TvFocusCard(
            onTap: () {},
            radius: metrics.value(18, minimum: 12),
            color: TvTokens.panelSoft,
            child: SizedBox(
              width: metrics.value(164, minimum: 120),
              height: metrics.value(164, minimum: 120),
              child: qr ?? _placeholder(metrics),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(TvLayoutMetrics metrics) {
    return Container(
      color: TvTokens.background,
      padding: EdgeInsets.all(metrics.value(14, minimum: 10)),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 49,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemBuilder: (_, index) => DecoratedBox(
          decoration: BoxDecoration(
            color: index % 3 == 0 ? TvTokens.focus : TvTokens.text,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
