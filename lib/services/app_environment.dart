import 'package:flutter/services.dart';

/// Flutter supplies [appFlavor] when the app is built with `--flavor`.
/// True when running the Android TV flavor.
const bool isTvApp = appFlavor == 'tv';
