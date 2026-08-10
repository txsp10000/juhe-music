import 'package:flutter_test/flutter_test.dart';

import 'package:qishui_music/api/music_api.dart';
import 'package:qishui_music/models/song.dart';
import 'package:qishui_music/services/settings_service.dart';

void main() {
  test('builds Soda cover URL using the documented resize suffix', () {
    final url = buildSodaImageUrl({
      'uri': 'tos-cn-v-2774c002/demo',
      'urls': ['https://p3-luna.douyinpic.com/img/'],
      'template_prefix': 'tplv-b829550vbb',
    });
    expect(
      url,
      'https://p3-luna.douyinpic.com/img/tos-cn-v-2774c002/demo~tplv-b829550vbb-resize:720:720.image',
    );
  });

  test('unwraps scene resource track_wrapper entities', () {
    final song = Song.fromApiJson({
      'entity': {
        'track_wrapper': {
          'track': {
            'id': 'track-1',
            'name': '测试歌曲',
            'artists': [
              {'name': '歌手 A'},
              {'name': '歌手 B'},
            ],
            'album': {'name': '测试专辑'},
            'duration_ms': 123456,
          },
        },
      },
    });
    expect(song.id, 'track-1');
    expect(song.singer, '歌手 A / 歌手 B');
    expect(song.duration, 123);
  });

  test('parses bitrate values reported in bps and kbps', () {
    final bps = StreamQuality.fromJson({
      'quality': 'highest',
      'bitrate': 260443,
      'stream_url': '/stream/1?quality=highest',
    });
    final kbps = StreamQuality.fromJson({
      'quality': 'medium',
      'bitrate_kbps': 68,
      'stream_url': '/stream/1?quality=medium',
    });
    expect(bps.bitrateKbps, 260);
    expect(kbps.bitrateKbps, 68);
    expect(bps.rank, greaterThan(kbps.rank));
  });

  test('selects the requested quality from stream info', () {
    final qualities = <StreamQuality>[
      StreamQuality.fromJson({
        'quality': 'highest',
        'bitrate_kbps': 260,
        'stream_url': '/stream/1?quality=highest',
      }),
      StreamQuality.fromJson({
        'quality': 'medium',
        'bitrate_kbps': 68,
        'stream_url': '/stream/1?quality=medium',
      }),
    ];

    final selected = selectStreamQuality(qualities, AudioQuality.medium);

    expect(selected.quality, 'medium');
    expect(selected.bitrateKbps, 68);
  });
}
