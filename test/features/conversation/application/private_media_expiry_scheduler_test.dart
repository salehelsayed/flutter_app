import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/application/private_media_expiry_scheduler.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending cold-start recovery cannot re-arm after background', () async {
    final recovery = Completer<void>();
    final calls = <String>[];
    var recoveryCalls = 0;
    final runtime = PrivateMediaLifecycleForegroundRuntime(
      isForeground: () => true,
      recoverLocalLifecycle: () {
        recoveryCalls++;
        return recoveryCalls == 1 ? recovery.future : Future<void>.value();
      },
      startScheduler: () => calls.add('start'),
      stopScheduler: () => calls.add('stop'),
      disposeScheduler: () => calls.add('dispose'),
    );

    final coldStart = runtime.recoverColdStartAndArm();
    runtime.onBackgrounded();
    recovery.complete();
    await coldStart;
    expect(calls, ['stop']);

    await runtime.recoverResumeAndArm();
    expect(calls, ['stop', 'start']);
    runtime.dispose();
  });

  test('resume paused before recovery completion remains stopped', () async {
    final recovery = Completer<void>();
    final calls = <String>[];
    final runtime = PrivateMediaLifecycleForegroundRuntime(
      isForeground: () => true,
      recoverLocalLifecycle: () => recovery.future,
      startScheduler: () => calls.add('start'),
      stopScheduler: () => calls.add('stop'),
      disposeScheduler: () => calls.add('dispose'),
    );

    final resume = runtime.recoverResumeAndArm();
    runtime.onBackgrounded();
    recovery.complete();
    await resume;

    expect(calls, ['stop']);
    runtime.dispose();
  });

  test('cold recovery while paused does not arm until a real resume', () async {
    var foreground = false;
    final calls = <String>[];
    final runtime = PrivateMediaLifecycleForegroundRuntime(
      isForeground: () => foreground,
      recoverLocalLifecycle: () async => calls.add('recover'),
      startScheduler: () => calls.add('start'),
      stopScheduler: () => calls.add('stop'),
      disposeScheduler: () => calls.add('dispose'),
    );

    await runtime.recoverColdStartAndArm();
    expect(calls, ['recover']);

    foreground = true;
    await runtime.recoverResumeAndArm();
    expect(calls, ['recover', 'recover', 'start']);
    runtime.dispose();
  });

  test(
    'pause then second resume queues fresh recovery and only latest arms',
    () async {
      final firstRecovery = Completer<void>();
      final secondRecovery = Completer<void>();
      final calls = <String>[];
      var recoveryCalls = 0;
      final runtime = PrivateMediaLifecycleForegroundRuntime(
        isForeground: () => true,
        recoverLocalLifecycle: () {
          recoveryCalls++;
          calls.add('recover-$recoveryCalls');
          return recoveryCalls == 1
              ? firstRecovery.future
              : secondRecovery.future;
        },
        startScheduler: () => calls.add('start'),
        stopScheduler: () => calls.add('stop'),
        disposeScheduler: () => calls.add('dispose'),
      );

      final firstResume = runtime.recoverResumeAndArm();
      await Future<void>.delayed(Duration.zero);
      runtime.onBackgrounded();
      final secondResume = runtime.recoverResumeAndArm();

      expect(calls, ['recover-1', 'stop']);
      firstRecovery.complete();
      await firstResume;
      expect(calls, ['recover-1', 'stop', 'recover-2']);

      secondRecovery.complete();
      await secondResume;
      expect(calls, ['recover-1', 'stop', 'recover-2', 'start']);
      runtime.dispose();
    },
  );

  test(
    'only eligible incoming disappearing parents signal reschedule',
    () async {
      final changes = StreamController<ConversationMessage>.broadcast(
        sync: true,
      );
      var signalCount = 0;
      final subscription = directPrivateMediaExpiryRescheduleSignals(
        changes.stream,
      ).listen((_) => signalCount++);

      ConversationMessage message({
        required String id,
        required bool incoming,
        PrivateMediaPolicy policy = const PrivateMediaPolicy.ordinary(),
        PrivateMediaLifecycleState state = PrivateMediaLifecycleState.none,
        String status = 'delivered',
      }) => ConversationMessage(
        id: id,
        contactPeerId: 'contact-1',
        senderPeerId: 'sender-1',
        text: '',
        timestamp: '2026-07-11T00:00:00.000Z',
        status: status,
        isIncoming: incoming,
        createdAt: '2026-07-11T00:00:00.000Z',
        privateMediaPolicy: policy,
        privateMediaState: state,
      );

      changes
        ..add(message(id: 'ordinary-status-a', incoming: true))
        ..add(message(id: 'ordinary-status-b', incoming: true, status: 'read'))
        ..add(
          message(
            id: 'outgoing-disappearing',
            incoming: false,
            policy: PrivateMediaPolicy.disappearing(3600),
            state: PrivateMediaLifecycleState.available,
          ),
        )
        ..add(
          message(
            id: 'expired-disappearing',
            incoming: true,
            policy: PrivateMediaPolicy.disappearing(3600),
            state: PrivateMediaLifecycleState.expired,
          ),
        );
      expect(signalCount, 0);

      changes.add(
        message(
          id: 'new-incoming-disappearing',
          incoming: true,
          policy: PrivateMediaPolicy.disappearing(3600),
          state: PrivateMediaLifecycleState.available,
        ),
      );
      expect(signalCount, 1);

      await subscription.cancel();
      await changes.close();
    },
  );

  test('foreground timer expires at the next deadline without resume', () {
    fakeAsync((async) {
      var nowMs = 1000;
      int? nextExpiryMs = 1100;
      var sweeps = 0;
      final signals = StreamController<void>.broadcast(sync: true);
      final scheduler = PrivateMediaExpiryScheduler(
        loadNextExpiryAtMs: () async => nextExpiryMs,
        sweepDueExpiries: (_) async {
          sweeps++;
          nextExpiryMs = null;
        },
        rescheduleSignals: signals.stream,
        nowMs: () => nowMs,
      );

      scheduler.start();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 99));
      expect(sweeps, 0);
      nowMs = 1100;
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(sweeps, 1);

      scheduler.dispose();
      signals.close();
    });
  });

  test('new incoming disappearing signal reschedules an earlier deadline', () {
    fakeAsync((async) {
      var nowMs = 1000;
      int? nextExpiryMs = 2000;
      var sweeps = 0;
      final signals = StreamController<void>.broadcast(sync: true);
      final scheduler = PrivateMediaExpiryScheduler(
        loadNextExpiryAtMs: () async => nextExpiryMs,
        sweepDueExpiries: (_) async {
          sweeps++;
          nextExpiryMs = null;
        },
        rescheduleSignals: signals.stream,
        nowMs: () => nowMs,
      );

      scheduler.start();
      async.flushMicrotasks();
      nextExpiryMs = 1200;
      signals.add(null);
      async.flushMicrotasks();
      nowMs = 1200;
      async.elapse(const Duration(milliseconds: 200));
      async.flushMicrotasks();

      expect(sweeps, 1);
      scheduler.dispose();
      signals.close();
    });
  });

  test('background stop cancels and resume start re-arms', () {
    fakeAsync((async) {
      var nowMs = 1000;
      int? nextExpiryMs = 1100;
      var sweeps = 0;
      final scheduler = PrivateMediaExpiryScheduler(
        loadNextExpiryAtMs: () async => nextExpiryMs,
        sweepDueExpiries: (_) async {
          sweeps++;
          nextExpiryMs = null;
        },
        rescheduleSignals: const Stream<void>.empty(),
        nowMs: () => nowMs,
      );

      scheduler.start();
      async.flushMicrotasks();
      scheduler.stop();
      nowMs = 1200;
      async.elapse(const Duration(milliseconds: 200));
      async.flushMicrotasks();
      expect(sweeps, 0);

      scheduler.start();
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(sweeps, 1);
      scheduler.dispose();
    });
  });

  test('transient load failure automatically retries while foreground', () {
    fakeAsync((async) {
      var nowMs = 1000;
      var loadCalls = 0;
      var sweeps = 0;
      int? nextExpiryMs = 1100;
      final signals = StreamController<void>.broadcast(sync: true);
      final scheduler = PrivateMediaExpiryScheduler(
        loadNextExpiryAtMs: () async {
          loadCalls++;
          if (loadCalls == 1) throw StateError('transient load');
          return nextExpiryMs;
        },
        sweepDueExpiries: (_) async {
          sweeps++;
          nextExpiryMs = null;
        },
        rescheduleSignals: signals.stream,
        nowMs: () => nowMs,
        retryDelay: const Duration(milliseconds: 50),
      );

      scheduler.start();
      async.flushMicrotasks();
      nowMs = 1100;
      async.elapse(const Duration(milliseconds: 50));
      async.flushMicrotasks();

      expect(loadCalls, greaterThanOrEqualTo(2));
      expect(sweeps, 1);
      scheduler.dispose();
      signals.close();
    });
  });

  test('transient sweep failure automatically retries without a signal', () {
    fakeAsync((async) {
      var nowMs = 1000;
      int? nextExpiryMs = 1100;
      var sweepCalls = 0;
      final signals = StreamController<void>.broadcast(sync: true);
      final scheduler = PrivateMediaExpiryScheduler(
        loadNextExpiryAtMs: () async => nextExpiryMs,
        sweepDueExpiries: (_) async {
          sweepCalls++;
          if (sweepCalls == 1) throw StateError('transient sweep');
          nextExpiryMs = null;
        },
        rescheduleSignals: signals.stream,
        nowMs: () => nowMs,
        retryDelay: const Duration(milliseconds: 50),
      );

      scheduler.start();
      async.flushMicrotasks();
      nowMs = 1100;
      async.elapse(const Duration(milliseconds: 100));
      async.flushMicrotasks();
      expect(sweepCalls, 1);

      nowMs = 1150;
      async.elapse(const Duration(milliseconds: 50));
      async.flushMicrotasks();
      expect(sweepCalls, 2);
      scheduler.dispose();
      signals.close();
    });
  });

  test('scheduled deadline is a monotonic floor after wall-clock rollback', () {
    fakeAsync((async) {
      var nowMs = 1000;
      int? nextExpiryMs = 1100;
      final evaluationFloors = <int>[];
      final scheduler = PrivateMediaExpiryScheduler(
        loadNextExpiryAtMs: () async => nextExpiryMs,
        sweepDueExpiries: (evaluationFloorMs) async {
          evaluationFloors.add(evaluationFloorMs);
          if (evaluationFloorMs >= 1100) nextExpiryMs = null;
        },
        rescheduleSignals: const Stream<void>.empty(),
        nowMs: () => nowMs,
      );

      scheduler.start();
      async.flushMicrotasks();
      nowMs = 900;
      async.elapse(const Duration(milliseconds: 100));
      async.flushMicrotasks();

      expect(evaluationFloors, [1100]);
      scheduler.dispose();
    });
  });
}
