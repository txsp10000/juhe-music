import 'package:flutter/material.dart';

import '../tv_layout_metrics.dart';
import 'tv_button.dart';

class TvPlayerControls extends StatelessWidget {
  final VoidCallback onPrevious;
  final VoidCallback onRewind;
  final VoidCallback onPlayPause;
  final VoidCallback onForward;
  final VoidCallback onNext;
  final VoidCallback onFavorite;
  final VoidCallback onQueue;
  final VoidCallback onQuality;
  final VoidCallback onRelatedSearch;
  final bool isPlaying;
  final bool isFavorite;
  final String qualityLabel;
  final FocusNode? queueFocusNode;
  final FocusNode? qualityFocusNode;
  final FocusNode? relatedSearchFocusNode;

  const TvPlayerControls({
    super.key,
    required this.onPrevious,
    required this.onRewind,
    required this.onPlayPause,
    required this.onForward,
    required this.onNext,
    required this.onFavorite,
    required this.onQueue,
    required this.onQuality,
    required this.onRelatedSearch,
    required this.isPlaying,
    required this.isFavorite,
    required this.qualityLabel,
    this.queueFocusNode,
    this.qualityFocusNode,
    this.relatedSearchFocusNode,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final playIcon = isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
    final playLabel = isPlaying ? '暂停' : '播放';
    final favoriteIcon =
        isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded;
    final primaryItems = [
      (Icons.skip_previous_rounded, '上一首', onPrevious, false, null),
      (Icons.replay_10_rounded, '快退10秒', onRewind, false, null),
      (playIcon, playLabel, onPlayPause, false, null),
      (Icons.forward_10_rounded, '快进10秒', onForward, false, null),
      (Icons.skip_next_rounded, '下一首', onNext, false, null),
    ];
    final actionItems = [
      (favoriteIcon, isFavorite ? '取消收藏' : '收藏', onFavorite, isFavorite, null),
      (Icons.list_alt_rounded, '队列', onQueue, false, queueFocusNode),
      (
        Icons.high_quality_rounded,
        qualityLabel,
        onQuality,
        true,
        qualityFocusNode
      ),
      (
        Icons.manage_search_rounded,
        '同名或歌手',
        onRelatedSearch,
        false,
        relatedSearchFocusNode
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buttonRow(metrics, primaryItems),
        SizedBox(height: metrics.value(10, minimum: 6)),
        _buttonRow(metrics, actionItems),
      ],
    );
  }

  Widget _buttonRow(
    TvLayoutMetrics metrics,
    List<(IconData, String, VoidCallback, bool, FocusNode?)> items,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          TvButton(
            focusNode: items[index].$5,
            icon: items[index].$1,
            label: items[index].$2,
            onTap: items[index].$3,
            primary: items[index].$4,
            compact: true,
          ),
          if (index < items.length - 1)
            SizedBox(width: metrics.value(12, minimum: 6)),
        ],
      ],
    );
  }
}
