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
  final Map<String, _CoverRequest> _inFlightDownloads = {};

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
        final bytes = await file.readAsBytes();
        if (_isSupportedImage(bytes)) return bytes;
        await file.delete();
      }
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> resolve(String id, String source) async {
    final cached = await load(id);
    if (cached != null) return cached;
    if (source.isEmpty) return null;

    while (true) {
      final existing = _inFlightDownloads[id];
      if (existing != null) {
        final bytes = await existing.future;
        if (bytes != null || existing.source == source) return bytes;
        continue;
      }

      final future = _cacheSource(id, source);
      final request = _CoverRequest(source, future);
      _inFlightDownloads[id] = request;
      try {
        return await future;
      } finally {
        if (identical(_inFlightDownloads[id], request)) {
          _inFlightDownloads.remove(id);
        }
      }
    }
  }

  Future<Uint8List?> download(String id, String url) => resolve(id, url);

  Future<Uint8List?> _cacheSource(String id, String source) async {
    final uri = Uri.tryParse(source);
    if (uri != null && uri.scheme == 'file') {
      try {
        return await _saveAndLoad(id, await File.fromUri(uri).readAsBytes());
      } catch (_) {
        return null;
      }
    }
    if (uri == null || uri.scheme.isEmpty) {
      try {
        final file = File(source);
        if (await file.exists()) {
          return await _saveAndLoad(id, await file.readAsBytes());
        }
      } catch (_) {}
      return null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return _downloadAndSave(id, uri);
  }

  Future<Uint8List?> _downloadAndSave(String id, Uri uri) async {
    try {
      return await RetryHelper.run(() async {
        final resp = await http.get(uri, headers: {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        }).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          final cached = await _saveAndLoad(id, resp.bodyBytes);
          if (cached != null) return cached;
          throw const FormatException('Response is not a supported image');
        }
        throw Exception('HTTP ${resp.statusCode}');
      }, attempts: 3, delay: const Duration(seconds: 1));
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _saveAndLoad(String id, List<int> bytes) async {
    if (!_isSupportedImage(bytes)) return null;
    File? tempFile;
    try {
      final dir = await _getDir();
      final file = File('${dir.path}/$id.jpg');
      tempFile = File('${file.path}.tmp');
      await tempFile.writeAsBytes(bytes, flush: true);
      if (await file.exists()) await file.delete();
      await tempFile.rename(file.path);
      return await load(id);
    } catch (_) {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      return null;
    }
  }

  bool _isSupportedImage(List<int> bytes) {
    if (bytes.length < 12) return false;
    final isJpeg = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final isPng = bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a;
    final isGif = bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38;
    final isWebp = bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    final isBmp = bytes[0] == 0x42 && bytes[1] == 0x4d;
    return isJpeg || isPng || isGif || isWebp || isBmp;
  }

  Future<String?> getLocalPath(String id) async {
    try {
      final dir = await _getDir();
      final file = File('${dir.path}/$id.jpg');
      if (await file.exists() && await file.length() > 0) {
        final bytes = await file.readAsBytes();
        if (_isSupportedImage(bytes)) return file.path;
        await file.delete();
      }
    } catch (_) {}
    return null;
  }
}

class _CoverRequest {
  final String source;
  final Future<Uint8List?> future;

  const _CoverRequest(this.source, this.future);
}
