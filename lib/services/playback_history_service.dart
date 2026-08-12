import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

class PlaybackHistoryService {
  static const _key = 'playback_history';
  static const _maximumLength = 50;

  static Future<List<Song>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    return raw
        .map((value) {
          try {
            return Song.fromJson(jsonDecode(value) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();
  }

  static Future<void> record(Song song) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    raw.removeWhere((value) {
      try {
        final existing = Song.fromJson(
          jsonDecode(value) as Map<String, dynamic>,
        );
        return existing.id == song.id && existing.source == song.source;
      } catch (_) {
        return true;
      }
    });
    raw.insert(0, jsonEncode(song.toJson()));
    if (raw.length > _maximumLength) {
      raw.removeRange(_maximumLength, raw.length);
    }
    await prefs.setStringList(_key, raw);
  }
}
