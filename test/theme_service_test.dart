import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:music/services/theme_service.dart';
import 'package:music/theme/app_design_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final redPng = img.encodePng(
    img.Image(width: 1, height: 1)..setPixelRgb(0, 0, 255, 0, 0),
  );

  setUp(ThemeService.reset);
  tearDown(ThemeService.reset);

  test('updates the theme color from cover bytes', () async {
    await ThemeService.updateFromCover(redPng);

    expect(ThemeService.bgHint.value, isNot(AppDesignTokens.queueBackground));
  });

  test('ignores stale cover color updates', () async {
    final update = ThemeService.updateFromCover(redPng);
    ThemeService.invalidateCover();

    await update;

    expect(ThemeService.bgHint.value, AppDesignTokens.queueBackground);
  });
}
