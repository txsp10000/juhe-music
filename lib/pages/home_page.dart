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

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _player = PlayerService();
  late AnimationController _barController;

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

  // ─── Design tokens ───
  static const _bg = Color(0xFF07080C);
  static const _surface = Color(0xFF0F1116);
  static const _accent = Color(0xFF5A78F0);
  static const _textPrimary = Color(0xFFEDEDF2);
  static const _textSecondary = Color(0xFF7C7F8C);
  static const _textTertiary = Color(0xFF4E515E);
  static const _divider = Color(0x0FFFFFFF);

  @override
  void initState() {
    super.initState();
    _barController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
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
    _barController.dispose();
    super.dispose();
  }

  void _openPlaylist(String name) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SearchResultPage(keyword: name)),
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
    final pick = _pinnedPlaylists[Random().nextInt(_pinnedPlaylists.length)];
    _openPlaylist(pick);
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('添加置顶歌单',
                style: TextStyle(color: _textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: const TextStyle(color: _textPrimary, fontSize: 15),
              decoration: InputDecoration(
                hintText: '输入歌单名称',
                hintStyle: const TextStyle(color: _textTertiary),
                filled: true,
                fillColor: const Color(0x00000000),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _accent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _divider),
                ),
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
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
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要删除「$name」吗？',
                style: const TextStyle(color: _textPrimary, fontSize: 16)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 48,
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

  // ══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final hasSong = _currentSong != null;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: 20, right: 20, top: 16,
                        bottom: hasSong ? 80 : 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 20),
                          _buildSearchBar(),
                          const SizedBox(height: 28),
                          _buildQuickActions(),
                          if (_pinnedPlaylists.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            _buildPinnedSection(),
                          ],
                          const SizedBox(height: 28),
                          ..._buildCategories(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (hasSong) _buildNowPlayingBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Brand header ──
  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              colors: [_accent, Color(0xFF8B6CF6)],
            ),
          ),
          child: const Icon(Icons.music_note, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('苗苗music',
                style: TextStyle(color: _textPrimary, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
            Text('发现好音乐', style: TextStyle(color: _textSecondary, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  // ── Search bar ──
  Widget _buildSearchBar() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SearchPage()),
      ).then((_) { _bindPlayer(); _syncState(); if (mounted) setState(() {}); }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: const [
            Icon(Icons.search, size: 20, color: _textTertiary),
            SizedBox(width: 10),
            Text('搜索歌曲、歌手、歌单...',
                style: TextStyle(color: _textTertiary, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  // ── Quick actions (no cards) ──
  Widget _buildQuickActions() {
    return Column(
      children: [
        _actionRow(
          icon: Icons.favorite,
          iconColor: const Color(0xFFFF5E5E),
          label: '我的收藏',
          subtitle: '已收藏的歌曲',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FavoritesPage()),
          ).then((_) { _bindPlayer(); _syncState(); if (mounted) setState(() {}); }),
        ),
        const SizedBox(height: 2),
        _actionRow(
          icon: Icons.shuffle,
          iconColor: const Color(0xFF56C8B5),
          label: '随机播放',
          subtitle: '从置顶歌单随机选曲',
          onTap: _randomPlay,
        ),
      ],
    );
  }

  Widget _actionRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(color: _textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: _textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: _textTertiary),
          ],
        ),
      ),
    );
  }

  // ── Pinned section ──
  Widget _buildPinnedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('已置顶'.toUpperCase(),
            style: const TextStyle(color: _textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8, runSpacing: 8,
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
          color: _accent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(name,
            style: const TextStyle(color: _accent, fontSize: 13, fontWeight: FontWeight.w500)),
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
          border: Border.all(color: _accent.withOpacity(0.3)),
        ),
        child: const Text('+ 添加',
            style: TextStyle(color: _accent, fontSize: 13)),
      ),
    );
  }

  // ── Categories ──
  List<Widget> _buildCategories() {
    final widgets = <Widget>[];
    for (final entry in _categories.entries) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(entry.key.toUpperCase(),
            style: const TextStyle(color: _textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
      ));
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Wrap(
          spacing: 8, runSpacing: 8,
          children: entry.value.map((n) => _buildCatChip(n)).toList(),
        ),
      ));
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
          color: _surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(name,
            style: const TextStyle(color: _textPrimary, fontSize: 13)),
      ),
    );
  }

  // ── Now playing bar ──
  Widget _buildNowPlayingBar() {
    final isPlaying = _player.isPlaying;
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bg.withOpacity(0), _bg],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _openPlayer,
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      colors: [_accent, Color(0xFF8B6CF6)],
                    ),
                  ),
                  child: AnimatedBuilder(
                    animation: _barController,
                    builder: (_, __) => CustomPaint(
                      painter: _BarsPainter(_barController.value),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _openPlayer,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_currentSong?.name ?? '',
                          style: const TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(_currentSong?.singer ?? '',
                          style: const TextStyle(color: _textSecondary, fontSize: 12),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _player.togglePlayPause(),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 28,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final double progress;
  _BarsPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    const barCount = 4;
    final spacing = size.width / (barCount + 1);
    final maxHeight = size.height * 0.6;
    for (var i = 0; i < barCount; i++) {
      final x = spacing * (i + 1);
      final phase = (progress + i * 0.25) % 1.0;
      final h = maxHeight * (0.3 + 0.7 * sin(phase * pi));
      final top = (size.height - h) / 2;
      canvas.drawLine(Offset(x, top), Offset(x, top + h), paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.progress != progress;
}
