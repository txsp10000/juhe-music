import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../../services/player_service.dart';
import '../tv_layout_metrics.dart';
import '../tv_tokens.dart';
import 'tv_focus_card.dart';

class TvSongList extends StatelessWidget {
  final List<Song> songs;
  final String emptyText;
  final Future<void> Function(int index) onPlay;
  final Future<void> Function(int index)? onLongPress;
  final String? title;
  final String? subtitle;
  final bool autofocusFirstItem;
  final bool dense;

  const TvSongList({
    super.key,
    required this.songs,
    required this.emptyText,
    required this.onPlay,
    this.onLongPress,
    this.title,
    this.subtitle,
    this.autofocusFirstItem = true,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final hasHeader = title != null;
    final content = songs.isEmpty
        ? _TvEmptyState(text: emptyText)
        : FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.value(dense ? 14 : 8, minimum: 8),
                vertical: metrics.value(4, minimum: 2),
              ),
              itemCount: songs.length,
              separatorBuilder: (_, __) => SizedBox(
                height: metrics.value(dense ? 6 : 14, minimum: 4),
              ),
              itemBuilder: (_, index) => _TvSongRow(
                song: songs[index],
                index: index,
                autofocus: autofocusFirstItem && index == 0,
                onTap: () => onPlay(index),
                onLongPress:
                    onLongPress == null ? null : () => onLongPress!(index),
                dense: dense,
              ),
            ),
          );

    if (!hasHeader) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title!, style: TvTokens.hero(size: metrics.font(58))),
        if (subtitle != null) ...[
          SizedBox(height: metrics.value(12, minimum: 6)),
          Text(
            subtitle!,
            style: TvTokens.body(size: metrics.font(26), color: TvTokens.muted),
          ),
        ],
        SizedBox(height: metrics.sectionGap),
        Expanded(child: content),
      ],
    );
  }
}

class _TvSongRow extends StatelessWidget {
  final Song song;
  final int index;
  final bool autofocus;
  final VoidCallback onTap;
  final Future<void> Function()? onLongPress;
  final bool dense;

  const _TvSongRow({
    required this.song,
    required this.index,
    required this.autofocus,
    required this.onTap,
    required this.dense,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final current = PlayerService().currentSong?.id == song.id;

    return TvFocusCard(
      autofocus: autofocus,
      onTap: onTap,
      onLongPress: onLongPress,
      radius: metrics.value(dense ? 18 : 24, minimum: 10),
      padding: EdgeInsets.symmetric(
        horizontal: metrics.value(dense ? 16 : 24, minimum: 10),
        vertical: metrics.value(dense ? 10 : 18, minimum: 7),
      ),
      focusedScale: 1,
      color: current
          ? TvTokens.focus.withValues(alpha: 0.14)
          : Colors.black.withValues(alpha: 0.20),
      borderColor: Colors.white.withValues(alpha: 0.06),
      child: Row(
        children: [
          SizedBox(
            width: metrics.value(dense ? 44 : 52, minimum: 28),
            child: Text(
              '${index + 1}'.padLeft(2, '0'),
              style: TvTokens.label(
                size: metrics.font(dense ? 20 : 24),
                color: current ? TvTokens.focus : TvTokens.faint,
              ),
            ),
          ),
          SizedBox(width: metrics.value(dense ? 14 : 18, minimum: 8)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.title(
                    size: metrics.font(dense ? 25 : 30),
                    color: current ? TvTokens.focus : TvTokens.text,
                  ),
                ),
                SizedBox(height: metrics.value(dense ? 3 : 6, minimum: 2)),
                Text(
                  song.singer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TvTokens.body(
                    size: metrics.font(dense ? 18 : 22),
                    color: TvTokens.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TvEmptyState extends StatelessWidget {
  final String text;

  const _TvEmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TvTokens.body(size: metrics.font(30), color: TvTokens.muted),
      ),
    );
  }
}
