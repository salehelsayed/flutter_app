import 'dart:async';

import 'package:flutter_app/debug/production_journeys/production_group_recovery_hold.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'live-gap hold blocks competing recovery and release restores it',
    () async {
      final gate = GroupRecoveryGate();
      final hold = ProductionGroupRecoveryHold(gate: gate);
      addTearDown(hold.dispose);
      await hold.acquire();
      expect(gate.tryRun(() async => 'periodic'), isNull);
      var queuedRan = false;
      final queued = gate.run(() async => queuedRan = true);
      await Future<void>.delayed(Duration.zero);
      expect(queuedRan, isFalse);
      hold.requireHeld();
      await hold.release();
      await queued;
      expect(queuedRan, isTrue);
      expect(gate.isActive, isFalse);
      expect(hold.requireHeld, throwsStateError);
      expect(await gate.tryRun(() async => 'periodic'), 'periodic');
    },
  );

  test(
    'hold waits for preceding recovery before establishing a live gap',
    () async {
      final gate = GroupRecoveryGate();
      final earlier = Completer<void>();
      final recovery = gate.run(() => earlier.future);
      final hold = ProductionGroupRecoveryHold(gate: gate);
      addTearDown(hold.dispose);
      final acquisition = hold.acquire();
      expect(hold.isHeld, isFalse);
      earlier.complete();
      await recovery;
      await acquisition;
      expect(hold.isHeld, isTrue);
      await hold.release();
      expect(gate.isActive, isFalse);
    },
  );

  test(
    'expired hold releases recovery and rejects scenario continuation',
    () async {
      final gate = GroupRecoveryGate();
      final hold = ProductionGroupRecoveryHold(
        gate: gate,
        maximumDuration: const Duration(milliseconds: 10),
      );
      await hold.acquire();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(gate.isActive, isFalse);
      expect(hold.requireHeld, throwsStateError);
      await expectLater(hold.release(), throwsStateError);
    },
  );

  test('timed-out acquisition cannot leave a later orphan hold', () async {
    final gate = GroupRecoveryGate();
    final earlier = Completer<void>();
    final recovery = gate.run(() => earlier.future);
    final hold = ProductionGroupRecoveryHold(
      gate: gate,
      acquisitionTimeout: const Duration(milliseconds: 10),
    );
    await expectLater(hold.acquire(), throwsA(isA<TimeoutException>()));
    earlier.complete();
    await recovery;
    await Future<void>.delayed(Duration.zero);
    expect(gate.isActive, isFalse);
    expect(hold.requireHeld, throwsStateError);
  });

  test('disposal releases the gate idempotently', () async {
    final gate = GroupRecoveryGate();
    final hold = ProductionGroupRecoveryHold(gate: gate);
    await hold.acquire();
    hold.dispose();
    hold.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(gate.isActive, isFalse);
    expect(hold.requireHeld, throwsStateError);
    await expectLater(hold.acquire(), throwsStateError);
  });
}
