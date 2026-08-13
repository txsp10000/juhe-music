import 'package:flutter_test/flutter_test.dart';
import 'package:music/services/audio_cache_service.dart';
import 'package:music/utils/retry_helper.dart';

void main() {
  test('stops retrying when the error is not retryable', () async {
    var attempts = 0;

    await expectLater(
      RetryHelper.run<void>(
        () async {
          attempts++;
          throw StateError('cancelled');
        },
        attempts: 3,
        delay: Duration.zero,
        shouldRetry: (_) => false,
      ),
      throwsStateError,
    );

    expect(attempts, 1);
  });

  test('audio cache cancellation token is idempotent', () async {
    final token = AudioCacheCancellationToken();

    token.cancel();
    token.cancel();

    expect(token.isCancelled, isTrue);
    await expectLater(token.whenCancelled, completes);
  });
}
