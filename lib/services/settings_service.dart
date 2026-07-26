import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Audio quality options (br parameter for API)
enum AudioQuality {
  low128(128, '128kbps (流畅)'),
  medium192(192, '192kbps (标准)'),
  high320(320, '320kbps (高品质)'),
  lossless740(740, '16bit无损'),
  lossless999(999, '24bit无损 (最高)');

  final int br;
  final String label;
  const AudioQuality(this.br, this.label);
}

class SettingsService {
  static final SettingsService _instance = SettingsService._();
  factory SettingsService() => _instance;
  SettingsService._();

  AudioQuality _quality = AudioQuality.lossless999;
  AudioQuality get quality => _quality;

  File? _file;

  Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/settings.json');
    return _file!;
  }

  Future<void> load() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        final br = json['br'] as int? ?? 999;
        _quality = AudioQuality.values.firstWhere(
          (q) => q.br == br,
          orElse: () => AudioQuality.lossless999,
        );
      }
    } catch (_) {}
  }

  Future<void> setQuality(AudioQuality q) async {
    _quality = q;
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode({'br': q.br}));
    } catch (_) {}
  }
}