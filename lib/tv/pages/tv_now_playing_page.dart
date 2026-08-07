import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/music_api.dart';
import '../../data/categories.dart';
import '../../models/song.dart';
import '../../services/favorites_service.dart';
import '../../services/player_service.dart';
import '../../services/theme_service.dart';
import '../tv_layout_metrics.dart';
import '../tv_routes.dart';
import '../tv_tokens.dart';
import '../widgets/tv_focus_card.dart';
import '../widgets/tv_page_scaffold.dart';
import '../widgets/tv_pill_button.dart';
import '../widgets/tv_player_controls.dart';
import '../widgets/tv_queue_panel.dart';
import '../widgets/tv_section_card.dart';

class TvNowPlayingPage extends StatefulWidget {
  const TvNowPlayingPage({super.key});

  @override
  State<TvNowPlayingPage> createState() => _TvNowPlayingPageState();
}

class _LrcLine {
  final int timeMs;
  final String text;

  const _LrcLine(this.timeMs, this.text);
}

class _TvNowPlayingPageState extends State<TvNowPlayingPage> {
  final _player = PlayerService();
  final _queueFocusNode = FocusNode();
  final _queueButtonFocusNode = FocusNode();
  final _searchFocusNode = FocusNode();
  final Map<String, FocusNode> _playlistFocusNodes = {};
  FocusNode? _queueReturnFocusNode;
  Timer? _timer;
  bool _queueOpen = false;
  bool _isFavorite = false;
  double? _downloadProgress;
  String? _loadingMessage;
  List<_LrcLine> _parsedLrc = [];

  @override
  void initState() {
    super.initState();
    _player.addProgressListener(_onProgress);
    _player.addSongChangeListener(_onSongChange);
    _player.addPlayStateListener(_onPlayState);
    _player.addDownloadProgressListener(_onDownloadProgress);
    FavoritesService.version.addListener(_refreshFavoriteState);
    _refreshFavoriteState();
    _syncLyrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (TvRoutes.consumeHomeQueueFocusRequest()) {
        _queueButtonFocusNode.requestFocus();
      } else {
        _searchFocusNode.requestFocus();
      }
    });
    // Keep TV rendering deliberately light. The player emits position events
    // much more frequently than a low-memory TV can repaint the full page.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _syncLyrics();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.removeProgressListener(_onProgress);
    _player.removeSongChangeListener(_onSongChange);
    _player.removePlayStateListener(_onPlayState);
    _player.removeDownloadProgressListener(_onDownloadProgress);
    FavoritesService.version.removeListener(_refreshFavoriteState);
    _queueFocusNode.dispose();
    _queueButtonFocusNode.dispose();
    _searchFocusNode.dispose();
    for (final node in _playlistFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onProgress(Duration _, Duration? __) {
    // The 1-second UI timer above is the sole repaint clock for progress and
    // lyrics; rebuilding on every media-kit position event can starve remote
    // control input and trigger an Android input ANR on low-end TVs.
  }

  void _onSongChange(Song song) {
    _parsedLrc = _parseLrc(song.lyric);
    _refreshFavoriteState();
    if (mounted) setState(() {});
  }

  void _onPlayState(bool _) {
    if (mounted) setState(() {});
  }

  void _onDownloadProgress(double? progress) {
    if (mounted) setState(() => _downloadProgress = progress);
  }

  void _syncLyrics() {
    final song = _player.currentSong;
    if (song == null) {
      if (_parsedLrc.isNotEmpty) _parsedLrc = [];
      return;
    }
    if (song.lyric.isNotEmpty && _parsedLrc.isEmpty) {
      _parsedLrc = _parseLrc(song.lyric);
    }
  }

  Future<void> _playQueueAt(int index) async {
    await _player.playAt(index);
    if (!mounted) return;
    _closeQueue();
  }

  void _openQueue({FocusNode? returnFocusNode}) {
    _queueReturnFocusNode = returnFocusNode ?? _queueButtonFocusNode;
    setState(() => _queueOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _queueFocusNode.requestFocus();
    });
  }

  void _closeQueue() {
    final returnFocusNode = _queueReturnFocusNode;
    _queueReturnFocusNode = null;
    setState(() => _queueOpen = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (returnFocusNode != null && returnFocusNode.canRequestFocus) {
        returnFocusNode.requestFocus();
      } else {
        _queueButtonFocusNode.requestFocus();
      }
    });
  }

  Future<void> _playPlaylist(
    PlaylistInfo playlist,
    FocusNode playlistFocusNode,
  ) async {
    setState(() => _loadingMessage = '正在加载「${playlist.name}」');
    try {
      final songs = await MusicApi.getPlaylist(playlist.id);
      if (!mounted) return;
      if (songs.isEmpty) return;
      _player.playlist
        ..clear()
        ..addAll(songs);
      await _player.playAt(0);
    } catch (_) {
      // Keep the existing queue and restore focus below.
    } finally {
      if (mounted) setState(() => _loadingMessage = null);
    }
    if (mounted) {
      _openQueue(returnFocusNode: playlistFocusNode);
    }
  }

  Future<void> _refreshFavoriteState() async {
    final song = _player.currentSong;
    final favorite =
        song == null ? false : await FavoritesService.isFavorite(song);
    if (mounted) setState(() => _isFavorite = favorite);
  }

  Future<void> _toggleFavorite() async {
    final song = _player.currentSong;
    if (song == null) return;
    if (_isFavorite) {
      await FavoritesService.remove(song);
    } else {
      await FavoritesService.save(song);
    }
    await _refreshFavoriteState();
  }

  void _openFavorites() {
    Navigator.of(context).pushNamed(TvRoutes.favorites);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final interactionBlocked = _queueOpen || _loadingMessage != null;
    return PopScope(
      canPop: !_queueOpen && _loadingMessage == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_queueOpen) {
          _closeQueue();
        }
      },
      child: Stack(
        children: [
          ExcludeFocus(
            excluding: interactionBlocked,
            child: TvPageScaffold(
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: TvPillButton(
                      label: '搜索',
                      icon: Icons.search_rounded,
                      fullWidth: true,
                      autofocus: true,
                      focusNode: _searchFocusNode,
                      borderColor: Colors.white.withValues(alpha: 0.32),
                      onTap: () =>
                          Navigator.of(context).pushNamed(TvRoutes.search),
                    ),
                  ),
                  SizedBox(height: metrics.value(26, minimum: 12)),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 38, child: _leftPanel(context)),
                        SizedBox(width: metrics.value(24, minimum: 12)),
                        Expanded(
                          flex: 62,
                          child: _playlistPanel(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_queueOpen)
            Positioned.fill(
              child: Material(
                color: Colors.black.withValues(alpha: 0.64),
                child: FocusScope(
                  autofocus: true,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _closeQueue,
                        ),
                      ),
                      TvQueuePanel(
                        songs: _player.playlist,
                        currentIndex: _player.currentIndex,
                        firstFocusNode: _queueFocusNode,
                        backgroundColor: ThemeService.bgHint.value,
                        onPlay: _playQueueAt,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_loadingMessage != null || _downloadProgress != null)
            _loadingOverlay(context),
        ],
      ),
    );
  }

  Widget _leftPanel(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final song = _player.currentSong;
    return LayoutBuilder(
      builder: (context, constraints) {
        final alignedWidth =
            constraints.maxWidth.clamp(320.0, 520.0).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SizedBox(
                width: alignedWidth,
                child: _lyricPanel(context),
              ),
            ),
            SizedBox(height: metrics.value(18, minimum: 8)),
            SizedBox(
              width: alignedWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song?.name ?? '还没有播放歌曲',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.hero(size: metrics.font(34)),
                  ),
                  SizedBox(height: metrics.value(8, minimum: 4)),
                  Text(
                    song?.singer ?? '从歌单或搜索开始',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TvTokens.body(
                        size: metrics.font(23), color: TvTokens.muted),
                  ),
                ],
              ),
            ),
            SizedBox(height: metrics.value(18, minimum: 8)),
            SizedBox(width: alignedWidth, child: _homeProgress(metrics)),
            SizedBox(height: metrics.value(18, minimum: 8)),
            SizedBox(
              width: alignedWidth,
              child: TvPlayerControls(
                onPrevious: _player.prev,
                onPlayPause: _player.togglePlayPause,
                onNext: _player.next,
                onFavorite: _toggleFavorite,
                onQueue: _openQueue,
                isPlaying: _player.isPlaying,
                isFavorite: _isFavorite,
                queueFocusNode: _queueButtonFocusNode,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _lyricPanel(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final song = _player.currentSong;
    final lines = song == null
        ? <String>[]
        : _visibleLyricTexts(song, metrics.isCompact ? 4 : 6);
    return TvSectionCard(
      title: '歌词',
      titleAlign: TextAlign.center,
      padding: EdgeInsets.all(metrics.value(18, minimum: 10)),
      child: Center(
        child: lines.isEmpty
            ? Text('正在获取歌词',
                style: TvTokens.body(
                    size: metrics.font(24), color: TvTokens.muted))
            : ListView.separated(
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.value(18, minimum: 10),
                  vertical: metrics.value(8, minimum: 4),
                ),
                itemCount: lines.length,
                separatorBuilder: (_, __) =>
                    SizedBox(height: metrics.value(12, minimum: 6)),
                itemBuilder: (_, index) => Text(
                  lines[index],
                  textAlign: TextAlign.center,
                  maxLines: index == 0 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: index == 0
                      ? TvTokens.hero(size: metrics.font(30))
                      : TvTokens.title(
                          size: metrics.font(22),
                          color: index < 3 ? TvTokens.text : TvTokens.muted,
                        ),
                ),
              ),
      ),
    );
  }

  Widget _playlistPanel(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final playlists = [
      const PlaylistInfo('收藏', 'favorites'),
      ...playlistCategories.entries.expand((entry) => entry.value)
    ];
    return TvSectionCard(
      title: '歌单',
      titleAlign: TextAlign.center,
      padding: EdgeInsets.all(metrics.value(24, minimum: 14)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GridView.builder(
            padding: EdgeInsets.all(metrics.value(14, minimum: 10)),
            itemCount: playlists.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: metrics.gridColumnCount(constraints.maxWidth),
              crossAxisSpacing: metrics.value(18, minimum: 10),
              mainAxisSpacing: metrics.value(18, minimum: 10),
              childAspectRatio: metrics.isCompact ? 1.25 : 1.18,
            ),
            itemBuilder: (_, index) {
              final playlist = playlists[index];
              final isFavorites = index == 0;
              final playlistFocusNode = _playlistFocusNodes.putIfAbsent(
                playlist.id,
                FocusNode.new,
              );
              return TvFocusCard(
                autofocus: false,
                focusNode: playlistFocusNode,
                onTap: isFavorites
                    ? _openFavorites
                    : () => _playPlaylist(playlist, playlistFocusNode),
                radius: metrics.value(22, minimum: 12),
                padding: EdgeInsets.all(metrics.value(18, minimum: 10)),
                color: Colors.black.withValues(alpha: 0.16),
                borderColor: Colors.white.withValues(alpha: 0.08),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isFavorites
                          ? Icons.favorite_rounded
                          : _iconForPlaylist(playlist),
                      color: isFavorites ? TvTokens.danger : TvTokens.text,
                      size: metrics.value(34, minimum: 24),
                    ),
                    SizedBox(height: metrics.value(12, minimum: 6)),
                    Text(
                      isFavorites ? '收藏' : playlist.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TvTokens.title(size: metrics.font(25)),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _loadingOverlay(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final preparing = _downloadProgress != null && _downloadProgress! < 0;
    final text = _loadingMessage ?? (preparing ? '正在准备播放' : '正在缓存音乐');
    final progress =
        _downloadProgress == null || preparing ? null : _downloadProgress;
    return Positioned.fill(
      child: AbsorbPointer(
        child: Material(
          color: Colors.black.withValues(alpha: 0.28),
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.value(34, minimum: 20),
                vertical: metrics.value(24, minimum: 16),
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius:
                    BorderRadius.circular(metrics.value(26, minimum: 16)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: metrics.value(34, minimum: 22),
                    height: metrics.value(34, minimum: 22),
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: metrics.value(3, minimum: 2),
                      color: TvTokens.focus,
                    ),
                  ),
                  SizedBox(width: metrics.value(18, minimum: 10)),
                  Text(text, style: TvTokens.title(size: metrics.font(26))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _homeProgress(TvLayoutMetrics metrics) {
    final duration = _player.liveDuration;
    final position = _player.livePosition;
    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return Row(
      children: [
        Text(_formatDuration(position),
            style:
                TvTokens.label(size: metrics.font(17), color: TvTokens.text)),
        SizedBox(width: metrics.value(12, minimum: 6)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: metrics.value(7, minimum: 4),
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(TvTokens.focus),
            ),
          ),
        ),
        SizedBox(width: metrics.value(12, minimum: 6)),
        Text(_formatDuration(duration),
            style:
                TvTokens.label(size: metrics.font(17), color: TvTokens.text)),
      ],
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

  List<_LrcLine> _parseLrc(String? lyric) {
    if (lyric == null || lyric.isEmpty) return [];
    final lines = <_LrcLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\](.*)');
    for (final line in lyric.split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match == null) continue;
      final min = int.parse(match.group(1)!);
      final sec = int.parse(match.group(2)!);
      final msStr = match.group(3);
      var ms = 0;
      if (msStr != null) {
        ms = int.parse(msStr);
        if (msStr.length == 1) ms *= 100;
        if (msStr.length == 2) ms *= 10;
      }
      final text = match.group(4)?.trim() ?? '';
      if (text.isNotEmpty) {
        lines.add(_LrcLine((min * 60 + sec) * 1000 + ms, text));
      }
    }
    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return lines;
  }

  int _currentLrcIndex() {
    if (_parsedLrc.isEmpty) return -1;
    final posMs = _player.livePosition.inMilliseconds;
    var left = 0;
    var right = _parsedLrc.length - 1;
    var idx = -1;
    while (left <= right) {
      final mid = (left + right) ~/ 2;
      if (_parsedLrc[mid].timeMs <= posMs) {
        idx = mid;
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }
    return idx;
  }

  List<String> _visibleLyricTexts(Song song, int count) {
    final idx = _currentLrcIndex();
    if (idx >= 0 && idx < _parsedLrc.length) {
      final lines = _parsedLrc
          .skip(idx)
          .take(count)
          .map((line) => line.text)
          .where((text) => text.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) return lines;
    }
    final first = _firstLyric(song.lyric);
    final fallback = song.album.isNotEmpty ? song.album : '歌词加载后会显示在这里';
    return first == fallback ? [first] : [first, fallback];
  }

  String _firstLyric(String? lyric) {
    if (lyric == null || lyric.isEmpty) return '正在获取歌词';
    final line = lyric
        .split('\n')
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '正在获取歌词')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .trim();
    return line.isEmpty ? '正在获取歌词' : line;
  }

  String _formatDuration(Duration value) =>
      '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}
