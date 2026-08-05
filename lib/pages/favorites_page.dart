import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../utils/toast.dart';
import '../widgets/glass_panel.dart';
import '../widgets/music_list_tile.dart';
import '../widgets/swipe_action_cell.dart';

class FavoritesPage extends StatefulWidget {
  final bool fromPlayer;
  final bool embedded;
  final VoidCallback? onShowPlayer;
  const FavoritesPage(
      {super.key,
      this.fromPlayer = false,
      this.embedded = false,
      this.onShowPlayer});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Song> _songs = [];
  final _player = PlayerService();
  bool _editMode = false;
  final Set<int> _selected = {};
  final ScrollController _scrollController = ScrollController();
  Color _accent = AppDesignTokens.lyricWhite;
  Color _bgHint = AppDesignTokens.inkBlack;

  @override
  void initState() {
    super.initState();
    _load();
    _player.addSongChangeListener(_onSongChange);
    FavoritesService.version.addListener(_onFavoritesChanged);
    _onThemeChange();
    ThemeService.accentColor.addListener(_onThemeChange);
    ThemeService.bgHint.addListener(_onThemeChange);
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

  void _onFavoritesChanged() => _load();
  void _onSongChange(Song _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _player.removeSongChangeListener(_onSongChange);
    FavoritesService.version.removeListener(_onFavoritesChanged);
    ThemeService.accentColor.removeListener(_onThemeChange);
    ThemeService.bgHint.removeListener(_onThemeChange);
    super.dispose();
  }

  Future<void> _load() async {
    final songs = await FavoritesService.load();
    if (mounted) {
      setState(() => _songs = songs);
      _scrollToPlaying();
    }
  }

  void _scrollToPlaying() {
    final current = _player.currentSong;
    if (current == null) return;
    final idx = _songs.indexWhere((s) => s.id == current.id);
    if (idx > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final offset = (idx * 76.0)
              .clamp(0.0, _scrollController.position.maxScrollExtent);
          _scrollController.animateTo(offset,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
      });
    }
  }

  void _playAt(int index) {
    if (_player.currentSong?.id != _songs[index].id) {
      _player.playlist.clear();
      _player.playlist.addAll(_songs);
      _player.playAt(index);
    }
    if (widget.fromPlayer) {
      Navigator.pop(context);
    } else if (widget.embedded && widget.onShowPlayer != null) {
      widget.onShowPlayer!();
    }
  }

  Future<void> _removeSong(int index) async {
    final song = _songs[index];
    await FavoritesService.remove(song);
    setState(() => _songs.removeAt(index));
  }

  void _toggleSelectAll() {
    if (_selected.length == _songs.length) {
      _selected.clear();
    } else {
      _selected
        ..clear()
        ..addAll(List.generate(_songs.length, (i) => i));
    }
    setState(() {});
  }

  Future<void> _deleteSelected() async {
    final toDelete = _selected.toList()..sort((a, b) => b.compareTo(a));
    for (final i in toDelete) {
      await FavoritesService.remove(_songs[i]);
    }
    final remaining = <Song>[];
    for (var i = 0; i < _songs.length; i++) {
      if (!_selected.contains(i)) remaining.add(_songs[i]);
    }
    setState(() {
      _songs = remaining;
      _selected.clear();
      _editMode = false;
    });
    Toast.show(context, '已删除 ${toDelete.length} 首');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MusicScaffoldBackground(
        bgHint: _bgHint,
        accent: _accent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBody()),
              if (_editMode) _buildEditTray(),
              if (widget.embedded) const SizedBox(height: 118),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Row(
        children: [
          if (!widget.embedded || _editMode)
            IconOrbButton(
              icon: Icons.arrow_back_rounded,
              accent: _accent,
              size: 42,
              onTap: () {
                if (_editMode) {
                  setState(() {
                    _editMode = false;
                    _selected.clear();
                  });
                } else {
                  Navigator.pop(context);
                }
              },
            ),
          if (!widget.embedded || _editMode) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_editMode ? '已选 ${_selected.length} 首' : '收藏',
                    style: AppDesignTokens.display(size: 28)),
                const SizedBox(height: 4),
                Text(_editMode ? '选择要移出的歌曲' : '${_songs.length} 首被点亮的歌',
                    style: AppDesignTokens.caption(color: _accent)),
              ],
            ),
          ),
          if (!_editMode && _songs.isNotEmpty)
            MusicChip(
                label: '整理',
                icon: Icons.edit_rounded,
                accent: _accent,
                onTap: () => setState(() => _editMode = true)),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_songs.isEmpty) {
      return MusicEmptyState(
        accent: _accent,
        icon: Icons.favorite_rounded,
        title: '还没有收藏的歌',
        message: '在播放页点亮爱心，歌曲会出现在这里。',
      );
    }
    final bottomPadding = widget.embedded ? (_editMode ? 36.0 : 132.0) : 24.0;
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(top: 4, bottom: bottomPadding),
      itemCount: _songs.length,
      itemBuilder: (_, i) {
        final s = _songs[i];
        final isCurrent = _player.currentSong?.id == s.id;
        if (_editMode) {
          return MusicListTile(
            song: s,
            index: i,
            selected: _selected.contains(i),
            isCurrent: isCurrent,
            accent: _accent,
            onTap: () => setState(() =>
                _selected.contains(i) ? _selected.remove(i) : _selected.add(i)),
            leadingOverride: Icon(
              _selected.contains(i)
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: _selected.contains(i) ? _accent : AppDesignTokens.dimGrey,
              size: 26,
            ),
          );
        }
        return SwipeActionCell(
          actionLabel: '删除',
          actionColor: AppDesignTokens.danger,
          onAction: () => _removeSong(i),
          child: MusicListTile(
              song: s,
              index: i,
              isCurrent: isCurrent,
              accent: _accent,
              onTap: () => _playAt(i),
              margin: EdgeInsets.zero),
        );
      },
    );
  }

  Widget _buildEditTray() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        child: GlassPanel(
          accent: _accent,
          radius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                  child: _editTrayButton(
                      label: _selected.length == _songs.length ? '取消全选' : '全选',
                      icon: Icons.select_all_rounded,
                      onTap: _toggleSelectAll)),
              const SizedBox(width: 12),
              Expanded(
                  child: _editTrayButton(
                      label: '删除',
                      icon: Icons.delete_rounded,
                      onTap: _selected.isEmpty ? null : _deleteSelected,
                      danger: _selected.isNotEmpty)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editTrayButton(
      {required String label,
      required IconData icon,
      required VoidCallback? onTap,
      bool danger = false}) {
    final enabled = onTap != null;
    final fg = danger
        ? AppDesignTokens.lyricWhite
        : AppDesignTokens.warmWhite.withOpacity(enabled ? 0.92 : 0.42);
    final bg = danger
        ? AppDesignTokens.danger.withOpacity(0.72)
        : Colors.white.withOpacity(enabled ? 0.12 : 0.06);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 54,
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 21),
            const SizedBox(width: 8),
            Text(label,
                style: AppDesignTokens.body(
                    size: 16, color: fg, weight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}
