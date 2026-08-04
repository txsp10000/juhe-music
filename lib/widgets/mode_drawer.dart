import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/categories.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../utils/toast.dart';
import 'glass_panel.dart';

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
  Color _accent = AppDesignTokens.lyricWhite;
  Color _bgHint = AppDesignTokens.inkBlack;

  final _modes = const [
    (Icons.waves_rounded, '沉浸0.8x'),
    (Icons.music_note_rounded, '抖音漫游'),
    (Icons.surround_sound_rounded, '超清全景声'),
    (Icons.spatial_audio_off_rounded, 'DJ模式'),
    (Icons.mic_external_on_rounded, '躺平'),
    (Icons.sentiment_dissatisfied_rounded, '深夜 EMO'),
    (Icons.nightlight_round, '助眠模式'),
    (Icons.bathtub_rounded, '洗澡'),
    (Icons.directions_run_rounded, '动感健身'),
    (Icons.eco_rounded, 'Chill 放松'),
    (Icons.mood_rounded, '快乐时光'),
    (Icons.equalizer_rounded, '电音'),
    (Icons.smart_display_rounded, '音乐视频'),
    (Icons.auto_awesome_rounded, '好运'),
    (Icons.account_balance_rounded, '图书馆'),
    (Icons.text_fields_rounded, '欧美'),
    (Icons.cleaning_services_rounded, '打扫'),
    (Icons.filter_vintage_rounded, '国风'),
  ];

  @override
  void initState() {
    super.initState();
    _loadPinned();
    _onThemeChange();
    ThemeService.accentColor.addListener(_onThemeChange);
    ThemeService.bgHint.addListener(_onThemeChange);
  }

  void _onThemeChange() {
    if (mounted) {
      setState(() {
        _accent = AppDesignTokens.readableAccent(ThemeService.accentColor.value);
        _bgHint = ThemeService.bgHint.value;
      });
    }
  }

  @override
  void dispose() {
    ThemeService.accentColor.removeListener(_onThemeChange);
    ThemeService.bgHint.removeListener(_onThemeChange);
    super.dispose();
  }

  static String _encode(PlaylistInfo p) => '${p.id}|${p.name}|${p.coverUrl}';
  static PlaylistInfo? _decode(String s) {
    final parts = s.split('|');
    if (parts.length < 2 || parts[0].isEmpty) return null;
    return PlaylistInfo(parts[1], parts[0], coverUrl: parts.length > 2 ? parts[2] : '');
  }

  Future<void> _loadPinned() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pinKey) ?? [];
    _pinnedPlaylists
      ..clear()
      ..addAll(list.map(_decode).whereType<PlaylistInfo>());
    if (mounted) setState(() {});
  }

  Future<void> _savePinned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinKey, _pinnedPlaylists.map(_encode).toList());
  }

  Future<void> _pinPlaylist(PlaylistInfo p) async {
    if (_pinnedPlaylists.any((e) => e.id == p.id)) return;
    _pinnedPlaylists.add(p);
    await _savePinned();
    if (mounted) { setState(() {}); Toast.show(context, '已置顶「${p.name}」'); }
  }

  Future<void> _unpinPlaylist(PlaylistInfo p) async {
    _pinnedPlaylists.removeWhere((e) => e.id == p.id);
    await _savePinned();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.80,
      backgroundColor: Colors.transparent,
      child: MusicScaffoldBackground(
        bgHint: _bgHint,
        accent: _accent,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 34, 22, 28),
            children: [
              _buildHeader(),
              const SizedBox(height: 34),
              _selectedDefault(),
              const SizedBox(height: 18),
              _wideMode('熟悉模式', Icons.favorite_rounded, widget.onOpenFavorites),
              const SizedBox(height: 14),
              _wideMode('新鲜模式', Icons.shuffle_rounded, widget.onRandomPlay),
              const SizedBox(height: 26),
              _buildModeGrid(),
              const SizedBox(height: 28),
              _buildPlaylistAccess(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('听歌模式', style: AppDesignTokens.display(size: 28)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: const Color(0xFFEBC7AD), borderRadius: BorderRadius.circular(10)), child: Text('SVIP', style: AppDesignTokens.body(size: 14, color: const Color(0xFF4C2A18), weight: FontWeight.w900))),
                  const SizedBox(width: 8),
                  Text('正在享受精准推荐', style: AppDesignTokens.body(size: 17, color: AppDesignTokens.warmWhite.withOpacity(0.62), weight: FontWeight.w800)),
                ],
              ),
            ],
          ),
        ),
        Column(
          children: [
            Row(children: [
              _smallCircle(Icons.play_circle_fill_rounded, const Color(0xFFFFFFFF)),
              const SizedBox(width: 8),
              _smallCircle(Icons.add_rounded, Colors.white.withOpacity(0.12)),
            ]),
            const SizedBox(height: 8),
            Text('双人一起听', style: AppDesignTokens.body(size: 14, color: AppDesignTokens.warmWhite.withOpacity(0.62), weight: FontWeight.w800)),
          ],
        ),
      ],
    );
  }

  Widget _smallCircle(IconData icon, Color bg) {
    return Container(width: 42, height: 42, decoration: BoxDecoration(shape: BoxShape.circle, color: bg), child: Icon(icon, color: bg == Colors.white ? _accent : AppDesignTokens.lyricWhite, size: 25));
  }

  Widget _selectedDefault() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        height: 76,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppDesignTokens.selectedPill, borderRadius: BorderRadius.circular(18)),
        child: Text('||| 默认模式', style: AppDesignTokens.title(size: 23, color: const Color(0xFF3B2418))),
      ),
    );
  }

  Widget _wideMode(String label, IconData icon, VoidCallback action) {
    return GestureDetector(
      onTap: () { Navigator.pop(context); action(); },
      child: Container(
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppDesignTokens.surfaceFor(_bgHint, opacity: 0.64).withOpacity(0.76), borderRadius: BorderRadius.circular(18)),
        child: Text(label, style: AppDesignTokens.title(size: 22)),
      ),
    );
  }

  Widget _buildModeGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 26,
      crossAxisSpacing: 8,
      childAspectRatio: 0.86,
      children: _modes.map((m) {
        return GestureDetector(
          onTap: () => Toast.show(context, '已切换到「${m.$2}」'),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(m.$1, color: AppDesignTokens.lyricWhite.withOpacity(0.90), size: 30),
              const SizedBox(height: 12),
              Text(m.$2, textAlign: TextAlign.center, maxLines: 2, style: AppDesignTokens.body(size: 14, color: AppDesignTokens.warmWhite.withOpacity(0.86), weight: FontWeight.w800)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPlaylistAccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('歌单分类', style: AppDesignTokens.title(size: 20)),
        const SizedBox(height: 12),
        if (_pinnedPlaylists.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: _pinnedPlaylists.map((p) => GestureDetector(onTap: () { Navigator.pop(context); widget.onSelectPlaylist(p); }, onLongPress: () => _unpinPlaylist(p), child: MusicChip(label: p.name, accent: _accent, active: true))).toList()),
        if (_pinnedPlaylists.isNotEmpty) const SizedBox(height: 14),
        ...playlistCategories.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.key, style: AppDesignTokens.caption(color: AppDesignTokens.warmWhite.withOpacity(0.62))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: entry.value.map((p) => GestureDetector(
                    onTap: () { Navigator.pop(context); widget.onSelectPlaylist(p); },
                    onLongPress: () => _pinPlaylist(p),
                    child: MusicChip(label: p.name, accent: _accent, background: Colors.white.withOpacity(0.08)),
                  )).toList(),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
