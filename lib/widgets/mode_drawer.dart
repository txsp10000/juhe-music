import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/categories.dart';
import '../utils/toast.dart';

class ModeDrawer extends StatefulWidget {
  final void Function(String playlistName) onSelectPlaylist;
  final VoidCallback onOpenFavorites;
  final VoidCallback onRandomPlay;
  final VoidCallback onViewFavorites;

  const ModeDrawer({
    super.key,
    required this.onSelectPlaylist,
    required this.onOpenFavorites,
    required this.onRandomPlay,
    required this.onViewFavorites,
  });

  @override
  State<ModeDrawer> createState() => _ModeDrawerState();
}

class _ModeDrawerState extends State<ModeDrawer> {
  static const _pinKey = 'pinned_playlists';
  final List<String> _pinnedPlaylists = [];

  @override
  void initState() {
    super.initState();
    _loadPinned();
  }

  Future<void> _loadPinned() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pinKey) ?? [];
    _pinnedPlaylists.clear();
    _pinnedPlaylists.addAll(list);
    if (mounted) setState(() {});
  }

  Future<void> _savePinned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinKey, List.from(_pinnedPlaylists));
  }

  Future<void> _pinPlaylist(String name) async {
    if (!_pinnedPlaylists.contains(name)) {
      _pinnedPlaylists.add(name);
      await _savePinned();
      if (mounted) {
        setState(() {});
        Toast.show(context, '已置顶「$name」');
      }
    }
  }

  Future<void> _unpinPlaylist(String name) async {
    _pinnedPlaylists.remove(name);
    await _savePinned();
    if (mounted) setState(() {});
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('添加置顶歌单',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: '输入歌单名称',
                hintStyle: const TextStyle(color: Color(0xFF666666)),
                filled: true,
                fillColor: const Color(0xFF0D0D0D),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF444444)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF333333)),
                ),
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('添加', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
    if (result != null && result.isNotEmpty && !_pinnedPlaylists.contains(result)) {
      _pinnedPlaylists.add(result);
      await _savePinned();
      if (mounted) setState(() {});
    }
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
            icon: '▶',
            label: '默认模式',
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 10),
          _buildModeBtn(
            icon: '♡',
            label: '收藏模式',
            onTap: () {
              Navigator.pop(context);
              widget.onOpenFavorites();
            },
          ),
          const SizedBox(height: 10),
          _buildModeBtn(
            icon: '⟳',
            label: '随机模式',
            onTap: () {
              Navigator.pop(context);
              widget.onRandomPlay();
            },
          ),
          const SizedBox(height: 10),
          _buildModeBtn(
            icon: '♥',
            label: '我的收藏',
            onTap: () {
              Navigator.pop(context);
              widget.onViewFavorites();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeBtn({
    required String icon,
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
        child: Center(
          child: Text(
            '$icon  $label',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinnedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '已置顶',
              style: TextStyle(color: Color(0xFF999999), fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _showAddDialog,
              child: const Text(
                '+ 添加',
                style: TextStyle(color: Color(0xFF999999), fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _pinnedPlaylists.map((name) => GestureDetector(
            onTap: () {
              Navigator.pop(context);
              widget.onSelectPlaylist(name);
            },
            onLongPress: () => _unpinPlaylist(name),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '📌 $name',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildCategoryGrid() {
    final widgets = <Widget>[];
    for (final entry in musicCategories.entries) {
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
          children: entry.value.map((name) => _buildCategoryTile(name)).toList(),
        ),
      );
      widgets.add(const SizedBox(height: 16));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildCategoryTile(String name) {
    final icon = categoryIcons[name] ?? '♪';
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        widget.onSelectPlaylist(name);
      },
      onLongPress: () => _pinPlaylist(name),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              icon,
              style: const TextStyle(fontSize: 20, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              name,
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
