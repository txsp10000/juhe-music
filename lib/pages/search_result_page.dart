import 'dart:async';

import 'package:flutter/material.dart';

import '../api/music_api.dart';
import '../models/song.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../utils/toast.dart';
import '../widgets/glass_panel.dart';
import '../widgets/music_list_tile.dart';
import 'playlist_detail_page.dart';

enum _SearchType { tracks, playlists }

class SearchResultPage extends StatefulWidget {
  final String keyword;
  final bool fromPlayer;
  final VoidCallback? onShowPlayer;

  const SearchResultPage(
      {super.key,
      required this.keyword,
      this.fromPlayer = false,
      this.onShowPlayer});

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  final _player = PlayerService();
  Color _bgHint = AppDesignTokens.queueBackground;
  _SearchType _type = _SearchType.tracks;
  List<Song> _songs = [];
  List<PlaylistInfo> _playlists = [];
  final Set<String> _favoriteIds = {};
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _trackCursor = '0';
  String? _playlistCursor = '0';
  bool _tracksHaveMore = true;
  bool _playlistsHaveMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _loadFavorites();
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

  Future<void> _loadFavorites() async {
    final songs = await FavoritesService.load();
    _favoriteIds.addAll(songs.map((song) => song.id));
    if (mounted) setState(() {});
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        MusicApi.searchTracks(widget.keyword),
        MusicApi.searchPlaylists(widget.keyword)
      ]);
      if (!mounted) return;
      final tracks = results[0] as SearchTracksResult;
      final playlists = results[1] as SearchPlaylistsResult;
      setState(() {
        _songs = tracks.songs;
        _playlists = playlists.playlists;
        _trackCursor = tracks.nextCursor;
        _playlistCursor = playlists.nextCursor;
        _tracksHaveMore = tracks.hasMore && tracks.nextCursor != null;
        _playlistsHaveMore = playlists.hasMore && playlists.nextCursor != null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '搜索失败，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final isTracks = _type == _SearchType.tracks;
    final cursor = isTracks ? _trackCursor : _playlistCursor;
    final hasMore = isTracks ? _tracksHaveMore : _playlistsHaveMore;
    if (!hasMore || cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      if (isTracks) {
        final result = await MusicApi.searchTracks(widget.keyword,
            cursor: int.tryParse(cursor) ?? 0);
        if (mounted) {
          setState(() {
            _songs.addAll(result.songs);
            _trackCursor = result.nextCursor;
            _tracksHaveMore = result.hasMore && result.nextCursor != null;
          });
        }
      } else {
        final result = await MusicApi.searchPlaylists(widget.keyword,
            cursor: int.tryParse(cursor) ?? 0);
        if (mounted) {
          setState(() {
            _playlists.addAll(result.playlists);
            _playlistCursor = result.nextCursor;
            _playlistsHaveMore = result.hasMore && result.nextCursor != null;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        Toast.show(context, '加载更多失败，上滑可重试');
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _playAt(int index) {
    _player.replaceQueue(_songs);
    unawaited(_player.playAt(index));
    if (widget.fromPlayer) {
      Navigator.pop(context);
    } else if (widget.onShowPlayer != null) {
      widget.onShowPlayer!();
      Navigator.pop(context);
    }
  }

  Future<void> _toggleFavorite(Song song) async {
    if (_favoriteIds.remove(song.id)) {
      await FavoritesService.remove(song);
    } else {
      _favoriteIds.add(song.id);
      await FavoritesService.save(song);
    }
    if (mounted) setState(() {});
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
          _header(accent),
          _tabs(accent),
          Expanded(child: _body(accent)),
        ])),
      ),
    );
  }

  Widget _header(Color accent) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
        child: Row(children: [
          IconOrbButton(
              icon: Icons.arrow_back_rounded,
              accent: accent,
              size: 42,
              onTap: () => Navigator.pop(context)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(widget.keyword,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppDesignTokens.title(size: 22)),
                const SizedBox(height: 4),
                Text(
                    _type == _SearchType.tracks
                        ? '${_songs.length} 首歌曲'
                        : '${_playlists.length} 个歌单',
                    style: AppDesignTokens.caption(
                        color: AppDesignTokens.lyricWhite
                            .withValues(alpha: 0.74))),
              ])),
        ]),
      );

  Widget _tabs(Color accent) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Row(children: [
          _tab('歌曲', _SearchType.tracks, accent),
          const SizedBox(width: 14),
          _tab('歌单', _SearchType.playlists, accent),
        ]),
      );

  Widget _tab(String label, _SearchType type, Color accent) {
    final selected = _type == type;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _type = type),
      child: SizedBox(
        width: 56,
        height: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: AppDesignTokens.body(
                size: 17,
                color: selected
                    ? AppDesignTokens.warmWhite
                    : AppDesignTokens.warmWhite.withValues(alpha: 0.42),
                weight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: selected ? 16 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
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
          title: '搜索失败',
          message: _error!,
          action:
              TextButton(onPressed: _loadInitial, child: const Text('重新搜索')));
    }
    final empty =
        _type == _SearchType.tracks ? _songs.isEmpty : _playlists.isEmpty;
    if (empty) {
      return MusicEmptyState(
          accent: accent,
          icon: Icons.search_off_rounded,
          title: '没有找到结果',
          message: '换个关键词试试。');
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 100) {
          unawaited(_loadMore());
        }
        return false;
      },
      child: _type == _SearchType.tracks
          ? _songList(accent)
          : _playlistList(accent),
    );
  }

  Widget _songList(Color accent) => ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: _songs.length + (_loadingMore ? 1 : 0),
        itemBuilder: (_, index) {
          if (index == _songs.length) {
            return const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()));
          }
          final song = _songs[index];
          return MusicListTile(
              song: song,
              index: index,
              isCurrent: _player.currentSong?.id == song.id,
              accent: accent,
              onTap: () => _playAt(index),
              trailing: IconButton(
                  onPressed: () => _toggleFavorite(song),
                  icon: Icon(_favoriteIds.contains(song.id)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded)));
        },
      );

  Widget _playlistList(Color accent) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        itemCount: _playlists.length + (_loadingMore ? 1 : 0),
        itemBuilder: (_, index) {
          if (index == _playlists.length) {
            return const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()));
          }
          final playlist = _playlists[index];
          return GestureDetector(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PlaylistDetailPage(
                        playlist: playlist,
                        fromPlayer: widget.fromPlayer,
                        onShowPlayer: widget.onShowPlayer))),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                        width: 64,
                        height: 64,
                        child: playlist.coverUrl.isEmpty
                            ? Icon(Icons.queue_music_rounded, color: accent)
                            : Image.network(playlist.coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                    Icons.queue_music_rounded,
                                    color: accent)))),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(playlist.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppDesignTokens.body(
                              size: 16, weight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text(
                          '${playlist.trackCount} 首${playlist.owner.isEmpty ? '' : ' · ${playlist.owner}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppDesignTokens.caption(
                              color: AppDesignTokens.quietGrey)),
                    ])),
                const Icon(Icons.chevron_right_rounded),
              ]),
            ),
          );
        },
      );
}
