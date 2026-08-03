import 'package:flutter/material.dart';

/// 真实歌单信息（从 API 动态获取）
class PlaylistInfo {
  final String name;
  final String id;
  final String coverUrl;
  const PlaylistInfo(this.name, this.id, {this.coverUrl = ''});
}

/// 歌单分类（只存分组和 ID，名称和封面从 API 实时获取）
/// 来源：GD Studio 官网 musicList.js 中的原始数据 + 已验证可用的网易云官方榜单
const playlistCategories = <String, List<String>>{
  '榜单': [
    '3778678',  // 热歌榜
    '19723756', // 飙升榜
    '3779629',  // 新歌榜
    '2884035',  // 原创榜
    '2250011882', // 抖音排行榜
  ],
  '语种': [
    '2809513713', // 欧美热歌榜
    '745956260',  // 韩语榜
    '5059644681', // 日语榜
    '60198',      // 美国Billboard榜
    '180106',     // UK排行榜周榜
  ],
  '风格': [
    '1978921795', // 电音榜
    '71384707',   // 古典榜
    '71385702',   // ACG榜
  ],
};
