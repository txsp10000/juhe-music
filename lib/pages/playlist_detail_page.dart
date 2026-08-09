import 'dart:async';

import 'package:flutter/material.dart';

import '../api/music_api.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/glass_panel.dart';
import '../widgets/music_list_tile.dart';

class PlaylistDetailPage extends StatefulWidget {
  final PlaylistInfo playlist;
  final bool fromPlayer;
  final VoidCallback? onShowPlayer;

  const PlaylistDetailPage({
    super.key,
    required this.playlist,
    this.fromPlayer = false,
    this.onShowPlayer,
  });

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  final _player = PlayerService();
  Color _bgHint = AppDesignTokens.queueBackground;
  List<Song> _songs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _onThemeChange();
    ThemeService.bgHint.addListener(_onThemeChange);
  }

  void _onThemeChange() {
    if (mounted) setState(() => _bgHint = ThemeService.bgHint.value);
  }

  @override
  void dispose() {
    ThemeService.bgHint.removeListener(_onThemeChange);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final songs = await MusicApi.getPlaylistTracks(widget.playlist.id);
      if (mounted) setState(() => _songs = songs);
    } catch (_) {
      if (mounted) setState(() => _error = '歌单加载失败，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _playAt(int index) {
    _player.replaceQueue(_songs);
    unawaited(_player.playAt(index));
    if (widget.fromPlayer) {
      Navigator.popUntil(context, (route) => route.isFirst);
    } else if (widget.onShowPlayer != null) {
      widget.onShowPlayer!();
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = AppDesignTokens.lyricWhite;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MusicScaffoldBackground(
        bgHint: _bgHint,
        accent: accent,
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Row(children: [
                IconOrbButton(
                  icon: Icons.arrow_back_rounded,
                  accent: accent,
                  size: 42,
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.playlist.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppDesignTokens.title(size: 22)),
                      const SizedBox(height: 4),
                      Text(_loading ? '正在加载歌曲' : '${_songs.length} 首歌曲',
                          style: AppDesignTokens.caption(
                              color: AppDesignTokens.lyricWhite
                                  .withValues(alpha: 0.74))),
                    ],
                  ),
                ),
              ]),
            ),
            Expanded(child: _body(accent)),
          ]),
        ),
      ),
    );
  }

  Widget _body(Color accent) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: accent));
    }
    if (_error != null) {
      return MusicEmptyState(
        accent: accent,
        icon: Icons.wifi_off_rounded,
        title: '歌单加载失败',
        message: _error!,
        action: TextButton(onPressed: _load, child: const Text('重新加载')),
      );
    }
    if (_songs.isEmpty) {
      return MusicEmptyState(
          accent: accent,
          icon: Icons.queue_music_rounded,
          title: '歌单是空的',
          message: '这个歌单暂时没有可播放的歌曲。');
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: _songs.length,
      itemBuilder: (_, index) => MusicListTile(
        song: _songs[index],
        index: index,
        isCurrent: _player.currentSong?.id == _songs[index].id,
        accent: accent,
        onTap: () => _playAt(index),
      ),
    );
  }
}
