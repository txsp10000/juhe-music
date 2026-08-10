import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:qishui_music/desktop/desktop_music_page.dart';
import 'package:qishui_music/main.dart';

void main() {
  testWidgets('MusicApp builds', (WidgetTester tester) async {
    await tester.pumpWidget(const MusicApp());
    if (Platform.isWindows) {
      expect(find.byType(DesktopMusicPage), findsOneWidget);
      return;
    }
    expect(find.text('模式选择'), findsOneWidget);
  });
}
