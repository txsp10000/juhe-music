import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../../services/player_service.dart';
import '../tv_layout_metrics.dart';
import '../tv_tokens.dart';
import 'tv_focus_card.dart';

class TvQueuePanel extends StatelessWidget {
  final List<Song> songs;
  final int currentIndex;
  final Future<void> Function(int index) onPlay;
  final FocusNode? firstFocusNode;
  final Color backgroundColor;

  const TvQueuePanel({
    super.key,
    required this.songs,
    required this.currentIndex,
    required this.onPlay,
    this.firstFocusNode,
    this.backgroundColor = TvTokens.background,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    return Container(
      width: metrics.value(720, minimum: 360),
      margin: EdgeInsets.all(metrics.value(18, minimum: 10)),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(metrics.value(32, minimum: 18)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: EdgeInsets.all(metrics.value(28, minimum: 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前播放列表 (${songs.length})',
              style: TvTokens.title(size: metrics.font(34)),
            ),
            SizedBox(height: metrics.value(20, minimum: 10)),
            Expanded(
              child: songs.isEmpty
                  ? Center(
                      child: Text(
                        '当前没有播放内容。',
                        style: TvTokens.body(
                            size: metrics.font(24), color: TvTokens.muted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: songs.length,
                      separatorBuilder: (_, __) =>
                          SizedBox(height: metrics.value(8, minimum: 5)),
                      itemBuilder: (_, index) {
                        final song = songs[index];
                        final current = index == currentIndex ||
                            PlayerService().currentSong?.id == song.id;
                        return TvFocusCard(
                          autofocus: index == 0,
                          focusNode: index == 0 ? firstFocusNode : null,
                          onTap: () => onPlay(index),
                          radius: metrics.value(18, minimum: 10),
                          padding: EdgeInsets.symmetric(
                            horizontal: metrics.value(18, minimum: 10),
                            vertical: metrics.value(12, minimum: 8),
                          ),
                          focusedScale: 1,
                          color: current
                              ? TvTokens.focus.withValues(alpha: 0.14)
                              : Colors.black.withValues(alpha: 0.26),
                          borderColor: Colors.white.withValues(alpha: 0.06),
                          child: Row(
                            children: [
                              SizedBox(
                                width: metrics.value(40, minimum: 26),
                                child: Text(
                                  '${index + 1}',
                                  style: TvTokens.label(
                                    size: metrics.font(20),
                                    color: current
                                        ? TvTokens.focus
                                        : TvTokens.muted,
                                  ),
                                ),
                              ),
                              SizedBox(width: metrics.value(14, minimum: 8)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TvTokens.title(
                                        size: metrics.font(24),
                                        color: current
                                            ? TvTokens.focus
                                            : TvTokens.text,
                                      ),
                                    ),
                                    SizedBox(
                                        height: metrics.value(3, minimum: 2)),
                                    Text(
                                      song.singer,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TvTokens.body(
                                          size: metrics.font(17),
                                          color: TvTokens.muted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
