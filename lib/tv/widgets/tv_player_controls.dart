import 'package:flutter/material.dart';

import '../tv_layout_metrics.dart';
import 'tv_button.dart';

class TvPlayerControls extends StatelessWidget {
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onFavorite;
  final VoidCallback onQueue;
  final bool isPlaying;
  final bool isFavorite;
  final FocusNode? queueFocusNode;

  const TvPlayerControls({
    super.key,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onFavorite,
    required this.onQueue,
    required this.isPlaying,
    required this.isFavorite,
    this.queueFocusNode,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final playIcon = isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
    final playLabel = isPlaying ? '暂停' : '播放';
    final favoriteIcon =
        isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded;
    final items = [
      (Icons.skip_previous_rounded, '上一首', onPrevious, false, null),
      (playIcon, playLabel, onPlayPause, false, null),
      (Icons.skip_next_rounded, '下一首', onNext, false, null),
      (favoriteIcon, '点收藏', onFavorite, isFavorite, null),
      (Icons.list_alt_rounded, '队列', onQueue, false, queueFocusNode),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          TvButton(
            autofocus: false,
            focusNode: items[index].$5,
            icon: items[index].$1,
            label: items[index].$2,
            onTap: items[index].$3,
            primary: items[index].$4,
            compact: true,
          ),
          if (index < items.length - 1)
            SizedBox(width: metrics.value(18, minimum: 8)),
        ],
      ],
    );
  }
}
