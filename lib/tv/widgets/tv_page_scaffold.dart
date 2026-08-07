import 'package:flutter/material.dart';

import '../tv_layout_metrics.dart';
import '../tv_tokens.dart';
import 'tv_background.dart';

class TvPageScaffold extends StatelessWidget {
  final Widget child;

  const TvPageScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    return Scaffold(
      backgroundColor: TvTokens.background,
      body: TvBackground(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              metrics.edge,
              metrics.topInset,
              metrics.edge,
              metrics.bottomInset,
            ),
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
