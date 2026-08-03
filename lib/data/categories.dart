import 'package:flutter/material.dart';

/// 真实歌单信息（从 API 动态获取）
class PlaylistInfo {
  final String name;
  final String id;
  final String coverUrl;
  const PlaylistInfo(this.name, this.id, {this.coverUrl = ''});
}

/// 歌单分类（只存分组和 ID，名称和封面从 API 实时获取）
const playlistCategories = <String, List<String>>{
  '榜单': ['3778678', '3779629', '19723756', '2884035', '2250011882'],
  '语种': ['745956260', '60198', '180106'],
};
