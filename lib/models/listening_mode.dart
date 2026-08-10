import 'package:flutter/material.dart';

class ListeningMode {
  final String name;
  final int sceneModeId;
  final String subQueueType;
  final IconData icon;

  const ListeningMode({
    required this.name,
    required this.sceneModeId,
    required this.subQueueType,
    required this.icon,
  });
}

const listeningModes = <ListeningMode>[
  ListeningMode(
      name: '沉浸0.8x',
      sceneModeId: 14,
      subQueueType: 'scene_mode_slow_motion',
      icon: Icons.slow_motion_video_rounded),
  ListeningMode(
      name: '说唱',
      sceneModeId: 24,
      subQueueType: 'scene_mode_rap',
      icon: Icons.mic_rounded),
  ListeningMode(
      name: '抖音漫游',
      sceneModeId: 9,
      subQueueType: 'scene_mode_douyin_roam',
      icon: Icons.explore_rounded),
  ListeningMode(
      name: '夜晚',
      sceneModeId: 40,
      subQueueType: 'scene_mode_night_time',
      icon: Icons.dark_mode_rounded),
  ListeningMode(
      name: 'DJ模式',
      sceneModeId: 7,
      subQueueType: 'scene_mode_dj',
      icon: Icons.headphones_rounded),
  ListeningMode(
      name: '治愈',
      sceneModeId: 21,
      subQueueType: 'scene_mode_heal',
      icon: Icons.spa_rounded),
  ListeningMode(
      name: '躺平',
      sceneModeId: 44,
      subQueueType: 'scene_mode_lying_flat',
      icon: Icons.weekend_rounded),
  ListeningMode(
      name: '轻音乐',
      sceneModeId: 25,
      subQueueType: 'scene_mode_non_vocal',
      icon: Icons.music_note_rounded),
  ListeningMode(
      name: '深夜 EMO',
      sceneModeId: 4,
      subQueueType: 'scene_mode_emo',
      icon: Icons.nights_stay_rounded),
  ListeningMode(
      name: '小酒馆',
      sceneModeId: 18,
      subQueueType: 'scene_mode_drunk',
      icon: Icons.local_bar_rounded),
  ListeningMode(
      name: '助眠模式',
      sceneModeId: 8,
      subQueueType: 'scene_mode_bedtime',
      icon: Icons.bedtime_rounded),
  ListeningMode(
      name: 'KTV必点',
      sceneModeId: 31,
      subQueueType: 'scene_mode_ktv',
      icon: Icons.queue_music_rounded),
  ListeningMode(
      name: '动感健身',
      sceneModeId: 2,
      subQueueType: 'scene_mode_sport',
      icon: Icons.fitness_center_rounded),
  ListeningMode(
      name: '起床',
      sceneModeId: 38,
      subQueueType: 'scene_mode_get_up',
      icon: Icons.alarm_rounded),
  ListeningMode(
      name: '洗澡',
      sceneModeId: 41,
      subQueueType: 'scene_mode_bath',
      icon: Icons.shower_rounded),
  ListeningMode(
      name: '浪漫情歌',
      sceneModeId: 19,
      subQueueType: 'scene_mode_love_song',
      icon: Icons.favorite_rounded),
  ListeningMode(
      name: 'Chill 放松',
      sceneModeId: 3,
      subQueueType: 'scene_mode_chill',
      icon: Icons.self_improvement_rounded),
  ListeningMode(
      name: '摇滚',
      sceneModeId: 28,
      subQueueType: 'scene_mode_rock',
      icon: Icons.electric_bolt_rounded),
  ListeningMode(
      name: '快乐时光',
      sceneModeId: 5,
      subQueueType: 'scene_mode_happy',
      icon: Icons.sentiment_very_satisfied_rounded),
  ListeningMode(
      name: 'R&B',
      sceneModeId: 23,
      subQueueType: 'scene_mode_rnb',
      icon: Icons.album_rounded),
  ListeningMode(
      name: '电音',
      sceneModeId: 11,
      subQueueType: 'scene_mode_electronic',
      icon: Icons.graphic_eq_rounded),
  ListeningMode(
      name: '佛系时间',
      sceneModeId: 20,
      subQueueType: 'scene_mode_calm',
      icon: Icons.air_rounded),
  ListeningMode(
      name: '好运',
      sceneModeId: 45,
      subQueueType: 'scene_mode_lucky',
      icon: Icons.auto_awesome_rounded),
  ListeningMode(
      name: '怀旧老歌',
      sceneModeId: 16,
      subQueueType: 'scene_mode_nostalgic',
      icon: Icons.history_rounded),
  ListeningMode(
      name: '图书馆',
      sceneModeId: 48,
      subQueueType: 'scene_mode_library',
      icon: Icons.local_library_rounded),
  ListeningMode(
      name: '民谣',
      sceneModeId: 29,
      subQueueType: 'scene_mode_folk',
      icon: Icons.music_note_rounded),
  ListeningMode(
      name: '粤语',
      sceneModeId: 10,
      subQueueType: 'scene_mode_cantonese',
      icon: Icons.record_voice_over_rounded),
  ListeningMode(
      name: '甜美女声',
      sceneModeId: 17,
      subQueueType: 'scene_mode_sweet_girl',
      icon: Icons.face_rounded),
  ListeningMode(
      name: '通勤必听',
      sceneModeId: 1,
      subQueueType: 'scene_mode_commute',
      icon: Icons.directions_subway_rounded),
  ListeningMode(
      name: 'K-pop',
      sceneModeId: 22,
      subQueueType: 'scene_mode_kpop',
      icon: Icons.star_rounded),
  ListeningMode(
      name: '失恋必听',
      sceneModeId: 13,
      subQueueType: 'scene_mode_breakup',
      icon: Icons.heart_broken_rounded),
  ListeningMode(
      name: '日语',
      sceneModeId: 30,
      subQueueType: 'scene_mode_jpop',
      icon: Icons.language_rounded),
  ListeningMode(
      name: '欧美',
      sceneModeId: 15,
      subQueueType: 'scene_mode_english',
      icon: Icons.public_rounded),
  ListeningMode(
      name: '旅行',
      sceneModeId: 36,
      subQueueType: 'scene_mode_travel',
      icon: Icons.flight_takeoff_rounded),
  ListeningMode(
      name: '打扫',
      sceneModeId: 47,
      subQueueType: 'scene_mode_clean_up',
      icon: Icons.cleaning_services_rounded),
  ListeningMode(
      name: '摸鱼',
      sceneModeId: 34,
      subQueueType: 'scene_mode_fish',
      icon: Icons.free_breakfast_rounded),
  ListeningMode(
      name: '国风',
      sceneModeId: 12,
      subQueueType: 'scene_mode_chinese_style',
      icon: Icons.landscape_rounded),
  ListeningMode(
      name: '儿歌',
      sceneModeId: 26,
      subQueueType: 'scene_mode_child',
      icon: Icons.child_care_rounded),
  ListeningMode(
      name: '打游戏',
      sceneModeId: 37,
      subQueueType: 'scene_mode_game',
      icon: Icons.sports_esports_rounded),
  ListeningMode(
      name: '雨天',
      sceneModeId: 35,
      subQueueType: 'scene_mode_rain',
      icon: Icons.water_drop_rounded),
  ListeningMode(
      name: '驾车',
      sceneModeId: 33,
      subQueueType: 'scene_mode_car_mode',
      icon: Icons.directions_car_rounded),
  ListeningMode(
      name: '海边',
      sceneModeId: 39,
      subQueueType: 'scene_mode_beach',
      icon: Icons.beach_access_rounded),
  ListeningMode(
      name: '专注模式',
      sceneModeId: 6,
      subQueueType: 'scene_mode_focus',
      icon: Icons.center_focus_strong_rounded),
  ListeningMode(
      name: '乡村',
      sceneModeId: 27,
      subQueueType: 'scene_mode_country',
      icon: Icons.grass_rounded),
  ListeningMode(
      name: '古典',
      sceneModeId: 32,
      subQueueType: 'scene_mode_classic',
      icon: Icons.piano_rounded),
];
