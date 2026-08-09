import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import 'search_result_page.dart';

class SearchPage extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onShowPlayer;
  final VoidCallback? onOpenDrawer;
  const SearchPage(
      {super.key, this.embedded = false, this.onShowPlayer, this.onOpenDrawer});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<String> _history = [];
  Color _accent = AppDesignTokens.lyricWhite;
  Color _bgHint = AppDesignTokens.inkBlack;

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
        _accent =
            AppDesignTokens.readableAccent(ThemeService.accentColor.value);
        _bgHint = ThemeService.bgHint.value;
      });
    }
  }

  void _refreshChrome() {
    if (mounted) setState(() {});
  }

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
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SearchResultPage(
                keyword: trimmed, onShowPlayer: widget.onShowPlayer)));
    if (mounted) _loadHistory();
  }

  Future<void> _clearHistory() async {
    for (final kw in List<String>.from(_history)) {
      await SearchHistoryService.removeOne(kw);
    }
    if (mounted) setState(() => _history.clear());
  }

  Future<void> _removeHistory(String kw) async {
    await SearchHistoryService.removeOne(kw);
    if (mounted) setState(() => _history.remove(kw));
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 18, 20, widget.embedded ? 12 : 24),
        children: [
          _buildHeader(),
          const SizedBox(height: 22),
          _buildSearchBar(),
          const SizedBox(height: 30),
          _buildHistory(),
        ],
      ),
    );
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      body: widget.embedded
          ? content
          : MusicScaffoldBackground(
              bgHint: _bgHint, accent: _accent, child: content),
    );
  }

  Widget _buildHeader() {
    if (widget.embedded) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onOpenDrawer?.call(),
        child: Row(
          children: [
            const Icon(Icons.menu_rounded,
                color: AppDesignTokens.lyricWhite, size: 34),
            const SizedBox(width: 10),
            Text('模式选择', style: AppDesignTokens.title(size: 26)),
          ],
        ),
      );
    }
    return Row(
      children: [
        GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_rounded,
                color: AppDesignTokens.lyricWhite, size: 30)),
        const SizedBox(width: 10),
        Text('搜索', style: AppDesignTokens.display(size: 30)),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(26)),
      child: Row(
        children: [
          Icon(Icons.search_rounded,
              color: AppDesignTokens.warmWhite.withValues(alpha: 0.65),
              size: 25),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: !widget.embedded,
              cursorColor: _accent,
              style: AppDesignTokens.body(size: 16, weight: FontWeight.w800),
              textInputAction: TextInputAction.search,
              onSubmitted: _doSearch,
              decoration:
                  const InputDecoration(border: InputBorder.none, hintText: ''),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
                onTap: () => _controller.clear(),
                child: Icon(Icons.close_rounded,
                    color: AppDesignTokens.warmWhite.withValues(alpha: 0.65),
                    size: 20)),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('搜索历史', style: AppDesignTokens.title(size: 19)),
            const Spacer(),
            if (_history.isNotEmpty)
              GestureDetector(
                  onTap: _clearHistory,
                  child: Icon(Icons.delete_outline_rounded,
                      color: AppDesignTokens.warmWhite.withValues(alpha: 0.58),
                      size: 28)),
          ],
        ),
        const SizedBox(height: 16),
        if (_history.isEmpty)
          Text('暂无搜索历史',
              style: AppDesignTokens.body(
                  color: AppDesignTokens.warmWhite.withValues(alpha: 0.55)))
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _history.map((kw) => _historyChip(kw)).toList(),
          ),
      ],
    );
  }

  Widget _historyChip(String kw) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
              onTap: () => _doSearch(kw),
              child: Text(kw,
                  style:
                      AppDesignTokens.body(size: 14, weight: FontWeight.w800))),
          const SizedBox(width: 8),
          GestureDetector(
              onTap: () => _removeHistory(kw),
              child: Icon(Icons.close_rounded,
                  color: AppDesignTokens.warmWhite.withValues(alpha: 0.60),
                  size: 16)),
        ],
      ),
    );
  }
}
