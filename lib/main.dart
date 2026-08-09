import 'dart:async';
import 'package:flutter/material.dart';
import 'pages/main_page.dart';
import 'services/player_service.dart';
import 'tv/tv_routes.dart';
import 'services/settings_service.dart';
import 'services/audio_cache_service.dart';
import 'services/app_environment.dart';
import 'services/tv_cache_cleanup_service.dart';
import 'theme/app_design_tokens.dart';

Future<void> _bootstrapBackgroundServices() async {
  try {
    if (!isTvApp) await AudioCacheService().cleanupIncomplete();
    await PlayerService.init();
  } catch (e, st) {
    debugPrint('Background init failed: $e');
    debugPrintStack(stackTrace: st);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService().load();
  // TV uses the same media caches as mobile during a run, but starts every
  // launch with a clean cache so the previous session never persists.
  if (isTvApp) await TvCacheCleanupService.clearLegacyMediaCaches();
  runApp(const MusicApp());

  unawaited(_bootstrapBackgroundServices());
}

class NoTransitionPageTransitionsBuilder extends PageTransitionsBuilder {
  const NoTransitionPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    const isTv = isTvApp;
    final theme = ThemeData(
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
        titleLarge: TextStyle(
            color: AppDesignTokens.lyricWhite, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(
            color: AppDesignTokens.lyricWhite, fontWeight: FontWeight.w700),
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
    );

    if (isTv) {
      return MaterialApp(
        title: '汽水音乐',
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: NoTransitionPageTransitionsBuilder(),
            },
          ),
        ),
        routes: TvRoutes.builders,
        onGenerateRoute: TvRoutes.onGenerateRoute,
        initialRoute: TvRoutes.home,
      );
    }

    return MaterialApp(
      title: '汽水音乐',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const MainPage(),
    );
  }
}
