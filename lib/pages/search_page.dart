import 'package:flutter/material.dart';
import '../services/favorites_service.dart';
import 'search_result_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<String> _history = [];

  // ─── Design tokens ───
  static const _bg = Color(0xFF07080C);
  static const _surface = Color(0xFF0F1116);
  static const _accent = Color(0xFF5A78F0);
  static const _textPrimary = Color(0xFFEDEDF2);
  static const _textSecondary = Color(0xFF7C7F8C);

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
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
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        leading: IconButton(
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
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) _doSearch(v.trim());
          },
          decoration: const InputDecoration(
            hintText: '搜索歌曲、歌手...',
            hintStyle: TextStyle(color: Color(0xFF4E515E)),
            border: InputBorder.none,
          ),
        ),
      ),
      body: _history.isEmpty
          ? const Center(
              child: Text('暂无搜索历史', style: TextStyle(color: _textSecondary, fontSize: 15)))
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
                    child: Row(
                      children: [
                        const Icon(Icons.history, size: 18, color: _textSecondary),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(kw, style: const TextStyle(color: _textPrimary, fontSize: 15)),
                        ),
                        GestureDetector(
                          onTap: () async {
                            await SearchHistoryService.removeOne(kw);
                            setState(() => _history.removeAt(i));
                          },
                          child: const Icon(Icons.close, size: 16, color: Color(0xFF4E515E)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
