import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/categories.dart';
import '../services/theme_service.dart';
import '../utils/toast.dart';

class ModeDrawer extends StatefulWidget {
  final void Function(PlaylistInfo playlist) onSelectPlaylist;
  final VoidCallback onOpenFavorites;
  final VoidCallback onRandomPlay;
  const ModeDrawer({super.key, required this.onSelectPlaylist, required this.onOpenFavorites, required this.onRandomPlay});
  @override
  State<ModeDrawer> createState() => _ModeDrawerState();
}

class _ModeDrawerState extends State<ModeDrawer> {
  static const _pinKey = 'pinned_playlists';
  final List<PlaylistInfo> _pinnedPlaylists = [];
  Color _accent = Colors.white;
  Color _bgHint = const Color(0xFF000000);

  @override
  void initState() {
    super.initState();
    _loadPinned();
    _onThemeChange();
    ThemeService.accentColor.addListener(_onThemeChange);
    ThemeService.bgHint.addListener(_onThemeChange);
  }

  void _onThemeChange() { if (mounted) setState(() { _accent = ThemeService.accentColor.value; _bgHint = ThemeService.bgHint.value; }); }
  @override
  void dispose() { ThemeService.accentColor.removeListener(_onThemeChange); ThemeService.bgHint.removeListener(_onThemeChange); super.dispose(); }

  static String _encode(PlaylistInfo p) => '${p.id}|${p.name}|${p.coverUrl}';
  static PlaylistInfo? _decode(String s) { final parts = s.split('|'); if (parts.length < 2 || parts[0].isEmpty) return null; return PlaylistInfo(parts.sublist(1, parts.length).join('|'), parts[0], coverUrl: parts.length > 2 ? parts[2] : ''); }

  Future<void> _loadPinned() async { final prefs = await SharedPreferences.getInstance(); final list = prefs.getStringList(_pinKey) ?? []; _pinnedPlaylists.clear(); for (final s in list) { final p = _decode(s); if (p != null) _pinnedPlaylists.add(p); } if (mounted) setState(() {}); }
  Future<void> _savePinned() async { final prefs = await SharedPreferences.getInstance(); await prefs.setStringList(_pinKey, _pinnedPlaylists.map(_encode).toList()); }

  Future<void> _pinPlaylist(PlaylistInfo p) async {
    if (!_pinnedPlaylists.any((e) => e.id == p.id)) { _pinnedPlaylists.add(p); await _savePinned(); if (mounted) { setState(() {}); Toast.show(context, '已置顶「${p.name}」'); } }
  }
  Future<void> _unpinPlaylist(PlaylistInfo p) async { _pinnedPlaylists.removeWhere((e) => e.id == p.id); await _savePinned(); if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      backgroundColor: _bgHint,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildHeader(), const SizedBox(height: 20), _buildModeButtons(), const SizedBox(height: 24),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_pinnedPlaylists.isNotEmpty) ...[_buildPinnedSection(), const SizedBox(height: 24)], _buildCategoryGrid(),
          ]))),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: Row(children: [
      const Text('听歌模式', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      const Spacer(),
      GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.close, color: _accent.withOpacity(0.5), size: 24)),
    ]));
  }

  Widget _buildModeButtons() {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
      _buildModeBtn(Icons.play_circle_outline, '默认模式', () => Navigator.pop(context)),
      const SizedBox(height: 10),
      _buildModeBtn(Icons.favorite_border, '收藏模式', () { Navigator.pop(context); widget.onOpenFavorites(); }),
      const SizedBox(height: 10),
      _buildModeBtn(Icons.shuffle, '随机模式', () { Navigator.pop(context); widget.onRandomPlay(); }),
    ]));
  }

  Widget _buildModeBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: _bgHint.computeLuminance() < 0.05 ? const Color(0xFF1A1A1A) : Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: _accent, size: 20), const SizedBox(width: 8),
        Text(label, style: TextStyle(color: _accent, fontSize: 16, fontWeight: FontWeight.w500)),
      ]),
    ));
  }

  Widget _buildPinnedSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('已置顶', style: TextStyle(color: _accent.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: _pinnedPlaylists.map((p) {
        return GestureDetector(
          onTap: () { Navigator.pop(context); widget.onSelectPlaylist(p); },
          onLongPress: () => _unpinPlaylist(p),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (p.coverUrl.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 5), child: ClipRRect(
                borderRadius: BorderRadius.circular(3), child: Image.network(p.coverUrl, width: 18, height: 18, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.music_note_outlined, color: _accent, size: 14)))),
              Text(p.name, style: TextStyle(color: _accent, fontSize: 12)),
            ])),
        );
      }).toList()),
    ]);
  }

  Widget _buildCategoryGrid() {
    final widgets = <Widget>[];
    for (final entry in playlistCategories.entries) {
      widgets.add(Padding(padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(entry.key, style: TextStyle(color: _accent.withOpacity(0.5), fontSize: 13, fontWeight: FontWeight.w500))));
      widgets.add(GridView.count(
        crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 2.2,
        children: entry.value.map((p) => _buildPlaylistTile(p)).toList(),
      ));
      widgets.add(const SizedBox(height: 14));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  Widget _buildPlaylistTile(PlaylistInfo p) {
    return GestureDetector(
      onTap: () { Navigator.pop(context); widget.onSelectPlaylist(p); },
      onLongPress: () => _pinPlaylist(p),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (p.coverUrl.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(3), child: Image.network(p.coverUrl, width: 16, height: 16, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.music_note_outlined, color: _accent, size: 14)))
          else Icon(Icons.music_note_outlined, color: _accent, size: 14),
          const SizedBox(width: 5),
          Flexible(child: Text(p.name, style: TextStyle(color: _accent.withOpacity(0.85), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}
