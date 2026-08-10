import 'package:flutter_test/flutter_test.dart';
import 'package:qishui_music/models/listening_mode.dart';

void main() {
  test('常用模式包含全部场景且排除熟悉和新鲜模式', () {
    expect(listeningModes, hasLength(45));

    final ids = listeningModes.map((mode) => mode.sceneModeId).toSet();
    final types = listeningModes.map((mode) => mode.subQueueType).toSet();

    expect(ids, hasLength(listeningModes.length));
    expect(types, hasLength(listeningModes.length));
    expect(types, isNot(contains('familiar')));
    expect(types, isNot(contains('fresh')));
    expect(
        types,
        containsAll(<String>[
          'scene_mode_slow_motion',
          'scene_mode_rap',
          'scene_mode_night_time',
          'scene_mode_classic',
        ]));
  });
}
