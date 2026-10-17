import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/features/call/application/blocked_call_media_release.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _callId = CallId.parse('11111111-1111-4111-8111-111111111111');
final _otherCallId = CallId.parse('22222222-2222-4222-8222-222222222222');

CallCleanupReport _report(
  CallId callId, {
  required bool ready,
  List<String>? failed,
}) => CallCleanupReport(
  callId: callId,
  completed: ready,
  alreadyCompleted: false,
  terminalAckReady: ready,
  failedStepNames:
      failed ?? (ready ? const <String>[] : const <String>['call_media']),
);

final _endedSnapshot = CallSessionSnapshot.active(
  callId: _callId,
  contactPeerId: 'private-contact-identity',
  direction: CallDirection.incoming,
  state: CallState.ended,
  callerAccountPeerId: 'remote-account',
  callerDeviceId: 'remote-device',
  startedAt: DateTime.utc(2026, 10, 15, 12),
  endedAt: DateTime.utc(2026, 10, 15, 12, 0, 20),
  endReason: CallEndReason.callerCancelled,
);

void main() {
  late List<CallId> released;
  late BlockedCallMediaRelease tracker;

  setUp(() {
    released = <CallId>[];
    tracker = BlockedCallMediaRelease(
      onReleased: (callId) async => released.add(callId),
    );
  });

  test(
    'a close that finishes after a blocked report fires once per blocked episode, as when the mic prompt resolves',
    () async {
      final prompt = Completer<void>();
      final close = tracker.track(_callId, prompt.future);
      tracker.observe(_report(_callId, ready: false));

      prompt.complete();
      await close;
      await pumpEventQueue();

      expect(released, <CallId>[_callId]);
      tracker.observe(_report(_callId, ready: false));
      await tracker.track(_callId, Future<void>.value());
      await pumpEventQueue();
      expect(released, <CallId>[
        _callId,
        _callId,
      ], reason: 'a new blocked report re-arms once');
    },
  );

  // Codex probe (2026-10-15): the production cleanup bounds `call_media` to
  // 2 s and runs `call_signaling_context` next. A media close that completes
  // after its deadline but before the final report used to be dropped, and
  // the report then armed a release that nothing would ever fire.
  test(
    'a media close that completes between its deadline and the final blocked report still fires',
    () {
      fakeAsync((async) {
        final mediaClose = Completer<void>();
        final nextStep = Completer<void>();
        final cleanup = CallCleanupCoordinator(
          <CallCleanupStep>[
            CallCleanupStep(
              callMediaCleanupStep,
              (_) => tracker.track(_callId, mediaClose.future),
              requiredForTerminalAck: true,
            ),
            CallCleanupStep(
              'call_signaling_context',
              (_) => nextStep.future,
              requiredForTerminalAck: true,
            ),
          ],
          stepTimeout: const Duration(seconds: 2),
          onReport: tracker.observe,
        );
        CallCleanupReport? report;
        cleanup.cleanup(_endedSnapshot).then((value) => report = value);

        async.elapse(const Duration(seconds: 2));
        expect(report, isNull, reason: 'the next step is still running');
        mediaClose.complete();
        async.flushMicrotasks();
        nextStep.complete();
        async.flushMicrotasks();

        expect(report?.terminalAckReady, isFalse);
        expect(report?.failedStepNames, <String>[callMediaCleanupStep]);
        expect(released, <CallId>[_callId]);
      });
    },
  );

  test(
    'a remembered early close fires after the blocked report returns, not inside it',
    () async {
      await tracker.track(_callId, Future<void>.value());
      await pumpEventQueue();

      tracker.observe(_report(_callId, ready: false));
      expect(released, isEmpty, reason: 'never inside the report call stack');
      await pumpEventQueue();

      expect(released, <CallId>[_callId]);
      tracker.observe(_report(_callId, ready: false));
      await pumpEventQueue();
      expect(released, <CallId>[_callId], reason: 'one fire per early close');
    },
  );

  test('a ready report after an early close never fires', () async {
    await tracker.track(_callId, Future<void>.value());
    tracker.observe(_report(_callId, ready: true));
    await pumpEventQueue();

    expect(released, isEmpty);
  });

  test(
    'a ready report forgets an early close before a later blocked report',
    () async {
      await tracker.track(_callId, Future<void>.value());
      tracker.observe(_report(_callId, ready: true));
      tracker.observe(_report(_callId, ready: false));
      await pumpEventQueue();

      expect(released, isEmpty, reason: 'the later blocked report only arms');
      await tracker.track(_callId, Future<void>.value());
      await pumpEventQueue();
      expect(released, <CallId>[_callId]);
    },
  );

  test('a ready report disarms a call that was blocked earlier', () async {
    final close = Completer<void>();
    final tracked = tracker.track(_callId, close.future);
    tracker.observe(_report(_callId, ready: false));
    tracker.observe(_report(_callId, ready: true));

    close.complete();
    await tracked;
    await pumpEventQueue();

    expect(released, isEmpty);
  });

  test(
    'a blocked report for another step does not arm the media release',
    () async {
      final close = Completer<void>();
      final tracked = tracker.track(_callId, close.future);
      tracker.observe(
        _report(
          _callId,
          ready: false,
          failed: const <String>['call_signaling_context'],
        ),
      );

      close.complete();
      await tracked;
      await pumpEventQueue();

      expect(released, isEmpty);
    },
  );

  test(
    'a failed close never fires and still reports its error to the step',
    () async {
      final close = Completer<void>();
      final tracked = tracker.track(_callId, close.future);
      tracker.observe(_report(_callId, ready: false));

      close.completeError(StateError('close failed'));

      await expectLater(tracked, throwsStateError);
      await pumpEventQueue();
      expect(released, isEmpty);
    },
  );

  test('calls are tracked separately', () async {
    final first = Completer<void>();
    final second = Completer<void>();
    final a = tracker.track(_callId, first.future);
    final b = tracker.track(_otherCallId, second.future);
    tracker.observe(_report(_otherCallId, ready: false));

    first.complete();
    second.complete();
    await Future.wait(<Future<void>>[a, b]);
    await pumpEventQueue();

    expect(released, <CallId>[_otherCallId]);
    tracker.observe(_report(_callId, ready: false));
    await pumpEventQueue();
    expect(released, <CallId>[
      _otherCallId,
      _callId,
    ], reason: 'the first call remembered its own early close');
  });

  test('a throwing callback is contained', () async {
    final tracker = BlockedCallMediaRelease(
      onReleased: (_) async => throw StateError('retry failed'),
    );
    final close = Completer<void>();
    final tracked = tracker.track(_callId, close.future);
    tracker.observe(_report(_callId, ready: false));

    close.complete();
    await tracked;
    await pumpEventQueue();
  });
}
