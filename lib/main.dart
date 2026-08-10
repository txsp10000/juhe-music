import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'desktop/desktop_music_page.dart';
import 'pages/main_page.dart';
import 'services/player_service.dart';
import 'tv/tv_routes.dart';
import 'services/settings_service.dart';
import 'services/audio_cache_service.dart';
import 'services/app_environment.dart';
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
            color: AppDesignTokens.lyricWhite,
            fontWeight: FontWeight.w800,
            decoration: TextDecoration.none),
        titleMedium: TextStyle(
            color: AppDesignTokens.lyricWhite,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none),
        bodyMedium: TextStyle(
            color: AppDesignTokens.lyricWhite, decoration: TextDecoration.none),
        bodySmall: TextStyle(
            color: AppDesignTokens.quietGrey, decoration: TextDecoration.none),
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
    final desktopTheme = theme.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F5F7),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF0071E3),
        surface: Color(0xFFFFFFFF),
        secondary: Color(0xFF6E6E73),
        onSurface: Color(0xFF1D1D1F),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF6E6E73)),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: Color(0xFF1D1D1F), fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: Color(0xFF1D1D1F), fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(color: Color(0xFF1D1D1F)),
        bodySmall: TextStyle(color: Color(0xFF6E6E73)),
      ),
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
      theme: Platform.isWindows ? desktopTheme : theme,
      home: Platform.isWindows ? const DesktopMusicPage() : const MainPage(),
    );
  }
}
