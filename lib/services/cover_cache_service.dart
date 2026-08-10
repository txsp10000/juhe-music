import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../utils/retry_helper.dart';

class CoverCacheService {
  static final CoverCacheService _instance = CoverCacheService._();
  factory CoverCacheService() => _instance;
  CoverCacheService._();

  Directory? _dir;
  final Map<String, Future<Uint8List?>> _inFlightDownloads = {};

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

    final existing = _inFlightDownloads[id];
    if (existing != null) return existing;
    final future = _downloadAndSave(id, url);
    _inFlightDownloads[id] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightDownloads[id], future)) {
        _inFlightDownloads.remove(id);
      }
    }
  }

  Future<Uint8List?> _downloadAndSave(String id, String url) async {
    try {
      return await RetryHelper.run(() async {
        final resp = await http.get(Uri.parse(url), headers: {
          'User-Agent': 'Mozilla/5.0'
        }).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          final dir = await _getDir();
          final file = File('${dir.path}/$id.jpg');
          final tempFile = File('${file.path}.tmp');
          await tempFile.writeAsBytes(resp.bodyBytes, flush: true);
          if (await file.exists()) await file.delete();
          await tempFile.rename(file.path);
          return await load(id);
        }
        throw Exception('HTTP ${resp.statusCode}');
      }, attempts: 3, delay: const Duration(seconds: 1));
    } catch (_) {
      return null;
    }
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
