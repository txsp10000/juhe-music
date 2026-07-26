import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class CoverCacheService {
  static final CoverCacheService _instance = CoverCacheService._();
  factory CoverCacheService() => _instance;
  CoverCacheService._();

  Directory? _dir;

  Future<Directory> _getDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}/cover_cache');
    if (!await _dir!.exists()) await _dir!.create(recursive: true);
    return _dir!;
  }

  Future<Uint8List?> load(String id) async {
    try {
      final dir = await _getDir();
      final file = File('${dir.path}/$id.jpg');
      if (await file.exists() && await file.length() > 0) {
        return await file.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> download(String id, String url) async {
    if (url.isEmpty) return null;
    final cached = await load(id);
    if (cached != null) return cached;
    try {
      final resp = await http.get(Uri.parse(url),
          headers: {'User-Agent': 'Mozilla/5.0'});
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        final dir = await _getDir();
        final file = File('${dir.path}/$id.jpg');
        await file.writeAsBytes(resp.bodyBytes);
        return resp.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getLocalPath(String id) async {
    try {
      final dir = await _getDir();
      final file = File('${dir.path}/$id.jpg');
      if (await file.exists() && await file.length() > 0) {
        return file.path;
      }
    } catch (_) {}
    return null;
  }
}
