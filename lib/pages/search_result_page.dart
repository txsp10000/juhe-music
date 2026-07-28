import 'package:flutter/material.dart';
import '../api/music_api.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import 'player_page.dart';

class SearchResultPage extends StatefulWidget {
  final String keyword;
  final bool fromPlayer;
  const SearchResultPage({super.key, required this.keyword, this.fromPlayer = false});

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  final _player = PlayerService();
  bool _loading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  List<Song> _songs = [];
  String _errorMsg = '';
  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _search({bool append = false}) async {
    try {
      final result = await MusicApi.searchRaw(widget.keyword, num: 20, page: _currentPage);
      if (!mounted) return;
      if (result.songs.isNotEmpty) {
        final picIds =
            result.songs.map((s) => s.picId.isNotEmpty ? s.picId : s.id).toList();
        MusicApi.getCovers(picIds).then((covers) {
          if (!mounted) return;
          for (final s in result.songs) {
            final key = s.picId.isNotEmpty ? s.picId : s.id;
            final cover = covers[key];
            if (cover != null && cover.isNotEmpty) s.cover = cover;
          }
          setState(() {});
        });
        setState(() {
          if (append) {
            _songs.addAll(result.songs);
          } else {
            _songs = result.songs;
          }
          _hasMore = result.songs.length >= 20;
          _loading = false;
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          if (!append) {
            _loading = false;
            _errorMsg = '重试30次后仍无结果';
          }
          _hasMore = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isLoadingMore = false;
        if (!append) _errorMsg = '搜索失败: $e';
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (!_hasMore || _isLoadingMore) return;
    _currentPage++;
    setState(() => _isLoadingMore = true);
    await _search(append: true);
  }

  void _playAt(int index) {
    if (_player.currentSong?.id == _songs[index].id) {
      if (widget.fromPlayer) {
        Navigator.pop(context);
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
      }
      return;
    }
    _player.playlist.clear();
    _player.playlist.addAll(_songs);
    _player.playAt(index);
    if (widget.fromPlayer) {
      Navigator.pop(context);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoadingMore,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0F14),
        appBar: AppBar(
          backgroundColor: const Color(0xFF171B26),
          title: Text(
            _loading ? '搜索中...' : '搜索结果',
            style: const TextStyle(color: Colors.white),
          ),
          leading: _isLoadingMore
              ? const SizedBox()
              : IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: [
              if (_loading)
                const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6890F9)))
              else if (_songs.isEmpty && !_isLoadingMore)
                Center(
                    child: Text(_errorMsg.isNotEmpty ? _errorMsg : '无搜索结果',
                        style: const TextStyle(
                            color: Color(0xFF8F919A), fontSize: 18),
                        textAlign: TextAlign.center))
              else
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollEndNotification &&
                        notification.metrics.pixels >= notification.metrics.maxScrollExtent - 100 &&
                        !_isLoadingMore &&
                        _hasMore) {
                      _loadNextPage();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    itemCount: _songs.length,
                    itemBuilder: (_, i) {
                      final s = _songs[i];
                      return InkWell(
                        onTap: () => _playAt(i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: Color(0x15FFFFFF))),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                child: Text('${i + 1}', textAlign: TextAlign.center,
                                    style: const TextStyle(color: Color(0xFF8F919A), fontSize: 16)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.name,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    Text(s.singer,
                                        style: const TextStyle(color: Color(0xFF8F919A), fontSize: 15)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              // 加载中遮罩
              if (_isLoadingMore)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF6890F9)),
                        SizedBox(height: 16),
                        Text('加载中...',
                            style: TextStyle(color: Colors.white, fontSize: 18)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
