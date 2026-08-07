import 'package:flutter/material.dart';

import '../../api/music_api.dart';
import '../../data/categories.dart';
import '../../services/player_service.dart';
import '../tv_layout_metrics.dart';
import '../tv_routes.dart';
import '../tv_tokens.dart';
import '../widgets/tv_focus_card.dart';
import '../widgets/tv_page_scaffold.dart';

class TvPlaylistPage extends StatefulWidget {
  const TvPlaylistPage({super.key});

  @override
  State<TvPlaylistPage> createState() => _TvPlaylistPageState();
}

class _TvPlaylistPageState extends State<TvPlaylistPage> {
  final _player = PlayerService();
  String? _loadingMessage;

  Future<void> _playPlaylist(PlaylistInfo playlist) async {
    setState(() => _loadingMessage = '正在加载「${playlist.name}」');
    try {
      final songs = await MusicApi.getPlaylist(playlist.id);
      if (!mounted || songs.isEmpty) return;
      _player.playlist
        ..clear()
        ..addAll(songs);
      await _player.playAt(0);
      if (!mounted) return;
      TvRoutes.requestHomeQueueFocus();
      Navigator.of(context).pushReplacementNamed(TvRoutes.home);
    } catch (_) {
      // Keep the current screen and focus so the user can retry.
    } finally {
      if (mounted) setState(() => _loadingMessage = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final playlists =
        playlistCategories.entries.expand((entry) => entry.value).toList();
    return Stack(
      children: [
        TvPageScaffold(
          child: ExcludeFocus(
            excluding: _loadingMessage != null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '歌单',
                  style: TvTokens.body(
                      size: metrics.font(22), color: TvTokens.muted),
                ),
                SizedBox(height: metrics.value(20, minimum: 10)),
                Text('发现歌单', style: TvTokens.hero(size: metrics.font(48))),
                SizedBox(height: metrics.value(10, minimum: 6)),
                Text(
                  '选择一个歌单开始播放',
                  style: TvTokens.body(
                      size: metrics.font(22), color: TvTokens.muted),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: metrics.sectionGap),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GridView.builder(
                        padding: EdgeInsets.all(metrics.value(14, minimum: 10)),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              metrics.gridColumnCount(constraints.maxWidth),
                          mainAxisSpacing: metrics.value(18, minimum: 10),
                          crossAxisSpacing: metrics.value(18, minimum: 10),
                          childAspectRatio: metrics.isCompact ? 1.25 : 1.18,
                        ),
                        itemCount: playlists.length + 1,
                        itemBuilder: (_, index) {
                          if (index == 0) {
                            return _textCard(
                              icon: Icons.favorite_rounded,
                              title: '我的收藏',
                              onTap: () => Navigator.of(context)
                                  .pushNamed(TvRoutes.favorites),
                              autofocus: false,
                              activeColor: TvTokens.danger,
                            );
                          }
                          return _playlistCard(playlists[index - 1]);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_loadingMessage != null)
          Positioned.fill(
            child: Material(
              color: Colors.black.withValues(alpha: 0.34),
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: metrics.value(34, minimum: 20),
                    vertical: metrics.value(24, minimum: 16),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.74),
                    borderRadius:
                        BorderRadius.circular(metrics.value(26, minimum: 16)),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: metrics.value(34, minimum: 22),
                        height: metrics.value(34, minimum: 22),
                        child: const CircularProgressIndicator(
                            color: TvTokens.focus),
                      ),
                      SizedBox(width: metrics.value(18, minimum: 10)),
                      Text(_loadingMessage!,
                          style: TvTokens.title(size: metrics.font(26))),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _playlistCard(PlaylistInfo item) {
    return _textCard(
      icon: _iconForPlaylist(item),
      title: item.name,
      onTap: () => _playPlaylist(item),
    );
  }

  Widget _textCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool autofocus = false,
    Color activeColor = TvTokens.text,
  }) {
    final metrics = TvLayoutMetrics.of(context);
    return TvFocusCard(
      autofocus: autofocus,
      onTap: onTap,
      radius: metrics.value(22, minimum: 12),
      padding: EdgeInsets.all(metrics.value(18, minimum: 10)),
      color: Colors.black.withValues(alpha: 0.16),
      borderColor: Colors.white.withValues(alpha: 0.08),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: activeColor, size: metrics.value(34, minimum: 24)),
          SizedBox(height: metrics.value(12, minimum: 6)),
          Text(
            title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TvTokens.title(size: metrics.font(25)),
          ),
        ],
      ),
    );
  }

  IconData _iconForPlaylist(PlaylistInfo playlist) {
    if (playlist.name.contains('热') || playlist.name.contains('榜')) {
      return Icons.leaderboard_rounded;
    }
    if (playlist.name.contains('新')) return Icons.fiber_new_rounded;
    if (playlist.name.contains('欧美') ||
        playlist.name.contains('韩') ||
        playlist.name.contains('日') ||
        playlist.name.contains('UK') ||
        playlist.name.contains('Billboard')) {
      return Icons.language_rounded;
    }
    if (playlist.name.contains('电音')) return Icons.bolt_rounded;
    if (playlist.name.contains('古典')) return Icons.piano_rounded;
    if (playlist.name.contains('ACG')) return Icons.auto_awesome_rounded;
    return Icons.queue_music_rounded;
  }
}
