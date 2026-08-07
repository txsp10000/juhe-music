import 'package:flutter/material.dart';

import '../tv_layout_metrics.dart';
import '../tv_tokens.dart';

class TvSectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final TextAlign titleAlign;

  const TvSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(0),
    this.titleAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Text(
              title,
              textAlign: titleAlign,
              style: TvTokens.title(size: metrics.font(30)),
            ),
          ),
          SizedBox(height: metrics.value(18, minimum: 10)),
          Expanded(child: child),
        ],
      ),
    );
  }
}
