import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Audio quality options (br parameter for API)
enum AudioQuality {
  medium('medium', 68, '标准 · 约 68kbps'),
  higher('higher', 132, '高品质 · 约 132kbps'),
  highest('highest', 260, '最高 · 约 260kbps'),
  hiRes('hi_res', 320, 'Hi-Res · 约 320kbps'),
  spatial('spatial', 321, '空间音频 · 约 321kbps');

  final String apiValue;
  final int br;
  final String label;
  const AudioQuality(this.apiValue, this.br, this.label);
}

class SettingsService {
  static final SettingsService _instance = SettingsService._();
  factory SettingsService() => _instance;
  SettingsService._();

  AudioQuality get quality => AudioQuality.highest;

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
      if (await file.exists()) await file.readAsString();
    } catch (_) {}
  }

  Future<void> setQuality(AudioQuality q) async {
    if (q != AudioQuality.highest) return;
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode({'quality': q.name}));
    } catch (_) {}
  }
}
