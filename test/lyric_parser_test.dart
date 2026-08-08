import 'package:flutter_test/flutter_test.dart';
import 'package:qishui_music/utils/lyric_parser.dart';

void main() {
  test('parses KRC line and per-character timing', () {
    final lines = parseLyrics(
      '[7140,1000]<0,200,0>你<200,300,0>好<500,500,0>啊',
    );

    expect(lines.single.text, '你好啊');
    expect(lyricTextAt(lines.single, 7139), '');
    expect(lyricTextAt(lines.single, 7140), '你');
    expect(lyricTextAt(lines.single, 7340), '你好');
    expect(lyricTextAt(lines.single, 7640), '你好啊');
  });
}
