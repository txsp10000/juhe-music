import 'package:flutter_test/flutter_test.dart';

import 'package:music/api/music_api.dart';
import 'package:music/models/song.dart';

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

  test('parses documented encrypted CDN stream qualities', () {
    final bps = StreamQuality.fromJson({
      'quality': 'highest',
      'bitrate': 260443,
      'download_url': 'https://cdn.example.com/highest.m4a',
      'backup_url': 'https://backup.example.com/highest.m4a',
      'encryption': {'aes_key_hex': '00112233445566778899aabbccddeeff'},
    });
    final kbps = StreamQuality.fromJson({
      'quality': 'medium',
      'bitrate_kbps': 68,
      'download_url': 'https://cdn.example.com/medium.m4a',
      'encryption': {'aes_key_hex': 'ffeeddccbbaa99887766554433221100'},
    });
    expect(bps.bitrateKbps, 260);
    expect(bps.downloadUrl, 'https://cdn.example.com/highest.m4a');
    expect(bps.backupUrl, 'https://backup.example.com/highest.m4a');
    expect(bps.aesKeyHex, '00112233445566778899aabbccddeeff');
    expect(kbps.bitrateKbps, 68);
    expect(bps.rank, greaterThan(kbps.rank));
  });

  test('selects the highest available quality from stream info', () {
    final qualities = <StreamQuality>[
      StreamQuality.fromJson({
        'quality': 'highest',
        'bitrate_kbps': 260,
        'download_url': 'https://cdn.example.com/highest.m4a',
        'encryption': {'aes_key_hex': '00112233445566778899aabbccddeeff'},
      }),
      StreamQuality.fromJson({
        'quality': 'spatial',
        'bitrate_kbps': 321,
        'download_url': 'https://cdn.example.com/spatial.m4a',
        'encryption': {'aes_key_hex': '102132435465768798a9babcbddceeff'},
      }),
      StreamQuality.fromJson({
        'quality': 'medium',
        'bitrate_kbps': 68,
        'download_url': 'https://cdn.example.com/medium.m4a',
        'encryption': {'aes_key_hex': 'ffeeddccbbaa99887766554433221100'},
      }),
    ];

    final selected = selectStreamQuality(qualities);

    expect(selected.quality, 'spatial');
    expect(selected.bitrateKbps, 321);
  });
}
