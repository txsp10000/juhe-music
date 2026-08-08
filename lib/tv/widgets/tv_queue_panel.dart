import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../../services/player_service.dart';
import '../tv_layout_metrics.dart';
import '../tv_tokens.dart';
import 'tv_focus_card.dart';

class TvQueuePanel extends StatefulWidget {
  final List<Song> songs;
  final int currentIndex;
  final Future<void> Function(int index) onPlay;
  final FocusNode? currentFocusNode;
  final Color backgroundColor;

  const TvQueuePanel({
    super.key,
    required this.songs,
    required this.currentIndex,
    required this.onPlay,
    this.currentFocusNode,
    this.backgroundColor = TvTokens.background,
  });

  @override
  State<TvQueuePanel> createState() => _TvQueuePanelState();
}

class _TvQueuePanelState extends State<TvQueuePanel> {
  final ScrollController _scrollController = ScrollController();
  double _itemExtent = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _revealCurrent() {
    if (!mounted || !_scrollController.hasClients || widget.songs.isEmpty) {
      return;
    }
    final target = widget.currentIndex.clamp(0, widget.songs.length - 1);
    final offset = ((target - 2).clamp(0, widget.songs.length) * _itemExtent)
        .clamp(0.0, _scrollController.position.maxScrollExtent)
        .toDouble();
    _scrollController.jumpTo(offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.currentFocusNode?.canRequestFocus == true) {
        widget.currentFocusNode!.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    _itemExtent = metrics.value(84, minimum: 54);
    final targetIndex = widget.songs.isEmpty
        ? -1
        : widget.currentIndex.clamp(0, widget.songs.length - 1);
    return Container(
      width: metrics.value(720, minimum: 360),
      margin: EdgeInsets.fromLTRB(
        metrics.value(18, minimum: 10),
        metrics.topInset,
        metrics.edge,
        metrics.bottomInset,
      ),
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(metrics.value(32, minimum: 18)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: EdgeInsets.all(metrics.value(28, minimum: 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前播放列表 (${widget.songs.length})',
              style: TvTokens.title(size: metrics.font(34)),
            ),
            SizedBox(height: metrics.value(20, minimum: 10)),
            Expanded(
              child: widget.songs.isEmpty
                  ? Center(
                      child: Text(
                        '当前没有播放内容。',
                        style: TvTokens.body(
                            size: metrics.font(24), color: TvTokens.muted),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemExtent: _itemExtent,
                      itemCount: widget.songs.length,
                      itemBuilder: (_, index) {
                        final song = widget.songs[index];
                        final current = index == widget.currentIndex ||
                            PlayerService().currentSong?.id == song.id;
                        return Padding(
                          padding: EdgeInsets.only(
                              bottom: metrics.value(8, minimum: 5)),
                          child: TvFocusCard(
                            focusNode: index == targetIndex
                                ? widget.currentFocusNode
                                : null,
                            onTap: () => widget.onPlay(index),
                            radius: metrics.value(18, minimum: 10),
                            padding: EdgeInsets.symmetric(
                              horizontal: metrics.value(18, minimum: 10),
                              vertical: metrics.value(10, minimum: 7),
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
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                          color: TvTokens.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
