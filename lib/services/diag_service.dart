import 'package:flutter/services.dart';

class DiagService {
  static const _channel = MethodChannel('com.miaomiao.music/diag');

  static void log(String tag, String message) {
    _channel.invokeMethod('write', {
      'tag': tag,
      'message': message,
    }).catchError((_) => null);
  }
}
