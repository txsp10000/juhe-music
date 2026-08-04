import 'dart:async';
import 'package:flutter/material.dart';
import 'pages/main_page.dart';
import 'services/player_service.dart';
import 'services/settings_service.dart';
import 'services/audio_cache_service.dart';
import 'services/wifi_cache_service.dart';
import 'theme/app_design_tokens.dart';

Future<void> _bootstrapBackgroundServices() async {
  try {
    await AudioCacheService().cleanupIncomplete();
    await AudioCacheService().migrateOldFiles();
    await PlayerService.init();
    WifiCacheService().init();
  } catch (e, st) {
    debugPrint('Background init failed: $e');
    debugPrintStack(stackTrace: st);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService().load();
  runApp(const MusicApp());

  unawaited(_bootstrapBackgroundServices());
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '苗苗music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppDesignTokens.inkBlack,
        colorScheme: const ColorScheme.dark(
          primary: AppDesignTokens.lyricWhite,
          surface: AppDesignTokens.stageBlack,
          secondary: AppDesignTokens.quietGrey,
        ),
        fontFamily: 'sans-serif',
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: AppDesignTokens.lyricWhite, fontWeight: FontWeight.w800),
          titleMedium: TextStyle(color: AppDesignTokens.lyricWhite, fontWeight: FontWeight.w700),
          bodyMedium: TextStyle(color: AppDesignTokens.lyricWhite),
          bodySmall: TextStyle(color: AppDesignTokens.quietGrey),
        ),
        iconTheme: const IconThemeData(color: AppDesignTokens.lyricWhite),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppDesignTokens.lyricWhite,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppDesignTokens.stageBlack,
          modalBackgroundColor: AppDesignTokens.stageBlack,
          surfaceTintColor: Colors.transparent,
        ),
        splashColor: Colors.white10,
        highlightColor: Colors.white10,
      ),
      home: const MainPage(),
    );
  }
}
