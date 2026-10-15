import 'dart:math';

import '../models/download_errors.dart';

typedef SleepFn = Future<void> Function(Duration);

/// Exponential backoff with jitter for retryable failures (Feature 3c).
///
/// Defaults: 2 s, 8 s, 30 s (3 retries), ±25% jitter. The clock ([sleep]) and
/// [random] are injectable so timing is deterministic under test.
class RetryPolicy {
  RetryPolicy({
    List<Duration>? baseDelays,
    this.jitter = 0.25,
    Random? random,
    SleepFn? sleep,
  }) : baseDelays = baseDelays ??
           const [
             Duration(seconds: 2),
             Duration(seconds: 8),
             Duration(seconds: 30),
           ],
       _random = random ?? Random(),
       _sleep = sleep ?? Future.delayed;

  final List<Duration> baseDelays;
  final double jitter;
  final Random _random;
  final SleepFn _sleep;

  int get maxRetries => baseDelays.length;

  /// Backoff for a 1-based retry attempt, with ±[jitter] applied.
  Duration delayFor(int retryAttempt) {
    final base = baseDelays[(retryAttempt - 1).clamp(0, baseDelays.length - 1)];
    final factor = 1 + (_random.nextDouble() * 2 - 1) * jitter; // [1-j, 1+j]
    return Duration(milliseconds: (base.inMilliseconds * factor).round());
  }

  /// Run [action], retrying while the resulting [AppError] is retryable and
  /// attempts remain. Non-retryable errors and cancellation throw immediately.
  /// Non-[AppError] throwables are run through [classify] first.
  Future<T> execute<T>(
    Future<T> Function() action, {
    required AppError Function(Object error) classify,
    void Function(Duration delay, int attempt)? onRetry,
    bool Function()? isCancelled,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await action();
      } on Object catch (e) {
        final err = e is AppError ? e : classify(e);
        attempt += 1;
        final cancelled = isCancelled?.call() ?? false;
        if (!err.isRetryable || attempt > maxRetries || cancelled) {
          throw err;
        }
        final delay = delayFor(attempt);
        onRetry?.call(delay, attempt);
        await _sleep(delay);
      }
    }
  }
}
