import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_environment.dart';

/// Removes only the TV audio cache at startup. Lyrics and cover art are kept
/// so returning to a previously played song does not require redownloading
/// its metadata.
class TvCacheCleanupService {
  static const _legacyMediaDirectories = <String>['audio_cache'];

  static Future<void> clearLegacyMediaCaches() async {
    if (!isTvApp) return;

    try {
      final documents = await getApplicationDocumentsDirectory();
      for (final name in _legacyMediaDirectories) {
        final directory = Directory('${documents.path}/$name');
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    } catch (_) {}
  }
}
