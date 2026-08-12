import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music/models/song.dart';
import 'package:music/services/playback_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('records newest songs first and removes duplicates', () async {
    final first = Song(id: '1', name: 'First', singer: 'Singer');
    final second = Song(id: '2', name: 'Second', singer: 'Singer');

    await PlaybackHistoryService.record(first);
    await PlaybackHistoryService.record(second);
    await PlaybackHistoryService.record(first);

    final history = await PlaybackHistoryService.load();
    expect(history.map((song) => song.id), ['1', '2']);
  });

  test('keeps at most fifty songs', () async {
    for (var index = 0; index < 55; index++) {
      await PlaybackHistoryService.record(
        Song(id: '$index', name: 'Song $index', singer: 'Singer'),
      );
    }

    final history = await PlaybackHistoryService.load();
    expect(history, hasLength(50));
    expect(history.first.id, '54');
    expect(history.last.id, '5');
  });
}
