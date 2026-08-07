import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_environment.dart';

/// Removes media caches left by older builds without touching user data such
/// as favorites, search history, or audio-quality preferences.
class TvCacheCleanupService {
  static const _legacyMediaDirectories = <String>[
    'audio_cache',
    'lyric_cache',
    'cover_cache',
  ];

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

    try {
      final preferences = await SharedPreferences.getInstance();
      final cachedPlaylistKeys = preferences.getKeys().where(
            (key) =>
                key.startsWith('playlist_name_') ||
                key.startsWith('playlist_cover_'),
          );
      for (final key in cachedPlaylistKeys) {
        await preferences.remove(key);
      }
    } catch (_) {}
  }
}
