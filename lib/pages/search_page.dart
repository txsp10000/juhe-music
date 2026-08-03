import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
import 'search_result_page.dart';
import '../services/theme_service.dart';

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
  Color _accent = Colors.white;
  Color _bgHint = const Color(0xFF000000);

  static const _textPrimary = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF999999);

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _onThemeChange();
    ThemeService.accentColor.addListener(_onThemeChange);
    ThemeService.bgHint.addListener(_onThemeChange);
  }

  void _onThemeChange() {
    if (mounted) setState(() {
      _accent = ThemeService.accentColor.value;
      _bgHint = ThemeService.bgHint.value;
    });
  }

  @override
  void dispose() {
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

  void _doSearch(String keyword) async {
    _focusNode.unfocus();
    await SearchHistoryService.save(keyword);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SearchResultPage(keyword: keyword),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgHint,
      appBar: AppBar(
        backgroundColor: _bgHint,
        automaticallyImplyLeading: false,
        leading: widget.embedded
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: _textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
        title: TextField(
          controller: _controller,
          autofocus: true,
          focusNode: _focusNode,
          style: const TextStyle(color: _textPrimary, fontSize: 17),
          cursorColor: _accent,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) { if (v.trim().isNotEmpty) _doSearch(v.trim()); },
          decoration: const InputDecoration(
            hintText: '搜索歌曲、歌手...',
            hintStyle: TextStyle(color: Color(0xFF4E515E)),
            border: InputBorder.none,
          ),
        ),
      ),
      body: _history.isEmpty
          ? const Center(child: Text('暂无搜索历史', style: TextStyle(color: _textSecondary, fontSize: 15)))
          : ListView.builder(
              itemCount: _history.length,
              itemBuilder: (_, i) {
                final kw = _history[i];
                return InkWell(
                  onTap: () => _doSearch(kw),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0x08FFFFFF))),
                    ),
                    child: Row(children: [
                      const Icon(Icons.history, size: 18, color: _textSecondary),
                      const SizedBox(width: 14),
                      Expanded(child: Text(kw, style: const TextStyle(color: _textPrimary, fontSize: 15))),
                      GestureDetector(
                        onTap: () async {
                          await SearchHistoryService.removeOne(kw);
                          setState(() => _history.removeAt(i));
                        },
                        child: const Icon(Icons.close, size: 16, color: Color(0xFF4E515E)),
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
