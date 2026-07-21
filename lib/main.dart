import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'pages/home_page.dart';
import 'services/player_service.dart';

Future<void> main() async {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.miaomiao.music.channel.audio',
    androidNotificationChannelName: '苗苗music',
    androidNotificationOngoing: true,
  );
  PlayerService().init();
  runApp(const MusicApp());
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '苗苗music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6890F9),
        scaffoldBackgroundColor: const Color(0xFF0D0F14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6890F9),
          surface: Color(0xFF171B26),
        ),
        fontFamily: 'sans-serif',
      ),
      home: const HomePage(),
    );
  }
}
