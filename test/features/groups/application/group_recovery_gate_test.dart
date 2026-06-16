import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';

void main() {
  group('GroupRecoveryGate serialization', () {
    test(
      'run() serializes concurrent passes (second body waits for first)',
      () async {
        final gate = GroupRecoveryGate();
        final order = <String>[];
        final firstStarted = Completer<void>();
        final releaseFirst = Completer<void>();

        final f1 = gate.run(() async {
          order.add('first-start');
          firstStarted.complete();
          await releaseFirst.future;
          order.add('first-end');
        });

        // Enqueued while the first pass is still in-flight.
        final f2 = gate.run(() async {
          order.add('second-start');
          order.add('second-end');
        });

        await firstStarted.future;
        // The second pass must not have started while the first is open.
        expect(order, <String>['first-start']);
        // Both passes are accounted for in depth while one runs and one queues.
        expect(gate.activeDepthListenable.value, 2);

        releaseFirst.complete();
        await Future.wait(<Future<void>>[f1, f2]);

        expect(order, <String>[
          'first-start',
          'first-end',
          'second-start',
          'second-end',
        ]);
        expect(gate.isActive, isFalse);
        expect(gate.activeDepthListenable.value, 0);
      },
    );

    test('tryRun() returns null while a pass is active or queued', () async {
      final gate = GroupRecoveryGate();
      final release = Completer<void>();

      final f1 = gate.run(() async {
        await release.future;
      });
      expect(gate.isActive, isTrue);

      var skippedRan = false;
      final skipped = gate.tryRun(() async {
        skippedRan = true;
      });
      expect(skipped, isNull);

      release.complete();
      await f1;
      expect(skippedRan, isFalse);

      // Once the gate is idle, tryRun proceeds.
      var ran = false;
      final f2 = gate.tryRun(() async {
        ran = true;
      });
      expect(f2, isNotNull);
      await f2;
      expect(ran, isTrue);
    });

    test('activeDepthListenable reflects depth during a pass', () async {
      final gate = GroupRecoveryGate();
      final seen = <int>[];
      gate.activeDepthListenable.addListener(() {
        seen.add(gate.activeDepthListenable.value);
      });

      final release = Completer<void>();
      final f = gate.run(() async {
        expect(gate.activeDepthListenable.value, greaterThan(0));
        await release.future;
      });
      expect(gate.activeDepthListenable.value, 1);

      release.complete();
      await f;

      expect(gate.activeDepthListenable.value, 0);
      expect(seen, contains(1));
      expect(seen.last, 0);
    });

    test(
      'a throwing action releases the chain and propagates its error',
      () async {
        final gate = GroupRecoveryGate();

        await expectLater(
          gate.run(() async {
            throw StateError('boom');
          }),
          throwsA(isA<StateError>()),
        );
        expect(gate.isActive, isFalse);

        // Chain released: the next pass still runs.
        var ran = false;
        await gate.run(() async {
          ran = true;
        });
        expect(ran, isTrue);
      },
    );

    test('a throwing queued pass does not wedge the following pass', () async {
      final gate = GroupRecoveryGate();
      final order = <String>[];
      final releaseFirst = Completer<void>();

      final f1 = gate.run(() async {
        order.add('first');
        await releaseFirst.future;
      });
      final f2 = gate.run(() async {
        order.add('second-throws');
        throw StateError('second boom');
      });
      // Attach the error handler now so the rejection is never unhandled.
      final f2Handled = f2.then<void>((_) {}, onError: (Object _) {});
      final f3 = gate.run(() async {
        order.add('third');
      });

      releaseFirst.complete();
      await f1;
      await f2Handled;
      await f3;

      expect(order, <String>['first', 'second-throws', 'third']);
      expect(gate.isActive, isFalse);
    });
  });

  group('top-level gate helpers', () {
    setUp(() => groupRecoveryGate.resetForTest());
    tearDown(() => groupRecoveryGate.resetForTest());

    test('isGroupRecoveryInProgress tracks the global gate', () async {
      expect(isGroupRecoveryInProgress(), isFalse);
      final release = Completer<void>();
      final f = runWithGroupRecoveryGate(() async {
        expect(isGroupRecoveryInProgress(), isTrue);
        await release.future;
      });
      expect(isGroupRecoveryInProgress(), isTrue);
      release.complete();
      await f;
      expect(isGroupRecoveryInProgress(), isFalse);
    });

    test(
      'runWithGroupRecoveryGateOrSkip skips when the gate is busy',
      () async {
        final release = Completer<void>();
        final f1 = runWithGroupRecoveryGate(() async {
          await release.future;
        });

        var ran = false;
        final skipped = runWithGroupRecoveryGateOrSkip(() async {
          ran = true;
        });
        expect(skipped, isNull);

        release.complete();
        await f1;
        expect(ran, isFalse);
      },
    );
  });
}
