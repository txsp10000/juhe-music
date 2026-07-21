import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/favorites_service.dart';
import 'search_result_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusCtrl = FocusNode();
  final _focusClear = FocusNode();
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusCtrl.requestFocus());
  }

  Future<void> _loadHistory() async {
    final h = await SearchHistoryService.load();
    if (mounted) setState(() => _history = h);
  }

  void _doSearch(String keyword) async {
    await SearchHistoryService.save(keyword);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SearchResultPage(keyword: keyword),
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusCtrl.dispose();
    _focusClear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF171B26),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Focus(
          focusNode: _focusCtrl,
          child: TextField(
            controller: _controller,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            cursorColor: const Color(0xFF6890F9),
            textInputAction: TextInputAction.search,
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) _doSearch(v.trim());
            },
            decoration: const InputDecoration(
              hintText: '输入歌曲名、歌手名搜索...',
              hintStyle: TextStyle(color: Color(0xFF888888)),
              border: InputBorder.none,
            ),
          ),
        ),
        actions: [
          Focus(
            focusNode: _focusClear,
            child: Builder(
              builder: (ctx) {
                final f = Focus.of(ctx).hasFocus;
                return GestureDetector(
                  onTap: () {
                    _controller.clear();
                    SearchHistoryService.clear();
                    setState(() => _history = []);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: f ? const Color(0x1A6890F9) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: f ? Border.all(color: const Color(0xFF6890F9), width: 2) : null,
                    ),
                    child: const Text('清除', style: TextStyle(color: Color(0xFFF4F4F7), fontSize: 14)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: _history.isEmpty
          ? const Center(
              child: Text('暂无搜索历史', style: TextStyle(color: Color(0xFF8F919A), fontSize: 16)))
          : ListView.builder(
              itemCount: _history.length,
              itemBuilder: (_, i) {
                final kw = _history[i];
                return Focus(
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                      _doSearch(kw);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (ctx) {
                      final hasFocus = Focus.of(ctx).hasFocus;
                      return GestureDetector(
                        onTap: () => _doSearch(kw),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: hasFocus ? const Color(0x1A6890F9) : Colors.transparent,
                            border: hasFocus
                                ? const Border(bottom: BorderSide(color: Color(0xFF6890F9), width: 2))
                                : const Border(bottom: BorderSide(color: Color(0x15FFFFFF))),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.history, size: 20,
                                  color: hasFocus ? const Color(0xFF6890F9) : const Color(0xFF8F919A)),
                              const SizedBox(width: 14),
                              Text(kw, style: TextStyle(
                                  color: hasFocus ? Colors.white : const Color(0xFFE0E0E0), fontSize: 16)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
