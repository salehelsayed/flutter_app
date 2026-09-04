import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retry_coordinator.dart';

void main() {
  group('KeyExchangeRetryCoordinator', () {
    test('joins in-flight retry requests', () async {
      final completer = Completer<int>();
      var runCount = 0;
      final coordinator = KeyExchangeRetryCoordinator(
        performRetry: () {
          runCount += 1;
          return completer.future;
        },
      );

      final first = coordinator.retryNow(trigger: 'app_resumed');
      final second = coordinator.retryNow(trigger: 'online_transition');

      expect(identical(first, second), isTrue);
      expect(runCount, 1);

      completer.complete(2);

      expect(await first, 2);
      expect(await second, 2);
      expect(runCount, 1);
    });

    test('suppresses a recent non-zero retry within cooldown', () async {
      var now = DateTime.utc(2026, 4, 12, 18);
      var runCount = 0;
      final coordinator = KeyExchangeRetryCoordinator(
        performRetry: () async {
          runCount += 1;
          return 1;
        },
        cooldown: const Duration(seconds: 10),
        now: () => now,
      );

      expect(await coordinator.retryNow(trigger: 'app_resumed'), 1);

      now = now.add(const Duration(seconds: 5));
      expect(await coordinator.retryNow(trigger: 'online_transition'), 0);
      expect(runCount, 1);

      now = now.add(const Duration(seconds: 6));
      expect(await coordinator.retryNow(trigger: 'online_transition'), 1);
      expect(runCount, 2);
    });

    test(
      'does not suppress a follow-up when the prior retry sent nothing',
      () async {
        var now = DateTime.utc(2026, 4, 12, 18);
        var runCount = 0;
        final coordinator = KeyExchangeRetryCoordinator(
          performRetry: () async {
            runCount += 1;
            return 0;
          },
          cooldown: const Duration(seconds: 10),
          now: () => now,
        );

        expect(await coordinator.retryNow(trigger: 'app_resumed'), 0);

        now = now.add(const Duration(seconds: 5));
        expect(await coordinator.retryNow(trigger: 'online_transition'), 0);
        expect(runCount, 2);
      },
    );

    test(
      'fresh requests queue one run after an older in-flight retry',
      () async {
        final olderCompleter = Completer<int>();
        final freshCompleter = Completer<int>();
        var runCount = 0;
        final coordinator = KeyExchangeRetryCoordinator(
          performRetry: () {
            runCount += 1;
            return runCount == 1
                ? olderCompleter.future
                : freshCompleter.future;
          },
        );

        final older = coordinator.retryNow(trigger: 'online_transition');
        final fresh = coordinator.retryNow(
          trigger: 'call_wake_resume_reconcile',
          requireFresh: true,
        );
        final joinedFresh = coordinator.retryNow(
          trigger: 'call_wake_resume_reconcile',
          requireFresh: true,
        );

        expect(identical(fresh, older), isFalse);
        expect(identical(fresh, joinedFresh), isTrue);
        expect(runCount, 1);

        olderCompleter.complete(2);
        expect(await older, 2);
        await pumpEventQueue(times: 2);
        expect(runCount, 2);

        freshCompleter.complete(1);
        expect(await fresh, 1);
        expect(await joinedFresh, 1);
      },
    );

    test('fresh request bypasses a recent non-zero retry cooldown', () async {
      var now = DateTime.utc(2026, 4, 12, 18);
      var runCount = 0;
      final coordinator = KeyExchangeRetryCoordinator(
        performRetry: () async {
          runCount += 1;
          return runCount;
        },
        cooldown: const Duration(seconds: 10),
        now: () => now,
      );

      expect(await coordinator.retryNow(trigger: 'online_transition'), 1);
      now = now.add(const Duration(seconds: 1));

      expect(
        await coordinator.retryNow(
          trigger: 'call_wake_resume_reconcile',
          requireFresh: true,
        ),
        2,
      );
      expect(runCount, 2);
    });
  });
}
