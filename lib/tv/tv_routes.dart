import 'package:flutter/material.dart';

import '../data/categories.dart';
import 'pages/tv_favorites_page.dart';
import 'pages/tv_now_playing_page.dart';
import 'pages/tv_playlist_detail_page.dart';
import 'pages/tv_playlist_page.dart';
import 'pages/tv_queue_page.dart';
import 'pages/tv_search_page.dart';
import 'pages/tv_search_results_page.dart';

abstract final class TvRoutes {
  static bool _focusHomeQueueOnNextBuild = false;

  static const home = '/tv/home';
  static const playlists = '/tv/playlists';
  static const playlistDetail = '/tv/playlist-detail';
  static const search = '/tv/search';
  static const searchResults = '/tv/search-results';
  static const favorites = '/tv/favorites';
  static const queue = '/tv/queue';

  static void requestHomeQueueFocus() {
    _focusHomeQueueOnNextBuild = true;
  }

  static bool consumeHomeQueueFocusRequest() {
    final requested = _focusHomeQueueOnNextBuild;
    _focusHomeQueueOnNextBuild = false;
    return requested;
  }

  static Map<String, WidgetBuilder> get builders => {
        home: (_) => const TvNowPlayingPage(),
        playlists: (_) => const TvPlaylistPage(),
        search: (_) => const TvSearchPage(),
        favorites: (_) => const TvFavoritesPage(),
        queue: (_) => const TvQueuePage(),
      };

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    if (settings.name == playlistDetail && settings.arguments is PlaylistInfo) {
      return _tvRoute(
        settings,
        TvPlaylistDetailPage(playlist: settings.arguments! as PlaylistInfo),
      );
    }
    if (settings.name == searchResults && settings.arguments is String) {
      return _tvRoute(
        settings,
        TvSearchResultsPage(keyword: settings.arguments! as String),
      );
    }
    return null;
  }

  static PageRouteBuilder<void> _tvRoute(RouteSettings settings, Widget page) {
    return PageRouteBuilder<void>(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => page,
    );
  }
}
