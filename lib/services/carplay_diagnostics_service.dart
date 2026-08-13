import 'package:flutter/services.dart';

class CarPlayDiagnosticsService {
  static const _channel = MethodChannel('com.music/diagnostics');

  static Future<String> read() async {
    return await _channel.invokeMethod<String>('readCarPlayLog') ??
        '暂无 CarPlay 诊断记录。';
  }

  static Future<void> clear() async {
    await _channel.invokeMethod<void>('clearCarPlayLog');
  }
}
