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
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF171B26),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _controller,
          autofocus: false,
          focusNode: _focusNode,
          style: const TextStyle(color: Colors.white, fontSize: 20),
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
      body: _history.isEmpty
          ? const Center(
              child: Text('暂无搜索历史', style: TextStyle(color: Color(0xFF8F919A), fontSize: 18)))
          : ListView.builder(
              itemCount: _history.length,
              itemBuilder: (_, i) {
                final kw = _history[i];
                return InkWell(
                  onTap: () => _doSearch(kw),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0x15FFFFFF))),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.history, size: 20, color: Color(0xFF8F919A)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(kw, style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 18)),
                        ),
                        GestureDetector(
                          onTap: () async {
                            await SearchHistoryService.removeOne(kw);
                            setState(() => _history.removeAt(i));
                          },
                          child: const Icon(Icons.close, size: 18, color: Color(0xFF8F919A)),
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
