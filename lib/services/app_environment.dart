import 'package:flutter/services.dart';

/// Flutter supplies [appFlavor] when the app is built with `--flavor`.
/// TV intentionally uses online-only playback and never writes media caches.
const bool isTvApp = appFlavor == 'tv';
