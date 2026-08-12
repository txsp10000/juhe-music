import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music/models/song.dart';
import 'package:music/tv/tv_layout_metrics.dart';
import 'package:music/tv/widgets/tv_button.dart';
import 'package:music/tv/widgets/tv_focus_card.dart';
import 'package:music/tv/widgets/tv_queue_panel.dart';

void main() {
  testWidgets('TV layout keeps content inside a five-percent safe zone',
      (tester) async {
    late TvLayoutMetrics metrics;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(960, 540)),
          child: Builder(
            builder: (context) {
              metrics = TvLayoutMetrics.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(metrics.edge, 48);
    expect(metrics.topInset, 27);
    expect(metrics.bottomInset, 27);
  });

  testWidgets('icon-only TV buttons expose their label to accessibility',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvButton(
            icon: Icons.play_arrow_rounded,
            label: '播放',
            compact: true,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('播放'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('queue opens with the current song focused', (tester) async {
    final songs = List.generate(
      30,
      (index) => Song(
        id: '$index',
        name: '歌曲 $index',
        singer: '歌手 $index',
      ),
    );
    final currentFocusNode = FocusNode();
    addTearDown(currentFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(960, 540)),
          child: Scaffold(
            body: TvQueuePanel(
              songs: songs,
              currentIndex: 18,
              currentFocusNode: currentFocusNode,
              onPlay: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(currentFocusNode.hasFocus, isTrue);
    expect(find.text('歌曲 18'), findsOneWidget);
  });
  testWidgets('confirm key up from the previous route does not activate a card',
      (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusCard(
            autofocus: true,
            onTap: () => tapCount++,
            onLongPress: () {},
            child: const Text('Favorite song'),
          ),
        ),
      ),
    );
    await tester.pump();

    final focusNode = FocusManager.instance.primaryFocus!;
    focusNode.onKeyEvent!(
      focusNode,
      const KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.select,
        logicalKey: LogicalKeyboardKey.select,
        timeStamp: Duration.zero,
      ),
    );
    expect(tapCount, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect(tapCount, 1);
  });
}
