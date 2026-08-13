import 'dart:async';

class RetryHelper {
  static const int defaultAttempts = 5;
  static const Duration defaultDelay = Duration(seconds: 3);

  static Future<T> run<T>(
    Future<T> Function() action, {
    int attempts = defaultAttempts,
    Duration delay = defaultDelay,
    bool Function(Object error)? shouldRetry,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        return await action();
      } catch (e) {
        lastError = e;
        if (shouldRetry != null && !shouldRetry(e)) rethrow;
        if (attempt < attempts) {
          await Future.delayed(delay);
        }
      }
    }
    if (lastError is Exception) throw lastError;
    throw Exception(lastError?.toString() ?? '重试后仍失败');
  }
}
