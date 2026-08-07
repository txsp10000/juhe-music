import 'package:flutter_test/flutter_test.dart';

import 'package:qishui_music/main.dart';

void main() {
  testWidgets('MusicApp builds', (WidgetTester tester) async {
    await tester.pumpWidget(const MusicApp());
    expect(find.text('模式选择'), findsOneWidget);
  });
}
