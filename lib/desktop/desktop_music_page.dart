import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/music_api.dart';
import '../models/listening_mode.dart';
import '../models/song.dart';
import '../services/cover_cache_service.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../utils/lyric_parser.dart';

enum _DesktopSection { listen, search, favorites }

class DesktopMusicPage extends StatefulWidget {
  const DesktopMusicPage({super.key});

  @override
  State<DesktopMusicPage> createState() => _DesktopMusicPageState();
}

class _DesktopMusicPageState extends State<DesktopMusicPage> {
  final PlayerService _player = PlayerService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  _DesktopSection _section = _DesktopSection.listen;
  List<Song> _searchResults = const [];
  List<Song> _favorites = const [];
  bool _loadingSearch = false;
  bool _loadingFavorites = false;
  String? _searchError;

  static const _ink = Color(0xFF1D1D1F);
  static const _secondary = Color(0xFF6E6E73);
  static const _tertiary = Color(0xFF86868B);
  static const _background = Color(0xFFF5F5F7);
  static const _surface = Color(0xFFFFFFFF);
  static const _separator = Color(0xFFD2D2D7);
  static const _accent = Color(0xFF0071E3);

  @override
  void initState() {
    super.initState();
    _player.addSongChangeListener(_refresh);
    _player.addPlayStateListener((_) => _refresh());
    _player.addProgressListener((_, __) => _refresh());
    FavoritesService.version.addListener(_loadFavorites);
    unawaited(_loadFavorites());
  }

  void _refresh([dynamic _]) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player.removeSongChangeListener(_refresh);
    FavoritesService.version.removeListener(_loadFavorites);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    if (!mounted) return;
    setState(() => _loadingFavorites = true);
    final songs = await FavoritesService.load();
    if (mounted) {
      setState(() {
        _favorites = songs;
        _loadingFavorites = false;
      });
    }
  }

  Future<void> _search(String raw) async {
    final keyword = raw.trim();
    setState(() {
      _section = _DesktopSection.search;
      _searchError = null;
      _loadingSearch = keyword.isNotEmpty;
      if (keyword.isEmpty) _searchResults = const [];
    });
    if (keyword.isEmpty) return;
    try {
      final result = await MusicApi.searchTracks(keyword);
      if (mounted) setState(() => _searchResults = result.songs);
    } catch (_) {
      if (mounted) setState(() => _searchError = '搜索失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _loadingSearch = false);
    }
  }

  Future<void> _selectMode(ListeningMode mode) async {
    setState(() => _section = _DesktopSection.listen);
    try {
      final songs = await MusicApi.getModeTracks(sceneModeId: mode.sceneModeId);
      if (songs.isEmpty) return;
      _player.replaceQueue(songs, mode: mode);
      await _player.playAt(0);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('模式歌曲加载失败')),
        );
      }
    }
  }

  Future<void> _playSongs(List<Song> songs, int index,
      {PlaybackQueueSource source = PlaybackQueueSource.regular}) async {
    if (songs.isEmpty) return;
    _player.replaceQueue(songs, source: source);
    await _player.playAt(index);
    if (mounted) setState(() => _section = _DesktopSection.listen);
  }

  Future<void> _toggleFavorite(Song song) async {
    final exists = _favorites.any((item) => item.id == song.id);
    if (exists) {
      await FavoritesService.remove(song);
    } else {
      await FavoritesService.save(song);
    }
    await _loadFavorites();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          final showQueue = constraints.maxWidth >= 1120;
          return SafeArea(
            minimum: const EdgeInsets.all(14),
            child: Column(
              children: [
                _buildWindowBar(compact),
                const SizedBox(height: 14),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSidebar(compact),
                      const SizedBox(width: 14),
                      Expanded(child: _buildMainPanel()),
                      if (showQueue) ...[
                        const SizedBox(width: 14),
                        SizedBox(width: 304, child: _buildQueueRail()),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _buildTransportBar(compact),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildWindowBar(bool compact) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _ink,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.graphic_eq_rounded,
              color: Colors.white, size: 17),
        ),
        const SizedBox(width: 10),
        const Text('汽水音乐',
            style: TextStyle(
                color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(width: 20),
        if (!compact)
          Expanded(
            child: Center(
              child: SizedBox(
                width: 370,
                height: 38,
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onSubmitted: _search,
                  style: const TextStyle(color: _ink, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '搜索歌曲、歌手或专辑',
                    hintStyle: const TextStyle(color: _tertiary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: _secondary, size: 19),
                    suffixIcon: IconButton(
                      tooltip: '搜索',
                      icon: const Icon(Icons.arrow_forward_rounded,
                          size: 18, color: _secondary),
                      onPressed: () => _search(_searchController.text),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFEAEAEF),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: _accent, width: 1.2)),
                  ),
                ),
              ),
            ),
          )
        else
          const Spacer(),
        _WindowIconButton(
            icon: Icons.settings_outlined, tooltip: '设置', onTap: () {}),
      ],
    );
  }

  Widget _buildSidebar(bool compact) {
    return SizedBox(
      width: compact ? 60 : 224,
      child: _Surface(
        color: _surface,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact)
              const Padding(
                  padding: EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: Text('音乐',
                      style: TextStyle(
                          color: _tertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700))),
            _navItem(Icons.play_circle_outline_rounded, '现在播放',
                _DesktopSection.listen, compact),
            _navItem(
                Icons.search_rounded, '搜索', _DesktopSection.search, compact),
            _navItem(Icons.favorite_border_rounded, '我的收藏',
                _DesktopSection.favorites, compact),
            const SizedBox(height: 22),
            if (!compact)
              const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Text('聆听模式',
                      style: TextStyle(
                          color: _tertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700))),
            Expanded(
              child: ListView.separated(
                itemCount: listeningModes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  final mode = listeningModes[index];
                  final selected = identical(_player.activeMode, mode);
                  return _NavRow(
                    icon: mode.icon,
                    label: mode.name,
                    compact: compact,
                    selected: selected,
                    onTap: () => unawaited(_selectMode(mode)),
                  );
                },
              ),
            ),
            if (!compact)
              const Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Text('Windows 客户端',
                      style: TextStyle(color: _tertiary, fontSize: 11))),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
      IconData icon, String label, _DesktopSection section, bool compact) {
    return _NavRow(
      icon: icon,
      label: label,
      compact: compact,
      selected: _section == section,
      onTap: () {
        setState(() => _section = section);
        if (section == _DesktopSection.search) _searchFocus.requestFocus();
      },
    );
  }

  Widget _buildMainPanel() {
    return _Surface(
      color: _surface,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: switch (_section) {
          _DesktopSection.listen => _buildListeningView(),
          _DesktopSection.search => _buildCollection(
              '搜索',
              _searchResults,
              _loadingSearch,
              _searchError,
              Icons.search_rounded,
              '搜索你想听的歌',
              '输入关键词开始搜索'),
          _DesktopSection.favorites => _buildCollection(
              '我的收藏',
              _favorites,
              _loadingFavorites,
              null,
              Icons.favorite_border_rounded,
              '还没有收藏歌曲',
              '喜欢的歌曲会出现在这里'),
        },
      ),
    );
  }

  Widget _buildListeningView() {
    final song = _player.currentSong;
    if (song == null) {
      return const _EmptyView(
          key: ValueKey('empty'),
          icon: Icons.music_note_rounded,
          title: '开始你的音乐之旅',
          message: '从左侧选择一个聆听模式，或搜索你想听的歌曲。');
    }
    final lyrics = parseLyrics(song.lyric);
    final index =
        _activeLyricIndex(lyrics, _player.livePosition.inMilliseconds);
    return Padding(
      key: ValueKey('playing-${song.id}'),
      padding: const EdgeInsets.fromLTRB(34, 30, 34, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DesktopAlbumArt(song: song, size: 224, radius: 14),
              const SizedBox(width: 30),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('正在播放',
                            style: TextStyle(
                                color: _accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Text(song.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _ink,
                                fontSize: 30,
                                height: 1.08,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 9),
                        Text(song.singer.isEmpty ? '未知歌手' : song.singer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _secondary,
                                fontSize: 15,
                                fontWeight: FontWeight.w500)),
                        if (song.album.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(song.album,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: _tertiary, fontSize: 12)),
                        ],
                        const SizedBox(height: 24),
                        Row(children: [
                          _FilledIconButton(
                              icon: _player.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              tooltip: _player.isPlaying ? '暂停' : '播放',
                              onTap: () =>
                                  unawaited(_player.togglePlayPause())),
                          const SizedBox(width: 10),
                          _WindowIconButton(
                              icon: _isFavorite(song)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              tooltip: _isFavorite(song) ? '取消收藏' : '收藏',
                              color: _isFavorite(song)
                                  ? const Color(0xFFFF3B30)
                                  : _secondary,
                              onTap: () => unawaited(_toggleFavorite(song))),
                        ]),
                      ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          const Divider(height: 1, color: _separator),
          const SizedBox(height: 22),
          const Text('歌词',
              style: TextStyle(
                  color: _ink, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Expanded(child: _Lyrics(lines: lyrics, currentIndex: index)),
        ],
      ),
    );
  }

  bool _isFavorite(Song song) => _favorites.any((item) => item.id == song.id);

  Widget _buildCollection(
      String title,
      List<Song> songs,
      bool loading,
      String? error,
      IconData emptyIcon,
      String emptyTitle,
      String emptyMessage) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: _accent));
    }
    if (error != null) {
      return _EmptyView(
          icon: Icons.wifi_off_rounded, title: error, message: '');
    }
    if (songs.isEmpty) {
      return _EmptyView(
          icon: emptyIcon, title: emptyTitle, message: emptyMessage);
    }
    final source = title == '我的收藏'
        ? PlaybackQueueSource.favorites
        : PlaybackQueueSource.regular;
    return Padding(
      key: ValueKey(title),
      padding: const EdgeInsets.fromLTRB(28, 27, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: _ink, fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text('${songs.length} 首歌曲',
            style: const TextStyle(color: _secondary, fontSize: 12)),
        const SizedBox(height: 20),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              SizedBox(width: 40),
              Expanded(
                  child: Text('歌曲',
                      style: TextStyle(color: _tertiary, fontSize: 11))),
              SizedBox(
                  width: 118,
                  child: Text('专辑',
                      style: TextStyle(color: _tertiary, fontSize: 11))),
              SizedBox(width: 40)
            ])),
        const SizedBox(height: 5),
        Expanded(
            child: ListView.separated(
                itemCount: songs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, index) => _TrackRow(
                    song: songs[index],
                    index: index,
                    active: _player.currentSong?.id == songs[index].id,
                    favorite: _isFavorite(songs[index]),
                    onTap: () =>
                        unawaited(_playSongs(songs, index, source: source)),
                    onFavorite: () =>
                        unawaited(_toggleFavorite(songs[index]))))),
      ]),
    );
  }

  Widget _buildQueueRail() {
    final isFavorites = _section == _DesktopSection.favorites;
    final songs = isFavorites ? _favorites : _player.queue;
    return _Surface(
        color: _surface,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Row(children: [
                Icon(
                    isFavorites
                        ? Icons.favorite_border_rounded
                        : Icons.queue_music_rounded,
                    color: _secondary,
                    size: 18),
                const SizedBox(width: 9),
                Expanded(
                    child: Text(isFavorites ? '收藏' : '播放列表',
                        style: const TextStyle(
                            color: _ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w600))),
                Text('${songs.length}',
                    style: const TextStyle(color: _tertiary, fontSize: 12))
              ])),
          const Divider(height: 1, color: _separator),
          Expanded(
              child: songs.isEmpty
                  ? const _EmptyView(
                      icon: Icons.queue_music_rounded,
                      title: '列表是空的',
                      message: '播放歌曲后会显示在这里。')
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: songs.length,
                      itemBuilder: (context, index) => _QueueRow(
                          song: songs[index],
                          index: index,
                          current: _player.currentSong?.id == songs[index].id,
                          onTap: () => isFavorites
                              ? unawaited(_playSongs(songs, index,
                                  source: PlaybackQueueSource.favorites))
                              : unawaited(_player.playAt(index))))),
        ]));
  }

  Widget _buildTransportBar(bool compact) {
    final song = _player.currentSong;
    final duration = _player.liveDuration;
    final position = _player.livePosition;
    final max = duration.inMilliseconds.toDouble();
    final value =
        max <= 0 ? 0.0 : position.inMilliseconds.toDouble().clamp(0.0, max);
    return _Surface(
        color: _surface,
        shadow: true,
        child: SizedBox(
            height: 78,
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(children: [
                  SizedBox(
                      width: compact ? 120 : 230,
                      child: song == null
                          ? const Text('未选择歌曲',
                              style: TextStyle(color: _secondary, fontSize: 12))
                          : Row(children: [
                              DesktopAlbumArt(song: song, size: 46, radius: 8),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(song.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: _ink,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 3),
                                    Text(song.singer,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: _secondary, fontSize: 11))
                                  ]))
                            ])),
                  const Spacer(),
                  _WindowIconButton(
                      icon: Icons.skip_previous_rounded,
                      tooltip: '上一首',
                      onTap: _player.prev),
                  const SizedBox(width: 4),
                  _FilledIconButton(
                      icon: _player.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      tooltip: _player.isPlaying ? '暂停' : '播放',
                      onTap: () => unawaited(_player.togglePlayPause())),
                  const SizedBox(width: 4),
                  _WindowIconButton(
                      icon: Icons.skip_next_rounded,
                      tooltip: '下一首',
                      onTap: _player.next),
                  const Spacer(),
                  Expanded(
                      flex: compact ? 2 : 3,
                      child: Row(children: [
                        Text(_formatTime(position),
                            style: const TextStyle(
                                color: _secondary, fontSize: 10)),
                        Expanded(
                            child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 4),
                                    overlayShape: const RoundSliderOverlayShape(
                                        overlayRadius: 12),
                                    activeTrackColor: _accent,
                                    inactiveTrackColor: const Color(0xFFD2D2D7),
                                    thumbColor: _accent),
                                child: Slider(
                                    value: value,
                                    max: max <= 0 ? 1 : max,
                                    onChanged: max <= 0
                                        ? null
                                        : (v) => unawaited(_player.seek(
                                            Duration(
                                                milliseconds: v.round())))))),
                        Text(_formatTime(duration),
                            style: const TextStyle(
                                color: _secondary, fontSize: 10))
                      ])),
                ]))));
  }

  int _activeLyricIndex(List<LyricLine> lines, int ms) {
    if (lines.isEmpty) return -1;
    for (var i = lines.length - 1; i >= 0; i--) {
      if (ms >= lines[i].startMs) return i;
    }
    return 0;
  }

  String _formatTime(Duration value) {
    final seconds = value.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class _Surface extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final bool shadow;
  const _Surface(
      {required this.child,
      required this.color,
      this.padding = EdgeInsets.zero,
      this.shadow = false});
  @override
  Widget build(BuildContext context) => Container(
      padding: padding,
      decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE1E1E6)),
          boxShadow: shadow
              ? const [
                  BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 14,
                      offset: Offset(0, 4))
                ]
              : null),
      child: ClipRRect(borderRadius: BorderRadius.circular(13), child: child));
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;
  const _NavRow(
      {required this.icon,
      required this.label,
      required this.compact,
      required this.selected,
      required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
      message: compact ? label : '',
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: const Color(0xFFF0F0F3),
          child: Container(
              height: 42,
              padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
              decoration: BoxDecoration(
                  color:
                      selected ? const Color(0xFFE8F2FD) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10)),
              child: Row(
                  mainAxisAlignment: compact
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Icon(icon,
                        color: selected
                            ? const Color(0xFF0071E3)
                            : const Color(0xFF6E6E73),
                        size: 19),
                    if (!compact) ...[
                      const SizedBox(width: 11),
                      Expanded(
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: selected
                                      ? const Color(0xFF0071E3)
                                      : const Color(0xFF424245),
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500)))
                    ]
                  ]))));
}

class _TrackRow extends StatelessWidget {
  final Song song;
  final int index;
  final bool active;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  const _TrackRow(
      {required this.song,
      required this.index,
      required this.active,
      required this.favorite,
      required this.onTap,
      required this.onFavorite});
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      hoverColor: const Color(0xFFF5F5F7),
      child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: active ? const Color(0xFFE8F2FD) : Colors.transparent,
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            SizedBox(
                width: 28,
                child: active
                    ? const Icon(Icons.graphic_eq_rounded,
                        color: Color(0xFF0071E3), size: 17)
                    : Text('${index + 1}'.padLeft(2, '0'),
                        style: const TextStyle(
                            color: Color(0xFFAEAEB2), fontSize: 11))),
            DesktopAlbumArt(song: song, size: 44, radius: 8),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: active
                              ? const Color(0xFF0071E3)
                              : const Color(0xFF1D1D1F),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(song.singer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF6E6E73), fontSize: 11))
                ])),
            SizedBox(
                width: 118,
                child: Text(song.album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF86868B), fontSize: 11))),
            IconButton(
                tooltip: favorite ? '取消收藏' : '收藏',
                iconSize: 18,
                splashRadius: 18,
                onPressed: onFavorite,
                icon: Icon(
                    favorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: favorite
                        ? const Color(0xFFFF3B30)
                        : const Color(0xFF86868B)))
          ])));
}

class _QueueRow extends StatelessWidget {
  final Song song;
  final int index;
  final bool current;
  final VoidCallback onTap;
  const _QueueRow(
      {required this.song,
      required this.index,
      required this.current,
      required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      hoverColor: const Color(0xFFF5F5F7),
      child: Container(
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              color: current ? const Color(0xFFE8F2FD) : Colors.transparent,
              borderRadius: BorderRadius.circular(9)),
          child: Row(children: [
            SizedBox(
                width: 20,
                child: current
                    ? const Icon(Icons.graphic_eq_rounded,
                        color: Color(0xFF0071E3), size: 15)
                    : Text('${index + 1}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFFAEAEB2), fontSize: 10))),
            DesktopAlbumArt(song: song, size: 36, radius: 7),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: current
                              ? const Color(0xFF0071E3)
                              : const Color(0xFF424245),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(song.singer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF86868B), fontSize: 10))
                ]))
          ])));
}

class _Lyrics extends StatelessWidget {
  final List<LyricLine> lines;
  final int currentIndex;
  const _Lyrics({required this.lines, required this.currentIndex});
  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const Center(
          child: Text('暂无歌词',
              style: TextStyle(color: Color(0xFF86868B), fontSize: 14)));
    }
    final visible = <int>[currentIndex - 1, currentIndex, currentIndex + 1]
        .where((i) => i >= 0 && i < lines.length)
        .toList();
    return Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: visible.map((i) {
              final active = i == currentIndex;
              return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(lines[i].text,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: active
                              ? const Color(0xFF1D1D1F)
                              : const Color(0xFFAEAEB2),
                          fontSize: active ? 22 : 16,
                          height: 1.25,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w400)));
            }).toList()));
  }
}

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _EmptyView(
      {super.key,
      required this.icon,
      required this.title,
      required this.message});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: const Color(0xFFAEAEB2)),
              const SizedBox(height: 14),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFF1D1D1F),
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF6E6E73), fontSize: 13)),
              ],
            ],
          ),
        ),
      );
}

class _WindowIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;
  const _WindowIconButton(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      this.color = const Color(0xFF6E6E73)});
  @override
  Widget build(BuildContext context) => Tooltip(
      message: tooltip,
      child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: color, size: 20),
          splashRadius: 20,
          hoverColor: const Color(0xFFEAEAEF)));
}

class _FilledIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _FilledIconButton(
      {required this.icon, required this.tooltip, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: const Color(0xFF0071E3),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
                width: 46,
                height: 46,
                child: Icon(icon, color: Colors.white, size: 24)),
          ),
        ),
      );
}

class DesktopAlbumArt extends StatefulWidget {
  final Song song;
  final double size;
  final double radius;
  const DesktopAlbumArt(
      {super.key, required this.song, required this.size, this.radius = 10});
  @override
  State<DesktopAlbumArt> createState() => _DesktopAlbumArtState();
}

class _DesktopAlbumArtState extends State<DesktopAlbumArt> {
  Uint8List? _bytes;
  String? _cacheKey;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DesktopAlbumArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.song.picId != widget.song.picId) {
      _bytes = null;
      _cacheKey = null;
      _load();
    }
  }

  Future<void> _load() async {
    final key =
        widget.song.picId.isNotEmpty ? widget.song.picId : widget.song.id;
    _cacheKey = key;
    final cache = CoverCacheService();
    final stored = await cache.load(key);
    final bytes = stored ??
        (widget.song.cover.isEmpty
            ? null
            : await cache.download(key, widget.song.cover));
    if (mounted && _cacheKey == key && bytes != null) {
      setState(() => _bytes = bytes);
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Container(
          width: widget.size,
          height: widget.size,
          color: const Color(0xFFE5E5EA),
          child: _bytes != null
              ? Image.memory(_bytes!, fit: BoxFit.cover)
              : _fallback()));
  Widget _fallback() => const Center(
      child:
          Icon(Icons.music_note_rounded, color: Color(0xFFAEAEB2), size: 32));
}
