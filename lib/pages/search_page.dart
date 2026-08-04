import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/glass_panel.dart';
import 'search_result_page.dart';

class SearchPage extends StatefulWidget {
  final bool embedded;
  const SearchPage({super.key, this.embedded = false});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<String> _history = [];
  Color _accent = AppDesignTokens.lyricWhite;
  Color _bgHint = AppDesignTokens.inkBlack;
  int _rankTab = 0;

  final _hot = const ['甲乙丙丁', '山风山风.等等我', '陈少熙 · 花落花', '红色高跟鞋', '痛仰乐队周边上线', '薛之谦', '汽水音乐 CITYLIVE'];
  final _side = const ['传说 A L', '失眠', '演员', '好走不见'];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _controller.addListener(_refreshChrome);
    _focusNode.addListener(_refreshChrome);
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

  void _refreshChrome() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _controller.removeListener(_refreshChrome);
    _focusNode.removeListener(_refreshChrome);
    _controller.dispose();
    _focusNode.dispose();
    ThemeService.accentColor.removeListener(_onThemeChange);
    ThemeService.bgHint.removeListener(_onThemeChange);
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final h = await SearchHistoryService.load();
    if (mounted) setState(() => _history = h);
  }

  Future<void> _doSearch(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    _focusNode.unfocus();
    await SearchHistoryService.save(trimmed);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => SearchResultPage(keyword: trimmed)));
  }

  Future<void> _clearHistory() async {
    for (final kw in List<String>.from(_history)) {
      await SearchHistoryService.removeOne(kw);
    }
    if (mounted) setState(() => _history.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      body: MusicScaffoldBackground(
        bgHint: _bgHint,
        accent: _accent,
        neutralize: true,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 14, 20, widget.embedded ? 106 : 24),
            children: [
              _buildSearchBar(),
              const SizedBox(height: 36),
              _buildHistory(),
              const SizedBox(height: 24),
              _buildBanner(),
              const SizedBox(height: 28),
              _buildRankTabs(),
              const SizedBox(height: 16),
              _buildRankCards(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(shape: BoxShape.circle, color: _accent.withOpacity(0.22)),
          child: Icon(Icons.music_note_rounded, color: _accent, size: 24),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.10), borderRadius: BorderRadius.circular(24)),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: AppDesignTokens.warmWhite.withOpacity(0.55), size: 25),
                Container(width: 2, height: 24, margin: const EdgeInsets.symmetric(horizontal: 9), color: _accent),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: !widget.embedded,
                    cursorColor: _accent,
                    style: AppDesignTokens.body(size: 16, weight: FontWeight.w800),
                    textInputAction: TextInputAction.search,
                    onSubmitted: _doSearch,
                    decoration: InputDecoration(
                      hintText: '🎁听歌赢皮皮朱签名照',
                      hintStyle: AppDesignTokens.body(size: 15, color: AppDesignTokens.warmWhite.withOpacity(0.35)),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Icon(Icons.document_scanner_outlined, color: AppDesignTokens.warmWhite.withOpacity(0.55), size: 22),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () {
            if (_controller.text.isNotEmpty) _controller.clear();
            if (!widget.embedded) Navigator.pop(context);
          },
          child: Text('取消', style: AppDesignTokens.body(size: 16, color: AppDesignTokens.warmWhite.withOpacity(0.72), weight: FontWeight.w800)),
        ),
      ],
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('历史搜索', style: AppDesignTokens.title(size: 18)),
            const Spacer(),
            GestureDetector(onTap: _clearHistory, child: Icon(Icons.delete_outline_rounded, color: AppDesignTokens.warmWhite.withOpacity(0.58), size: 28)),
          ],
        ),
        const SizedBox(height: 16),
        if (_history.isEmpty)
          MusicChip(label: '喊麦', accent: _accent, background: Colors.white.withOpacity(0.08))
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _history.map((kw) => MusicChip(label: kw, accent: _accent, background: Colors.white.withOpacity(0.08), onTap: () => _doSearch(kw))).toList(),
          ),
      ],
    );
  }

  Widget _buildBanner() {
    return Container(
      height: 104,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(colors: [const Color(0xFFEAE2CD), AppDesignTokens.surfaceFor(_bgHint, opacity: 0.45)]),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(left: 24, top: 18, child: Text('实体专辑', style: AppDesignTokens.body(size: 14, color: const Color(0xFF6F5744), weight: FontWeight.w900))),
          Positioned(left: 24, top: 42, child: Text('赵雷实体专辑\n上线苗苗music', style: AppDesignTokens.title(size: 21, color: const Color(0xFF1D1712)))),
          Positioned(right: 18, bottom: 12, child: Icon(Icons.album_rounded, color: _accent.withOpacity(0.80), size: 76)),
          Positioned(left: 160, bottom: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(border: Border.all(color: const Color(0xFF6F5744)), borderRadius: BorderRadius.circular(4)), child: Text('立即购买', style: AppDesignTokens.caption(color: const Color(0xFF6F5744))))),
        ],
      ),
    );
  }

  Widget _buildRankTabs() {
    final tabs = ['热门搜索', '热歌榜', '新歌榜', '音乐人歌曲榜'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = _rankTab == i;
          return GestureDetector(
            onTap: () => setState(() => _rankTab = i),
            child: Padding(
              padding: const EdgeInsets.only(right: 28),
              child: Text(tabs[i], style: AppDesignTokens.title(size: 21, color: active ? _accent : AppDesignTokens.warmWhite.withOpacity(0.32))),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildRankCards() {
    return SizedBox(
      height: 350,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _rankCard(_hot, wide: true),
          const SizedBox(width: 14),
          _rankCard(_side),
        ],
      ),
    );
  }

  Widget _rankCard(List<String> items, {bool wide = false}) {
    return Container(
      width: wide ? 318 : 220,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(color: AppDesignTokens.surfaceFor(_bgHint, opacity: 0.62).withOpacity(0.82), borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: List.generate(items.length, (i) {
          final hot = i < 2;
          return Expanded(
            child: GestureDetector(
              onTap: () => _doSearch(items[i]),
              child: Row(
                children: [
                  SizedBox(width: 34, child: Text('${i + 1}', style: AppDesignTokens.title(size: 20, color: hot ? _accent : AppDesignTokens.warmWhite.withOpacity(0.42)))),
                  Expanded(child: Text(items[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: AppDesignTokens.body(size: 17, color: AppDesignTokens.lyricWhite, weight: FontWeight.w800))),
                  if (hot) MusicChip(label: '热', accent: _accent, background: _accent.withOpacity(0.22), foreground: _accent),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
