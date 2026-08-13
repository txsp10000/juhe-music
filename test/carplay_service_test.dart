import 'package:flutter_test/flutter_test.dart';
import 'package:music/models/song.dart';
import 'package:music/services/carplay_service.dart';

void main() {
  test('CarPlay selection resolves the visible song after list reordering', () {
    final songs = [
      Song(id: 'new', name: 'New', singer: 'Singer', source: 'soda'),
      Song(id: 'visible', name: 'Visible', singer: 'Singer', source: 'soda'),
    ];

    expect(findCarPlaySongIndex(songs, 'visible', 'soda'), 1);
    expect(findCarPlaySongIndex(songs, 'missing', 'soda'), -1);
  });

  test('CarPlay selection distinguishes duplicate IDs from different sources',
      () {
    final songs = [
      Song(id: 'same', name: 'A', singer: 'Singer', source: 'source-a'),
      Song(id: 'same', name: 'B', singer: 'Singer', source: 'source-b'),
    ];

    expect(findCarPlaySongIndex(songs, 'same', 'source-b'), 1);
  });

  test('CarPlay lyric change keeps exactly 500ms of visual delay', () {
    expect(
      carPlayLyricChangeDelayMs(
        positionMs: 4200,
        nextLyricStartMs: 5000,
      ),
      1300,
    );
    expect(
      carPlayLyricChangeDelayMs(
        positionMs: 5600,
        nextLyricStartMs: 5000,
      ),
      0,
    );
    expect(
      carPlayLyricChangeDelayMs(
        positionMs: 4200,
        nextLyricStartMs: null,
      ),
      isNull,
    );
  });
}
