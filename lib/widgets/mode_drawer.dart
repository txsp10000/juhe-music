import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/categories.dart';
import '../utils/toast.dart';

class ModeDrawer extends StatefulWidget {
  final void Function(PlaylistInfo playlist) onSelectPlaylist;
  final VoidCallback onOpenFavorites;
  final VoidCallback onRandomPlay;

  const ModeDrawer({
    super.key,
    required this.onSelectPlaylist,
    required this.onOpenFavorites,
    required this.onRandomPlay,
  });

  @override
  State<ModeDrawer> createState() => _ModeDrawerState();
}

class _ModeDrawerState extends State<ModeDrawer> {
  static const _pinKey = 'pinned_playlists';
  final List<PlaylistInfo> _pinnedPlaylists = [];

  @override
  void initState() {
    super.initState();
    _loadPinned();
  }

  static String _encode(PlaylistInfo p) => '${p.id}|${p.name}';

  static PlaylistInfo? _decode(String s) {
    final idx = s.indexOf('|');
    if (idx <= 0) return null;
    return PlaylistInfo(s.substring(idx + 1), s.substring(0, idx));
  }

  Future<void> _loadPinned() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pinKey) ?? [];
    _pinnedPlaylists.clear();
    for (final s in list) {
      final p = _decode(s);
      if (p != null) _pinnedPlaylists.add(p);
    }
    if (mounted) setState(() {});
  }

  Future<void> _savePinned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinKey, _pinnedPlaylists.map(_encode).toList());
  }

  Future<void> _pinPlaylist(PlaylistInfo p) async {
    if (!_pinnedPlaylists.any((e) => e.id == p.id)) {
      _pinnedPlaylists.add(p);
      await _savePinned();
      if (mounted) {
        setState(() {});
        Toast.show(context, '已置顶「${p.name}」');
      }
    }
  }

  Future<void> _unpinPlaylist(PlaylistInfo p) async {
    _pinnedPlaylists.removeWhere((e) => e.id == p.id);
    await _savePinned();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      backgroundColor: const Color(0xFF000000),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildModeButtons(),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_pinnedPlaylists.isNotEmpty) ...[
                      _buildPinnedSection(),
                      const SizedBox(height: 24),
                    ],
                    _buildCategoryGrid(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          const Text(
            '听歌模式',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.close, color: Color(0xFF999999), size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildModeBtn(
            icon: Icons.play_circle_outline,
            label: '默认模式',
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 10),
          _buildModeBtn(
            icon: Icons.favorite_border,
            label: '收藏模式',
            onTap: () {
              Navigator.pop(context);
              widget.onOpenFavorites();
            },
          ),
          const SizedBox(height: 10),
          _buildModeBtn(
            icon: Icons.shuffle,
            label: '随机模式',
            onTap: () {
              Navigator.pop(context);
              widget.onRandomPlay();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinnedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '已置顶',
          style: TextStyle(color: Color(0xFF999999), fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _pinnedPlaylists.map((p) => GestureDetector(
            onTap: () {
              Navigator.pop(context);
              widget.onSelectPlaylist(p);
            },
            onLongPress: () => _unpinPlaylist(p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.push_pin_outlined, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildCategoryGrid() {
    final widgets = <Widget>[];
    for (final entry in playlistCategories.entries) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: Text(
            entry.key,
            style: const TextStyle(color: Color(0xFF999999), fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      );
      widgets.add(
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.2,
          children: entry.value.map((p) => _buildPlaylistTile(p)).toList(),
        ),
      );
      widgets.add(const SizedBox(height: 16));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildPlaylistTile(PlaylistInfo p) {
    final icon = playlistIcons[p.name] ?? Icons.music_note_outlined;
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        widget.onSelectPlaylist(p);
      },
      onLongPress: () => _pinPlaylist(p),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              p.name,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
