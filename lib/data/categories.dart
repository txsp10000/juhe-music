import 'package:flutter/material.dart';

/// 真实歌单信息（网易云歌单ID）
class PlaylistInfo {
  final String name;
  final String id;
  const PlaylistInfo(this.name, this.id);
}

/// 歌单分类（实时从网络获取的真实歌单）
const playlistCategories = <String, List<PlaylistInfo>>{
  '榜单': [
    PlaylistInfo('热歌榜', '3778678'),
    PlaylistInfo('新歌榜', '3779629'),
    PlaylistInfo('飙升榜', '19723756'),
    PlaylistInfo('原创榜', '2884035'),
    PlaylistInfo('抖音排行榜', '2250011882'),
  ],
  '语种': [
    PlaylistInfo('韩语榜', '745956260'),
    PlaylistInfo('美国Billboard榜', '60198'),
    PlaylistInfo('UK排行榜周榜', '180106'),
  ],
};

/// 歌单图标映射（Material Icons，纯白无颜色线条风格）
const playlistIcons = <String, IconData>{
  '热歌榜': Icons.trending_up_outlined,
  '新歌榜': Icons.fiber_new_outlined,
  '飙升榜': Icons.rocket_launch_outlined,
  '原创榜': Icons.edit_outlined,
  '抖音排行榜': Icons.music_video_outlined,
  '韩语榜': Icons.translate_outlined,
  '美国Billboard榜': Icons.public_outlined,
  'UK排行榜周榜': Icons.language_outlined,
};
