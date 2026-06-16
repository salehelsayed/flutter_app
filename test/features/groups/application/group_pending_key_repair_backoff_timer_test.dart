import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_pending_key_repair_backoff_timer.dart';

void main() {
  test(
    'advances 5s -> 30s -> 2m then clamps at 2m while sweeps repair nothing',
    () {
      fakeAsync((async) {
        final fireTimes = <Duration>[];
        final timer = GroupPendingKeyRepairBackoffTimer(
          runSweep: () async {
            fireTimes.add(async.elapsed);
            return 0;
          },
          schedule: const [
            Duration(seconds: 5),
            Duration(seconds: 30),
            Duration(minutes: 2),
          ],
        );
        timer.start();

        async.elapse(const Duration(seconds: 5));
        expect(fireTimes, hasLength(1));
        async.elapse(const Duration(seconds: 30));
        expect(fireTimes, hasLength(2));
        async.elapse(const Duration(minutes: 2));
        expect(fireTimes, hasLength(3));
        // Clamps at the final (2m) interval and keeps firing.
        async.elapse(const Duration(minutes: 2));
        expect(fireTimes, hasLength(4));

        expect(fireTimes[0], const Duration(seconds: 5));
        expect(fireTimes[1], const Duration(seconds: 35));
        expect(
          fireTimes[2],
          const Duration(seconds: 35) + const Duration(minutes: 2),
        );
        expect(
          fireTimes[3],
          const Duration(seconds: 35) + const Duration(minutes: 4),
        );

        timer.dispose();
      });
    },
  );

  test('stops after a sweep repairs at least one message', () {
    fakeAsync((async) {
      var calls = 0;
      final timer = GroupPendingKeyRepairBackoffTimer(
        runSweep: () async {
          calls++;
          return calls >= 2 ? 1 : 0; // repairs on the 2nd sweep
        },
        schedule: const [Duration(seconds: 5), Duration(seconds: 30)],
      );
      timer.start();

      async.elapse(const Duration(seconds: 5)); // sweep 1 -> 0, keeps going
      expect(calls, 1);
      expect(timer.isRunning, isTrue);

      async.elapse(const Duration(seconds: 30)); // sweep 2 -> 1 -> stops
      expect(calls, 2);
      expect(timer.isRunning, isFalse);

      // No further ticks once stopped.
      async.elapse(const Duration(minutes: 10));
      expect(calls, 2);
    });
  });

  test('dispose cancels a pending tick before it fires', () {
    fakeAsync((async) {
      var calls = 0;
      final timer = GroupPendingKeyRepairBackoffTimer(
        runSweep: () async {
          calls++;
          return 0;
        },
        schedule: const [Duration(seconds: 5)],
      );
      timer.start();
      timer.dispose();

      async.elapse(const Duration(minutes: 10));
      expect(calls, 0);
      expect(timer.isRunning, isFalse);
    });
  });

  test('a throwing sweep is non-fatal and keeps backing off', () {
    fakeAsync((async) {
      var calls = 0;
      final timer = GroupPendingKeyRepairBackoffTimer(
        runSweep: () async {
          calls++;
          throw StateError('sweep boom');
        },
        schedule: const [Duration(seconds: 5), Duration(seconds: 30)],
      );
      timer.start();

      async.elapse(const Duration(seconds: 5));
      expect(calls, 1);
      expect(timer.isRunning, isTrue);
      async.elapse(const Duration(seconds: 30));
      expect(calls, 2);
      expect(timer.isRunning, isTrue);

      timer.dispose();
    });
  });
}
