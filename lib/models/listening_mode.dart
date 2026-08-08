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
      name: '抖音漫游',
      sceneModeId: 9,
      subQueueType: 'scene_mode_douyin_roam',
      icon: Icons.explore_rounded),
  ListeningMode(
      name: 'DJ模式',
      sceneModeId: 7,
      subQueueType: 'scene_mode_dj',
      icon: Icons.headphones_rounded),
  ListeningMode(
      name: '躺平',
      sceneModeId: 44,
      subQueueType: 'scene_mode_lying_flat',
      icon: Icons.weekend_rounded),
  ListeningMode(
      name: '深夜 EMO',
      sceneModeId: 4,
      subQueueType: 'scene_mode_emo',
      icon: Icons.nights_stay_rounded),
  ListeningMode(
      name: '助眠模式',
      sceneModeId: 8,
      subQueueType: 'scene_mode_bedtime',
      icon: Icons.bedtime_rounded),
];
