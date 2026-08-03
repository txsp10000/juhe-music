import 'package:flutter/material.dart';
import 'pages/main_page.dart';
import 'services/player_service.dart';
import 'services/settings_service.dart';
import 'services/audio_cache_service.dart';
import 'services/wifi_cache_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService().load();
  await AudioCacheService().cleanupIncomplete();
  await AudioCacheService().migrateOldFiles();
  await PlayerService.init();
  WifiCacheService().init();
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
        primaryColor: Colors.white,
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          surface: Color(0xFF1A1A1A),
        ),
        fontFamily: 'sans-serif',
      ),
      home: const MainPage(),
    );
  }
}
