import 'dart:math';
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

class _HomePageState extends State<HomePage> {
  final _player = PlayerService();

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
    super.dispose();
  }

  void _openPlaylist(String name) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SearchResultPage(keyword: '$name歌单')),
    ).then((_) {
      _bindPlayer();
      _syncState();
      if (mounted) setState(() {});
    });
  }

  void _randomPlay() {
    if (_pinnedPlaylists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先置顶一些歌单'), duration: Duration(seconds: 2)),
      );
      return;
    }
    final random = Random();
    final pick = _pinnedPlaylists[random.nextInt(_pinnedPlaylists.length)];
    _openPlaylist(pick);
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
                  borderSide: const BorderSide(color: Color(0xFF6C8CFF)),
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
                  backgroundColor: const Color(0xFF6C8CFF),
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

  void _openPlayer() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage())).then((_) {
      _bindPlayer();
      _syncState();
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasSong = _currentSong != null;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A1D28), Color(0xFF0D0F14)],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchBar(),
                  const SizedBox(height: 12),
                  _buildNowPlayingBar(),
                  const SizedBox(height: 12),
                  _buildFuncCards(),
                  const SizedBox(height: 24),
                  _buildPinnedSection(),
                  const SizedBox(height: 24),
                  ..._buildCategories(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SearchPage()),
      ).then((_) { _bindPlayer(); _syncState(); if (mounted) setState(() {}); }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2230),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: const Row(
          children: [
            Icon(Icons.search, size: 20, color: Color(0xFF555A6E)),
            SizedBox(width: 10),
            Text('搜索歌曲、歌手、歌单...',
                style: TextStyle(color: Color(0xFF555A6E), fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Widget _buildFuncCards() {
    return Column(
      children: [
        _buildFuncCard(
          icon: Icons.favorite,
          iconColor: const Color(0xFFFF6B6B),
          bgColor: const Color(0x1FFF6B6B),
          title: '我的收藏',
          desc: '已收藏的歌曲',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FavoritesPage()),
          ).then((_) { _bindPlayer(); _syncState(); if (mounted) setState(() {}); }),
        ),
        const SizedBox(height: 12),
        _buildFuncCard(
          icon: Icons.repeat,
          iconColor: const Color(0xFF4ECDC4),
          bgColor: const Color(0x1F4ECDC4),
          title: '随机播放',
          desc: '从置顶歌单随机选曲',
          onTap: _randomPlay,
        ),
      ],
    );
  }

  Widget _buildFuncCard({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF161922),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(desc,
                    style: const TextStyle(color: Color(0xFF8B8FA0), fontSize: 11)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFF555A6E)),
          ],
        ),
      ),
    );
  }

  Widget _buildPinnedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('已置顶',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._pinnedPlaylists.map((n) => _buildPinnedChip(n)),
            _buildAddChip(),
          ],
        ),
      ],
    );
  }

  Widget _buildPinnedChip(String name) {
    return GestureDetector(
      onTap: () => _openPlaylist(name),
      onLongPress: () => _showDeleteDialog(name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x1F6C8CFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x336C8CFF)),
        ),
        child: Text('📌 $name',
            style: const TextStyle(color: Color(0xFF6C8CFF), fontSize: 13, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildAddChip() {
    return GestureDetector(
      onTap: _showAddDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x4D6C8CFF)),
        ),
        child: const Text('+ 添加',
            style: TextStyle(color: Color(0xFF6C8CFF), fontSize: 13)),
      ),
    );
  }

  List<Widget> _buildCategories() {
    final widgets = <Widget>[];
    for (final entry in _categories.entries) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(entry.key,
              style: const TextStyle(color: Color(0xFF8B8FA0), fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      );
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entry.value.map((n) => _buildCatChip(n)).toList(),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildCatChip(String name) {
    return GestureDetector(
      onTap: () => _openPlaylist(name),
      onLongPress: () async {
        if (!_pinnedPlaylists.contains(name)) {
          _pinnedPlaylists.add(name);
          await _savePinnedPlaylists();
          if (mounted) setState(() {});
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已置顶「$name」'), duration: const Duration(seconds: 1)),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF161922),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Text(name,
            style: const TextStyle(color: Color(0xFFF0F0F5), fontSize: 13)),
      ),
    );
  }

  Widget _buildNowPlayingBar() {
    final hasSong = _currentSong != null;
    final isPlaying = _player.isPlaying;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: hasSong ? _openPlayer : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF161922),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6C8CFF), Color(0xFF9B6CFF)],
                ),
              ),
              child: const Icon(
                Icons.graphic_eq,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentSong?.name ?? '正在播放',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _currentSong?.singer ?? '暂无播放',
                    style: const TextStyle(color: Color(0xFF8B8FA0), fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (hasSong)
              GestureDetector(
                onTap: () => _player.togglePlayPause(),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 24,
                  color: const Color(0x99FFFFFF),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
