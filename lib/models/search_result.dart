import 'song.dart';

class SearchResult {
  final List<Song> list;
  final int total;
  final int page;
  final String source;

  SearchResult({
    required this.list,
    required this.total,
    this.page = 1,
    this.source = '',
  });
}

class PlatformResult {
  final Platform platform;
  final List<Song> songs;
  final int total;
  final String? error;

  PlatformResult({
    required this.platform,
    required this.songs,
    this.total = 0,
    this.error,
  });
}
