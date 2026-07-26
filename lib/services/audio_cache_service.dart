import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class AudioCacheService {
  static final AudioCacheService _instance = AudioCacheService._();
  factory AudioCacheService() => _instance;
  AudioCacheService._();

  static final _client = http.Client();
  Directory? _cacheDir;

  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${docDir.path}/audio_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  Future<String> getFilePath(String songId, [String? url]) async {
    final dir = await _getCacheDir();
    final ext = _extractExt(url);
    return '${dir.path}/$songId.$ext';
  }

  String _extractExt(String? url) {
    if (url == null || url.isEmpty) return 'mp3';
    final uri = Uri.tryParse(url);
    if (uri == null) return 'mp3';
    final path = uri.path.toLowerCase();
    if (path.endsWith('.flac')) return 'flac';
    if (path.endsWith('.m4a')) return 'm4a';
    if (path.endsWith('.aac')) return 'aac';
    if (path.endsWith('.wav')) return 'wav';
    if (path.endsWith('.ogg')) return 'ogg';
    return 'mp3';
  }

  Future<bool> isCached(String songId, [String? url]) async {
    final path = await getFilePath(songId, url);
    return File(path).exists();
  }

  Future<String?> download(String songId, String url) async {
    try {
      final path = await getFilePath(songId, url);
      final file = File(path);

      if (await file.exists()) return path;

      final dir = await _getCacheDir();
      final oldMp3 = File('${dir.path}/$songId.mp3');
      if (!path.endsWith('.mp3') && await oldMp3.exists()) {
        await oldMp3.delete();
      }

      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = 'Mozilla/5.0';
      final response = await _client.send(request);

      if (response.statusCode == 200) {
        final sink = file.openWrite();
        await response.stream.pipe(sink);
        await sink.close();
        if (await file.length() > 0) return path;
        await file.delete();
      }
    } catch (_) {}
    return null;
  }
}
