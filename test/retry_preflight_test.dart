import 'dart:math';

import 'package:down_any_media/models/download_errors.dart';
import 'package:down_any_media/services/preflight.dart';
import 'package:down_any_media/services/retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RetryPolicy backoff', () {
    test('delayFor stays within ±25% of the base', () {
      final policy = RetryPolicy(random: Random(42));
      for (var i = 0; i < 200; i++) {
        final d1 = policy.delayFor(1).inMilliseconds;
        expect(d1, inInclusiveRange(1500, 2500)); // 2s ±25%
        final d2 = policy.delayFor(2).inMilliseconds;
        expect(d2, inInclusiveRange(6000, 10000)); // 8s ±25%
        final d3 = policy.delayFor(3).inMilliseconds;
        expect(d3, inInclusiveRange(22500, 37500)); // 30s ±25%
      }
    });

    test('retries a retryable failure then succeeds', () async {
      final slept = <Duration>[];
      final policy = RetryPolicy(sleep: (d) async => slept.add(d));
      var calls = 0;
      final result = await policy.execute<String>(
        () async {
          calls++;
          if (calls < 3) throw const NetworkError();
          return 'ok';
        },
        classify: (e) => const UnknownError(),
      );
      expect(result, 'ok');
      expect(calls, 3);
      expect(slept.length, 2); // two backoffs before the 3rd try
    });

    test('gives up immediately on a non-retryable error', () async {
      final slept = <Duration>[];
      final policy = RetryPolicy(sleep: (d) async => slept.add(d));
      var calls = 0;
      await expectLater(
        policy.execute<void>(
          () async {
            calls++;
            throw const VideoUnavailableError();
          },
          classify: (e) => const UnknownError(),
        ),
        throwsA(isA<VideoUnavailableError>()),
      );
      expect(calls, 1);
      expect(slept, isEmpty);
    });

    test('stops after maxRetries and throws the last error', () async {
      final policy = RetryPolicy(sleep: (_) async {});
      var calls = 0;
      await expectLater(
        policy.execute<void>(
          () async {
            calls++;
            throw const NetworkError();
          },
          classify: (e) => const UnknownError(),
        ),
        throwsA(isA<NetworkError>()),
      );
      expect(calls, 4); // initial + 3 retries
    });

    test('non-AppError is classified before deciding retryability', () async {
      final policy = RetryPolicy(sleep: (_) async {});
      var calls = 0;
      await expectLater(
        policy.execute<void>(
          () async {
            calls++;
            throw StateError('boom');
          },
          classify: (e) => const VideoUnavailableError(), // not retryable
        ),
        throwsA(isA<VideoUnavailableError>()),
      );
      expect(calls, 1);
    });

    test('onRetry reports ascending attempt numbers', () async {
      final attempts = <int>[];
      final policy = RetryPolicy(sleep: (_) async {});
      try {
        await policy.execute<void>(
          () async => throw const NetworkError(),
          classify: (e) => const UnknownError(),
          onRetry: (_, attempt) => attempts.add(attempt),
        );
      } on AppError {
        // expected
      }
      expect(attempts, [1, 2, 3]);
    });
  });

  group('Preflight storage', () {
    test('known estimate blocks when free < 2x', () {
      final r = Preflight.checkStorage(
        estimatedBytes: 100 * 1024 * 1024,
        freeBytes: 150 * 1024 * 1024,
      );
      expect(r.isBlocked, isTrue);
      expect(r.blockingError, isA<StorageFullError>());
    });

    test('known estimate passes when free >= 2x', () {
      final r = Preflight.checkStorage(
        estimatedBytes: 100 * 1024 * 1024,
        freeBytes: 250 * 1024 * 1024,
      );
      expect(r.isBlocked, isFalse);
      expect(r.warning, isNull);
    });

    test('unknown size warns below the floor but never blocks', () {
      final r = Preflight.checkStorage(
        estimatedBytes: null,
        freeBytes: 100 * 1024 * 1024,
      );
      expect(r.isBlocked, isFalse);
      expect(r.warning, isNotNull);
    });

    test('unknown size above floor is clean', () {
      final r = Preflight.checkStorage(
        estimatedBytes: null,
        freeBytes: 2 * 1024 * 1024 * 1024,
      );
      expect(r.isBlocked, isFalse);
      expect(r.warning, isNull);
    });

    test('duplicate detection', () {
      expect(
        Preflight.isDuplicate('https://x/1', ['https://x/1', 'https://x/2']),
        isTrue,
      );
      expect(Preflight.isDuplicate('https://x/9', ['https://x/1']), isFalse);
    });

    test('humanBytes formats sensibly', () {
      expect(Preflight.humanBytes(500 * 1024 * 1024), '500 MB');
      expect(Preflight.humanBytes(2 * 1024 * 1024 * 1024), '2 GB');
    });
  });
}
