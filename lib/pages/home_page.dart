import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/player_service.dart';
import '../models/song.dart';
import 'search_page.dart';
import 'favorites_page.dart';
import 'player_page.dart';
import 'search_result_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _player = PlayerService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Song? _currentSong;

  final List<String> _pinnedPlaylists = [];

  static const _pinKey = 'pinned_playlists';

  static const _categories = <String, List<String>>{
    '语种': ['华语', '欧美', '日语', '韩语', '粤语', '小语种', '闽南语'],
    '风格': ['流行', '嘻哈说唱', '喊麦', '电子', '轻音乐', '慢摇DJ', '民谣', '摇滚', '国风', '古风', '另类/独立', '实验', '民族歌曲', '原声带', '世界音乐', '二次元', '节奏布鲁斯', '戏曲', '古典', '金属', '新世纪', '儿童音乐', '爵士', '蓝调', '乡村', '雷鬼', '拉丁音乐', '舞曲', '网络歌曲', '纯音乐', '交响乐', '朋克', '后摇', '迷幻'],
    '榜单': ['热歌榜', '新歌榜', '飙升榜', '原创榜'],
    '场景': ['清晨', '夜晚', '起床', '助眠', '学习', '工作', '运动', '驾车', '约会', '小酒馆', 'KTV', '游戏直播', '咖啡厅', '瑜伽', '冥想', '下午茶', '散步', '洗澡'],
    '心情': ['伤感', '怀旧', '浪漫', '治愈', '安静', '励志', '快乐', '感动', '孤独', '思念', '放松', '慵懒', '甜蜜', '清新', '热血', '空灵'],
    '主题': ['影视原声', '餐厅', '旅行', '派对', '婚礼', '童年', '青春', '毕业', '圣诞', '新年', '情人节', '生日', '秋天', '冬天', '春天', '夏天'],
  };

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
    _bindPlayer();
    _syncState();
    _loadPinnedPlaylists();
  }

  Future<void> _loadPinnedPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pinKey) ?? [];
    _pinnedPlaylists.clear();
    _pinnedPlaylists.addAll(list);
    if (mounted) setState(() {});
  }

  Future<void> _savePinnedPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinKey, List.from(_pinnedPlaylists));
  }

  void _bindPlayer() {
    _player.removeSongChangeListener(_onSongChange);
    _player.addSongChangeListener(_onSongChange);
    _player.onPlayStateChanged = (_) => mounted ? setState(() {}) : null;
  }

  void _onSongChange(Song song) {
    if (mounted) setState(() => _currentSong = song);
  }

  void _syncState() {
    _currentSong = _player.currentSong;
  }

  @override
  void dispose() {
    _player.removeSongChangeListener(_onSongChange);
    _pulseController.dispose();
    super.dispose();
  }

  void _openPlaylist(String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchResultPage(keyword: name),
      ),
    ).then((_) {
      _bindPlayer();
      _syncState();
      if (mounted) setState(() {});
    });
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171B26),
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
                hintStyle: const TextStyle(color: Color(0x66FFFFFF)),
                filled: true,
                fillColor: const Color(0x00000000),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF6890F9)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0x33FFFFFF)),
                ),
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6890F9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('添加', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
    if (result != null && result.isNotEmpty && !_pinnedPlaylists.contains(result)) {
      _pinnedPlaylists.add(result);
      await _savePinnedPlaylists();
      if (mounted) setState(() {});
    }
  }

  Future<void> _showDeleteDialog(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171B26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要删除「$name」吗？',
                style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE05555),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      _pinnedPlaylists.remove(name);
      await _savePinnedPlaylists();
      if (mounted) setState(() {});
    }
  }

  Widget _buildPlaylistChip(String name, {bool isPinned = false}) {
    return GestureDetector(
      onTap: () => _openPlaylist(name),
      onLongPress: isPinned
          ? () => _showDeleteDialog(name)
          : () async {
              _pinnedPlaylists.add(name);
              await _savePinnedPlaylists();
              if (mounted) setState(() {});
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Text(
          isPinned ? '📌 $name' : name,
          style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildPlaylistSection() {
    final widgets = <Widget>[];

    // 已置顶区域
    widgets.add(const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Text('已置顶',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    ));

    if (_pinnedPlaylists.isNotEmpty) {
      widgets.add(Wrap(
        children: _pinnedPlaylists.map((n) => _buildPlaylistChip(n, isPinned: true)).toList(),
      ));
    }

    // 添加按钮
    widgets.add(Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: _showAddDialog,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x336890F9)),
          ),
          child: const Text('+ 添加',
              style: TextStyle(color: Color(0xFF6890F9), fontSize: 13)),
        ),
      ),
    ));

    // 普通分类
    for (final entry in _categories.entries) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(entry.key,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ));
      widgets.add(Wrap(
        children: entry.value.map((n) => _buildPlaylistChip(n)).toList(),
      ));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widgets,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSong = _currentSong != null;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A1D28), Color(0xFF0D0F14)],
              ),
            ),
            child: Column(
              children: [
                // 顶栏：搜索 + 收藏
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                  child: Row(
                    children: [
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())).then((_) { _bindPlayer(); _syncState(); if (mounted) setState(() {}); }),
                        child: Container(
                          width: 220,
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0x33FFFFFF)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search, size: 20, color: Color(0xFF888888)),
                              SizedBox(width: 8),
                              Text('搜索', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesPage())).then((_) { _bindPlayer(); _syncState(); if (mounted) setState(() {}); }),
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0x33FFFFFF)),
                          ),
                          child: const Icon(Icons.favorite, size: 20, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
                // 歌单区域
                Expanded(child: _buildPlaylistSection()),
                // 跳动按钮
                if (hasSong)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (_, child) => Transform.scale(
                        scale: _pulseAnimation.value,
                        child: child,
                      ),
                      child: GestureDetector(
                        onTap: _openPlayer,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.graphic_eq, color: Colors.white, size: 32),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPlayer() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage())).then((_) {
      _bindPlayer();
      _syncState();
      if (mounted) setState(() {});
    });
  }
}
