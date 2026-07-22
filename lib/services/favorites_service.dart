import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

class FavoritesService {
  static const _key = 'favorites';

  static Future<List<Song>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw.map((s) => Song.fromJson(jsonDecode(s))).toList();
  }

  static Future<void> save(Song song) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final exists = raw.any((s) {
      final item = Song.fromJson(jsonDecode(s));
      return item.id == song.id && item.source == song.source;
    });
    if (exists) return;
    raw.add(jsonEncode(song.toJson()));
    await prefs.setStringList(_key, raw);
  }

  static Future<void> removeAll(List<Song> songs) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final ids = songs.map((s) => '${s.id}_${s.source}').toSet();
    raw.removeWhere((s) {
      final item = Song.fromJson(jsonDecode(s));
      return ids.contains('${item.id}_${item.source}');
    });
    await prefs.setStringList(_key, raw);
  }

  static Future<void> remove(Song song) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.removeWhere((s) {
      final item = Song.fromJson(jsonDecode(s));
      return item.id == song.id;
    });
    await prefs.setStringList(_key, raw);
  }

  static Future<bool> isFavorite(Song song) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw.any((s) {
      final item = Song.fromJson(jsonDecode(s));
      return item.id == song.id;
    });
  }
}

class SearchHistoryService {
  static const _key = 'search_history';

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  static Future<void> save(String keyword) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.remove(keyword);
    list.insert(0, keyword);
    if (list.length > 20) list.removeLast();
    await prefs.setStringList(_key, list);
  }

  static Future<void> removeOne(String keyword) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.remove(keyword);
    await prefs.setStringList(_key, list);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
