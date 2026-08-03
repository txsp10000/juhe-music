import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/categories.dart';
import '../api/music_api.dart';
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
  final Map<String, PlaylistInfo> _playlists = {};
  // 搜索
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _loadPinned();
    _loadAllPlaylists();
  }

  static String _encode(PlaylistInfo p) => '${p.id}|${p.name}|${p.coverUrl}';

  static PlaylistInfo? _decode(String s) {
    final parts = s.split('|');
    if (parts.length < 2 || parts[0].isEmpty) return null;
    return PlaylistInfo(
      parts.sublist(1, parts.length).join('|'),
      parts[0],
      coverUrl: parts.length > 2 ? parts[2] : '',
    );
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

  Future<void> _loadAllPlaylists() async {
    for (final entry in playlistCategories.entries) {
      for (final id in entry.value) {
        final info = await MusicApi.getPlaylistInfo(id);
        if (mounted && info != null) setState(() => _playlists[id] = info);
      }
    }
    // 也加载置顶歌单的封面（如果不在内置列表里）
    for (final p in _pinnedPlaylists) {
      if (!_playlists.containsKey(p.id)) {
        final info = await MusicApi.getPlaylistInfo(p.id);
        if (mounted && info != null) setState(() => _playlists[p.id] = info);
      }
    }
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

  /// 根据输入的文字添加歌单（支持歌单 ID 或网易云链接）
  Future<void> _addPlaylist(String input) async {
    final text = input.trim();
    if (text.isEmpty) return;
    // 从链接中提取 ID
    var id = text;
    final urlMatch = RegExp(r'playlist[=/](\d+)').firstMatch(text);
    if (urlMatch != null) id = urlMatch.group(1)!;
    // 是否是纯数字 ID
    if (!RegExp(r'^\d+$').hasMatch(id)) {
      Toast.show(context, '请输入网易云歌单 ID 或链接');
      return;
    }
    Toast.show(context, '正在查找歌单...');
    final info = await MusicApi.getPlaylistInfo(id);
    if (!mounted) return;
    if (info != null) {
      _playlists[id] = info;
      await _pinPlaylist(info);
      Toast.show(context, '已添加「${info.name}」');
      setState(() {});
    } else {
      Toast.show(context, '未找到歌单，请检查 ID');
    }
  }

  List<PlaylistInfo> _filteredPlaylists() {
    if (_searchText.isEmpty) return [];
    final q = _searchText.toLowerCase();
    final results = <PlaylistInfo>[];
    for (final p in _playlists.values) {
      if (p.name.toLowerCase().contains(q)) results.add(p);
    }
    return results;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredPlaylists();
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      backgroundColor: const Color(0xFF000000),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildSearchBar(),
            const SizedBox(height: 12),
            _buildModeButtons(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _searchText.isNotEmpty && filtered.isNotEmpty
                    ? _buildSearchResults(filtered)
                    : _searchText.isNotEmpty
                        ? _buildSearchEmpty()
                        : Column(
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: '搜索或粘贴歌单ID/链接...',
                hintStyle: const TextStyle(color: Color(0xFF555555), fontSize: 14),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF666666), size: 20),
                suffixIcon: _searchText.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _searchText = '');
                        },
                        child: const Icon(Icons.close, color: Color(0xFF666666), size: 18),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF444444)),
                ),
              ),
              onChanged: (v) {
                setState(() => _searchText = v);
                if (v.trim().isEmpty) {
                  _loadAllPlaylists(); // 清空搜索时刷新歌单信息
                }
              },
              onSubmitted: (v) {
                if (v.trim().isNotEmpty && !RegExp(r'^\d').hasMatch(v.trim())) {
                  // 非纯数字开头 → 搜索内置歌单（已经显示了）
                } else if (RegExp(r'^\d+$').hasMatch(v.trim()) || v.contains('playlist')) {
                  _addPlaylist(v.trim());
                }
              },
            ),
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
          const SizedBox(height: 8),
          _buildModeBtn(
            icon: Icons.favorite_border,
            label: '收藏模式',
            onTap: () {
              Navigator.pop(context);
              widget.onOpenFavorites();
            },
          ),
          const SizedBox(height: 8),
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
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
          style: TextStyle(color: Color(0xFF999999), fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _pinnedPlaylists.map((p) {
            final latest = _playlists[p.id];
            final cover = latest?.coverUrl ?? p.coverUrl;
            final name = latest?.name ?? p.name;
            return GestureDetector(
              onTap: () {
                Navigator.pop(context);
                widget.onSelectPlaylist(latest ?? p);
              },
              onLongPress: () => _unpinPlaylist(p),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cover.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Image.network(
                            cover, width: 18, height: 18, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.music_note_outlined, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCategoryGrid() {
    final widgets = <Widget>[];
    for (final entry in playlistCategories.entries) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 4),
          child: Text(
            entry.key,
            style: const TextStyle(color: Color(0xFF999999), fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      );
      widgets.add(
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 2.2,
          children: entry.value.map((id) => _buildPlaylistTile(id)).toList(),
        ),
      );
      widgets.add(const SizedBox(height: 14));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildPlaylistTile(String id) {
    final info = _playlists[id];
    final cover = info?.coverUrl ?? '';
    final name = info?.name ?? id;
    return GestureDetector(
      onTap: info != null
          ? () {
              Navigator.pop(context);
              widget.onSelectPlaylist(info);
            }
          : null,
      onLongPress: info != null ? () => _pinPlaylist(info) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (info != null && cover.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Image.network(
                  cover, width: 16, height: 16, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.music_note_outlined, color: Colors.white, size: 14),
                ),
              )
            else
              const Icon(Icons.music_note_outlined, color: Colors.white, size: 14),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                name,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(List<PlaylistInfo> results) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final p = results[i];
        return GestureDetector(
          onTap: () {
            Navigator.pop(context);
            widget.onSelectPlaylist(p);
          },
          onLongPress: () => _pinPlaylist(p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (p.coverUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      p.coverUrl, width: 22, height: 22, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.music_note_outlined, color: Colors.white, size: 16),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(p.name,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF555555), size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchEmpty() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          const Icon(Icons.playlist_play, color: Color(0xFF555555), size: 48),
          const SizedBox(height: 12),
          const Text('未找到内置歌单',
              style: TextStyle(color: Color(0xFF666666), fontSize: 14)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _addPlaylist(_searchText),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF444444)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('在线搜索「$_searchText」',
                  style: const TextStyle(color: Color(0xFF999999), fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}
