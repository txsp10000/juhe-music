import 'dart:async';

import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/glass_panel.dart';
import '../widgets/music_list_tile.dart';
import '../widgets/swipe_action_cell.dart';

class PlaylistPage extends StatefulWidget {
  final bool fromPlayer;
  const PlaylistPage({super.key, this.fromPlayer = false});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  final _player = PlayerService();
  final ScrollController _scrollController = ScrollController();
  Color _accent = AppDesignTokens.lyricWhite;
  Color _bgHint = AppDesignTokens.inkBlack;

  @override
  void initState() {
    super.initState();
    _player.addSongChangeListener(_onSongChange);
    _onThemeChange();
    ThemeService.accentColor.addListener(_onThemeChange);
    ThemeService.bgHint.addListener(_onThemeChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPlaying());
  }

  void _onThemeChange() {
    if (mounted) {
      setState(() {
        _accent =
            AppDesignTokens.readableAccent(ThemeService.accentColor.value);
        _bgHint = ThemeService.bgHint.value;
      });
    }
  }

  void _scrollToPlaying() {
    final idx = _player.currentIndex;
    if (idx > 0 && _scrollController.hasClients) {
      final offset =
          (idx * 76.0).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(offset,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _onSongChange(Song _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _player.removeSongChangeListener(_onSongChange);
    ThemeService.accentColor.removeListener(_onThemeChange);
    ThemeService.bgHint.removeListener(_onThemeChange);
    super.dispose();
  }

  void _playAt(int index) {
    if (_player.currentSong?.id != _player.playlist[index].id) {
      unawaited(_player.playAt(index));
    } else if (!_player.isPlaying) {
      unawaited(_player.play());
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final songs = _player.playlist;
    final currentIdx = _player.currentIndex;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MusicScaffoldBackground(
        bgHint: _bgHint,
        accent: _accent,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(songs.length, currentIdx),
              Expanded(
                child: songs.isEmpty
                    ? MusicEmptyState(
                        accent: _accent,
                        icon: Icons.queue_music_rounded,
                        title: '队列是空的',
                        message: '去搜索或播放收藏里的歌曲。')
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(top: 4, bottom: 24),
                        itemCount: songs.length,
                        itemBuilder: (_, i) {
                          final s = songs[i];
                          final isCurrent = i == currentIdx;
                          return SwipeActionCell(
                            actionLabel: '删除',
                            actionColor: AppDesignTokens.danger,
                            onAction: () {
                              _player.removeAt(i).then((_) {
                                if (mounted) setState(() {});
                              });
                            },
                            child: MusicListTile(
                                song: s,
                                index: i,
                                isCurrent: isCurrent,
                                accent: _accent,
                                onTap: () => _playAt(i),
                                margin: EdgeInsets.zero),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int count, int currentIdx) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: [
          IconOrbButton(
              icon: Icons.arrow_back_rounded,
              accent: _accent,
              size: 42,
              onTap: () => Navigator.pop(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('播放队列', style: AppDesignTokens.title(size: 24)),
                const SizedBox(height: 4),
                Text(
                    count == 0
                        ? '没有歌曲'
                        : '${currentIdx + 1}/$count · 跟着当前歌曲继续播放',
                    style: AppDesignTokens.caption(color: _accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
