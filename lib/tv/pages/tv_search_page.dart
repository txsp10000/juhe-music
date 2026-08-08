import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/favorites_service.dart';
import '../tv_layout_metrics.dart';
import '../tv_routes.dart';
import '../tv_tokens.dart';
import '../widgets/tv_focus_card.dart';
import '../widgets/tv_page_scaffold.dart';

class TvSearchPage extends StatefulWidget {
  const TvSearchPage({super.key});

  @override
  State<TvSearchPage> createState() => _TvSearchPageState();
}

class _TvSearchPageState extends State<TvSearchPage> {
  final _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  final _historyFocusNode = FocusNode();
  List<String> _history = [];
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode(onKeyEvent: _handleSearchInputKey);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _loadHistory();
  }

  @override
  void dispose() {
    _searchFocusNode
      ..removeListener(_onSearchFocusChanged)
      ..dispose();
    _historyFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await SearchHistoryService.load();
    if (mounted) setState(() => _history = history);
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  void _startEditing() {
    if (!_editing) setState(() => _editing = true);
    _searchFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  KeyEventResult _moveFocusOnArrow(
      KeyEvent event, LogicalKeyboardKey key, FocusNode target) {
    if (event is! KeyDownEvent || event.logicalKey != key) {
      return KeyEventResult.ignored;
    }
    target.requestFocus();
    return KeyEventResult.handled;
  }

  KeyEventResult _handleSearchInputKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final selection = _searchController.selection;
    final cursor = selection.isValid ? selection.extentOffset : 0;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        cursor >= _searchController.text.length &&
        _history.isNotEmpty) {
      _historyFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        _history.isNotEmpty) {
      _historyFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _startEditing();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _search() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    setState(() => _editing = false);
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await SearchHistoryService.save(keyword);
    if (!mounted) return;
    await Navigator.of(context)
        .pushNamed(TvRoutes.searchResults, arguments: keyword);
    if (!mounted) return;
    await _loadHistory();
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    final history = _history.take(16).toList();

    return TvPageScaffold(
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('搜索音乐', style: TvTokens.hero(size: metrics.font(48))),
            SizedBox(height: metrics.sectionGap),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 38, child: _leftPanel(metrics)),
                  SizedBox(width: metrics.value(28, minimum: 14)),
                  Expanded(flex: 62, child: _rightPanel(metrics, history)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leftPanel(TvLayoutMetrics metrics) {
    return Padding(
      padding: EdgeInsets.all(metrics.value(22, minimum: 12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: metrics.value(74, minimum: 50),
            padding: EdgeInsets.symmetric(
                horizontal: metrics.value(22, minimum: 12)),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius:
                  BorderRadius.circular(metrics.value(24, minimum: 14)),
              border: Border.all(
                color: _searchFocusNode.hasFocus
                    ? TvTokens.focus
                    : Colors.white.withValues(alpha: 0.1),
                width: _searchFocusNode.hasFocus ? 3 : 1,
              ),
            ),
            child: TextField(
              autofocus: true,
              readOnly: !_editing,
              showCursor: _editing,
              controller: _searchController,
              focusNode: _searchFocusNode,
              onTap: _startEditing,
              style: TvTokens.body(
                  size: metrics.font(24), weight: FontWeight.w700),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                border: InputBorder.none,
                icon: Icon(Icons.search_rounded,
                    color: TvTokens.muted,
                    size: metrics.value(28, minimum: 20)),
                hintText: _editing ? '输入歌名或者全拼' : '按确认键开始输入',
                hintStyle: TvTokens.body(
                    size: metrics.font(22), color: TvTokens.muted),
              ),
            ),
          ),
          SizedBox(height: metrics.value(18, minimum: 10)),
        ],
      ),
    );
  }

  Widget _rightPanel(TvLayoutMetrics metrics, List<String> history) {
    return Padding(
      padding: EdgeInsets.all(metrics.value(22, minimum: 12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('搜索记录', style: TvTokens.title(size: metrics.font(30))),
          SizedBox(height: metrics.value(20, minimum: 10)),
          Expanded(
            child: history.isEmpty
                ? Center(
                    child: Text('暂无搜索历史',
                        style: TvTokens.body(
                            size: metrics.font(24), color: TvTokens.muted)),
                  )
                : ListView.separated(
                    itemCount: history.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: metrics.value(12, minimum: 8)),
                    itemBuilder: (_, index) {
                      final keyword = history[index];
                      return TvSearchActionButton(
                        label: keyword,
                        autofocus: false,
                        focusNode: index == 0 ? _historyFocusNode : null,
                        onKeyEvent: index == 0
                            ? (_, event) => _moveFocusOnArrow(event,
                                LogicalKeyboardKey.arrowUp, _searchFocusNode)
                            : null,
                        onTap: () {
                          _searchController.text = keyword;
                          _searchController.selection =
                              TextSelection.collapsed(offset: keyword.length);
                          _search();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class TvSearchActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool autofocus;
  final bool selected;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;

  const TvSearchActionButton({
    super.key,
    required this.label,
    this.onTap,
    this.autofocus = false,
    this.selected = false,
    this.focusNode,
    this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    return TvFocusCard(
      onTap: onTap,
      autofocus: autofocus,
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      radius: metrics.value(20, minimum: 12),
      color: selected
          ? TvTokens.focus.withValues(alpha: 0.16)
          : Colors.transparent,
      padding: EdgeInsets.symmetric(
        horizontal: metrics.value(20, minimum: 12),
        vertical: metrics.value(16, minimum: 10),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TvTokens.body(
            size: metrics.font(24),
            color: selected ? TvTokens.focus : TvTokens.text,
            weight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
