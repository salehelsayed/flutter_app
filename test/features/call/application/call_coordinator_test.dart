import 'dart:async';

import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _callId = CallId.parse('55555555-5555-4555-8555-555555555555');
final _now = DateTime.utc(2026, 8, 30, 12);

CallEvent _event(
  CallEventType type, {
  String? eventId,
  DateTime? occurredAt,
  DateTime? expiresAt,
  IncomingCallAdmission? admission,
}) => CallEvent(
  type: type,
  eventId: eventId ?? type.name,
  occurredAt: occurredAt ?? _now,
  callId: _callId,
  contactPeerId: 'contact-a',
  localAccountPeerId: 'local-account',
  localDeviceId: 'local-device',
  remoteAccountPeerId: 'contact-a',
  remoteDeviceId: 'contact-device',
  expiresAt: expiresAt,
  admission: admission ?? IncomingCallAdmission.accepted,
);

final class _MemoryHistoryRepository implements CallHistoryRepository {
  final Map<CallId, CallHistoryEntry> rows = <CallId, CallHistoryEntry>{};

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => rows[callId];

  @override
  Future<List<CallHistoryEntry>> listForContact(
    String contactAccountPeerId,
  ) async => rows.values
      .where((row) => row.contactAccountPeerId == contactAccountPeerId)
      .toList();

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    rows.putIfAbsent(entry.callId, () => entry);
  }
}

final class _ThrowingHistoryRepository implements CallHistoryRepository {
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(
    String contactAccountPeerId,
  ) async => const <CallHistoryEntry>[];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    throw StateError('history unavailable');
  }
}

final class _RecordingExecutor implements CallEffectExecutor {
  _RecordingExecutor({this.gate, this.blockedEffect});

  final Completer<void>? gate;
  final CallEffectType? blockedEffect;
  final List<CallEffectType> effects = <CallEffectType>[];

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    effects.add(effect.type);
    if (gate != null &&
        effect.type ==
            (blockedEffect ?? CallEffectType.prepareOutgoingInvite)) {
      await gate!.future;
    }
    return null;
  }
}

final class _ImmediateAcceptExecutor implements CallEffectExecutor {
  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async => switch (effect.type) {
    CallEffectType.prepareOutgoingInvite => _event(
      CallEventType.outgoingInviteReady,
      eventId: 'invite-ready',
    ),
    CallEffectType.sendInvite => _event(
      CallEventType.remoteAccept,
      eventId: 'immediate-accept',
    ),
    _ => null,
  };
}

CallCoordinator _coordinator({
  required _MemoryHistoryRepository history,
  CallEffectExecutor? executor,
  CallCleanupCoordinator? cleanup,
  int maxPendingEvents = 64,
  CallTimerScheduler? timerScheduler,
  DateTime Function()? clock,
  Duration effectTimeout = const Duration(seconds: 15),
  Duration mediaPreparationTimeout = const Duration(seconds: 45),
  Duration terminalEffectTimeout = const Duration(seconds: 5),
  void Function(CallCoordinatorInternalFailure failure)? onInternalFailure,
  void Function(
    CallEventType trigger,
    CallState resultingState,
    CallEndReason? endReason,
  )?
  onAppliedStateTransition,
}) => CallCoordinator(
  reducer: const CallReducer(),
  cleanupCoordinator:
      cleanup ?? CallCleanupCoordinator(const <CallCleanupStep>[]),
  historyProjector: CallHistoryProjector(history),
  effectExecutor: executor ?? _RecordingExecutor(),
  clock: clock ?? () => _now,
  idSource: () => _callId,
  maxPendingEvents: maxPendingEvents,
  timerScheduler: timerScheduler,
  mediaPreparationTimeout: mediaPreparationTimeout,
  effectTimeout: effectTimeout,
  terminalEffectTimeout: terminalEffectTimeout,
  onInternalFailure: onInternalFailure,
  onAppliedStateTransition: onAppliedStateTransition,
);

final class _Scheduled {
  _Scheduled(this.delay, this.callback);

  final Duration delay;
  final Future<void> Function() callback;
  bool canceled = false;
}

final class _FakeTimerHandle implements CallTimerHandle {
  _FakeTimerHandle(this.scheduled);

  final _Scheduled scheduled;

  @override
  bool get isActive => !scheduled.canceled;

  @override
  void cancel() => scheduled.canceled = true;
}

final class _FakeTimerScheduler implements CallTimerScheduler {
  final List<_Scheduled> scheduled = <_Scheduled>[];

  @override
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback) {
    final value = _Scheduled(delay, callback);
    scheduled.add(value);
    return _FakeTimerHandle(value);
  }

  Future<void> fire(Duration delay) async {
    final value = scheduled.firstWhere(
      (candidate) => candidate.delay == delay && !candidate.canceled,
    );
    await value.callback();
  }
}

void main() {
  test(
    'applied transition observer reports fixed reducer enums only',
    () async {
      final history = _MemoryHistoryRepository();
      final transitions =
          <
            ({
              CallEventType trigger,
              CallState resultingState,
              CallEndReason? endReason,
            })
          >[];
      final coordinator = _coordinator(
        history: history,
        onAppliedStateTransition: (trigger, resultingState, endReason) {
          transitions.add((
            trigger: trigger,
            resultingState: resultingState,
            endReason: endReason,
          ));
        },
      );
      addTearDown(coordinator.dispose);

      await coordinator.dispatch(_event(CallEventType.place));
      await coordinator.dispatch(_event(CallEventType.place));
      await coordinator.dispatch(_event(CallEventType.cancel));

      expect(transitions, <Object>[
        (
          trigger: CallEventType.place,
          resultingState: CallState.preparing,
          endReason: null,
        ),
        (
          trigger: CallEventType.cancel,
          resultingState: CallState.ended,
          endReason: CallEndReason.callerCancelled,
        ),
      ]);
    },
  );

  test('transition observer failure cannot change dispatch outcome', () async {
    final history = _MemoryHistoryRepository();
    var observerCalls = 0;
    final coordinator = _coordinator(
      history: history,
      onAppliedStateTransition: (_, _, _) {
        observerCalls++;
        throw StateError('diagnostic unavailable');
      },
    );
    addTearDown(coordinator.dispose);

    final reduction = await coordinator.dispatch(_event(CallEventType.place));

    expect(reduction.decision, CallEventDecision.applied);
    expect(reduction.snapshot.state, CallState.preparing);
    expect(coordinator.activeSession?.state, CallState.preparing);
    expect(observerCalls, 1);
  });

  test(
    'ordered effects run outside the reducer and publish snapshots',
    () async {
      final history = _MemoryHistoryRepository();
      final executor = _RecordingExecutor();
      final coordinator = _coordinator(history: history, executor: executor);
      addTearDown(coordinator.dispose);
      final states = <CallState>[];
      final subscription = coordinator.snapshots.listen(
        (snapshot) => states.add(snapshot.state),
      );
      addTearDown(subscription.cancel);

      await coordinator.dispatch(_event(CallEventType.place));
      await coordinator.dispatch(_event(CallEventType.outgoingInviteReady));
      await coordinator.dispatch(_event(CallEventType.remoteRinging));
      await coordinator.dispatch(_event(CallEventType.remoteAccept));

      expect(states, <CallState>[
        CallState.preparing,
        CallState.inviting,
        CallState.ringing,
        CallState.accepted,
      ]);
      expect(executor.effects.first, CallEffectType.prepareOutgoingInvite);
      expect(coordinator.activeSession?.state, CallState.accepted);
    },
  );

  test(
    'terminal dispatch clears active reference after cleanup failure',
    () async {
      final history = _MemoryHistoryRepository();
      final cleanup = CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('failing', (_) async => throw StateError('failed')),
      ]);
      final coordinator = _coordinator(history: history, cleanup: cleanup);
      addTearDown(coordinator.dispose);

      await coordinator.dispatch(_event(CallEventType.place));
      await coordinator.dispatch(_event(CallEventType.cancel));

      expect(coordinator.activeSession, isNull);
      expect(coordinator.lastSnapshot?.state, CallState.ended);
      expect(history.rows, hasLength(1));
    },
  );

  test(
    'duplicate terminal paths yield one cleanup and one history row',
    () async {
      final history = _MemoryHistoryRepository();
      var cleanups = 0;
      final coordinator = _coordinator(
        history: history,
        cleanup: CallCleanupCoordinator(<CallCleanupStep>[
          CallCleanupStep('count', (_) async => cleanups++),
        ]),
      );
      addTearDown(coordinator.dispose);

      await coordinator.dispatch(_event(CallEventType.place));
      await coordinator.dispatch(_event(CallEventType.cancel));
      await coordinator.dispatch(
        _event(CallEventType.remoteTerminate, eventId: 'late-terminate'),
      );

      expect(cleanups, 1);
      expect(history.rows, hasLength(1));
    },
  );

  test(
    'exact terminal cleanup retry gates ACK without replaying state or history',
    () async {
      final history = _MemoryHistoryRepository();
      var cleanupRuns = 0;
      final cleanup = CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('call_media', (_) async {
          cleanupRuns++;
          if (cleanupRuns == 1) throw StateError('private failure');
        }, requiredForTerminalAck: true),
      ]);
      final coordinator = _coordinator(history: history, cleanup: cleanup);
      addTearDown(coordinator.dispose);

      await coordinator.dispatch(_event(CallEventType.place));
      await coordinator.dispatch(_event(CallEventType.cancel));

      expect(coordinator.activeSession, isNull);
      expect(coordinator.terminalCleanupAckReady(_callId), isFalse);
      expect(await coordinator.retryTerminalCleanup(_callId), isTrue);
      expect(coordinator.terminalCleanupAckReady(_callId), isTrue);
      expect(await coordinator.retryTerminalCleanup(_callId), isTrue);
      expect(cleanupRuns, 2);
      expect(history.rows, hasLength(1));
    },
  );

  test('pending event queue fails closed at its configured bound', () async {
    final gate = Completer<void>();
    final history = _MemoryHistoryRepository();
    final coordinator = _coordinator(
      history: history,
      executor: _RecordingExecutor(gate: gate),
      maxPendingEvents: 1,
    );
    addTearDown(coordinator.dispose);

    final first = coordinator.dispatch(_event(CallEventType.place));
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      coordinator.dispatch(_event(CallEventType.cancel, eventId: 'cancel')),
      throwsA(isA<CallEventQueueFullException>()),
    );
    gate.complete();
    await first;
  });

  test('injected 30 second no-answer timer terminates the call', () async {
    final timers = _FakeTimerScheduler();
    final history = _MemoryHistoryRepository();
    final coordinator = _coordinator(history: history, timerScheduler: timers);
    addTearDown(coordinator.dispose);

    await coordinator.dispatch(_event(CallEventType.place));
    await coordinator.dispatch(_event(CallEventType.outgoingInviteReady));
    expect(
      timers.scheduled.map((timer) => timer.delay),
      contains(const Duration(seconds: 30)),
    );

    await timers.fire(const Duration(seconds: 30));

    expect(coordinator.activeSession, isNull);
    expect(coordinator.lastSnapshot?.endReason?.name, 'noAnswer');
    expect(history.rows, hasLength(1));
  });

  test(
    '45 second invite expiry is canceled and stale callback cannot reopen',
    () async {
      final timers = _FakeTimerScheduler();
      final history = _MemoryHistoryRepository();
      final coordinator = _coordinator(
        history: history,
        timerScheduler: timers,
      );
      addTearDown(coordinator.dispose);

      await coordinator.dispatch(_event(CallEventType.place));
      await coordinator.dispatch(_event(CallEventType.outgoingInviteReady));
      final expiry = timers.scheduled.firstWhere(
        (timer) => timer.delay == const Duration(seconds: 45),
      );
      await coordinator.dispatch(_event(CallEventType.cancel));
      expect(expiry.canceled, isTrue);

      await expiry.callback();

      expect(coordinator.activeSession, isNull);
      expect(history.rows, hasLength(1));
    },
  );

  test(
    'incoming expiry timer uses authenticated lifetime remaining at receipt',
    () async {
      final timers = _FakeTimerScheduler();
      final history = _MemoryHistoryRepository();
      final receivedAt = _now.add(const Duration(seconds: 30));
      final coordinator = _coordinator(
        history: history,
        timerScheduler: timers,
        clock: () => receivedAt,
      );
      addTearDown(coordinator.dispose);

      await coordinator.dispatch(
        _event(
          CallEventType.remoteInvite,
          occurredAt: _now,
          expiresAt: _now.add(const Duration(seconds: 45)),
          admission: IncomingCallAdmission.accepted,
        ),
      );

      expect(timers.scheduled.single.delay, const Duration(seconds: 15));
    },
  );

  test(
    'timer terminalization survives a saturated public dispatch queue',
    () async {
      final gate = Completer<void>();
      final timers = _FakeTimerScheduler();
      final history = _MemoryHistoryRepository();
      final coordinator = _coordinator(
        history: history,
        executor: _RecordingExecutor(
          gate: gate,
          blockedEffect: CallEffectType.presentIncomingCall,
        ),
        maxPendingEvents: 1,
        timerScheduler: timers,
      );
      addTearDown(coordinator.dispose);

      await coordinator.dispatch(
        _event(
          CallEventType.remoteInvite,
          expiresAt: _now.add(const Duration(seconds: 45)),
          admission: IncomingCallAdmission.accepted,
        ),
      );
      final validation = coordinator.dispatch(
        _event(CallEventType.incomingValidated),
      );
      await Future<void>.delayed(Duration.zero);

      final timerExpectation = expectLater(
        timers.fire(const Duration(seconds: 45)),
        completes,
      );
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await validation;
      await timerExpectation;

      expect(coordinator.activeSession, isNull);
      expect(coordinator.lastSnapshot?.endReason?.name, 'expired');
      expect(history.rows, hasLength(1));
    },
  );

  test('timer dispatch reports terminal persistence failure safely', () async {
    final timers = _FakeTimerScheduler();
    final failures = <CallCoordinatorInternalFailure>[];
    final coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
      historyProjector: CallHistoryProjector(_ThrowingHistoryRepository()),
      effectExecutor: _RecordingExecutor(),
      clock: () => _now,
      idSource: () => _callId,
      timerScheduler: timers,
      onInternalFailure: failures.add,
    );
    addTearDown(coordinator.dispose);

    await coordinator.dispatch(_event(CallEventType.place));
    await coordinator.dispatch(_event(CallEventType.outgoingInviteReady));
    await expectLater(timers.fire(const Duration(seconds: 30)), completes);

    expect(coordinator.activeSession, isNull);
    expect(coordinator.lastSnapshot?.state, CallState.ended);
    expect(coordinator.internalFailureCount, 1);
    expect(failures, <CallCoordinatorInternalFailure>[
      CallCoordinatorInternalFailure.timerDispatchFailed,
    ]);
  });

  test(
    'synchronous accept follow-up cannot leave preconnect timers armed',
    () async {
      final timers = _FakeTimerScheduler();
      final history = _MemoryHistoryRepository();
      final coordinator = _coordinator(
        history: history,
        executor: _ImmediateAcceptExecutor(),
        timerScheduler: timers,
      );
      addTearDown(coordinator.dispose);

      await coordinator.dispatch(_event(CallEventType.place));

      expect(coordinator.activeSession?.state, CallState.accepted);
      expect(
        timers.scheduled.where((timer) => !timer.canceled).single.delay,
        const Duration(seconds: 30),
      );
    },
  );

  test(
    'reconnect timeout is scheduled and terminalizes through one lane',
    () async {
      final timers = _FakeTimerScheduler();
      final history = _MemoryHistoryRepository();
      final coordinator = _coordinator(
        history: history,
        timerScheduler: timers,
      );
      addTearDown(coordinator.dispose);

      await coordinator.dispatch(_event(CallEventType.place));
      await coordinator.dispatch(_event(CallEventType.outgoingInviteReady));
      await coordinator.dispatch(_event(CallEventType.remoteAccept));
      await coordinator.dispatch(_event(CallEventType.negotiationReady));
      await coordinator.dispatch(_event(CallEventType.mediaConnected));
      await coordinator.dispatch(_event(CallEventType.mediaLost));

      expect(coordinator.activeSession?.state, CallState.reconnecting);
      expect(
        timers.scheduled.where((timer) => !timer.canceled).single.delay,
        const Duration(seconds: 15),
      );

      await timers.fire(const Duration(seconds: 15));
      expect(coordinator.activeSession, isNull);
      expect(
        coordinator.lastSnapshot?.endReason,
        CallEndReason.reconnectFailed,
      );
      expect(history.rows, hasLength(1));
    },
  );

  test(
    'same-call replay after cleanup cannot recreate an active session',
    () async {
      final history = _MemoryHistoryRepository();
      final coordinator = _coordinator(history: history);
      addTearDown(coordinator.dispose);

      await coordinator.dispatch(_event(CallEventType.place));
      await coordinator.dispatch(_event(CallEventType.cancel));
      final replay = await coordinator.dispatch(
        _event(CallEventType.remoteInvite, eventId: 'replayed-invite'),
      );

      expect(replay.decision, CallEventDecision.ignored);
      expect(replay.reason, CallReductionReason.terminalDominates);
      expect(coordinator.activeSession, isNull);
      expect(history.rows, hasLength(1));
    },
  );

  test('dispose terminalizes a call that was already queued', () async {
    final history = _MemoryHistoryRepository();
    final coordinator = _coordinator(history: history);

    final queuedPlace = coordinator.dispatch(_event(CallEventType.place));
    final disposal = coordinator.dispose();
    await queuedPlace;
    await disposal;

    expect(coordinator.activeSession, isNull);
    expect(coordinator.lastSnapshot?.state, CallState.ended);
    expect(coordinator.lastSnapshot?.endReason?.name, 'appShutdown');
    expect(history.rows, hasLength(1));
  });

  test(
    'maximum-skew invite still projects monotonic connected history',
    () async {
      final history = _MemoryHistoryRepository();
      final timers = _FakeTimerScheduler();
      final coordinator = _coordinator(
        history: history,
        timerScheduler: timers,
      );
      addTearDown(coordinator.dispose);
      final inviteAt = _now.add(const Duration(seconds: 30));

      await coordinator.dispatch(
        _event(
          CallEventType.remoteInvite,
          occurredAt: inviteAt,
          expiresAt: inviteAt.add(const Duration(seconds: 45)),
        ),
      );
      await coordinator.dispatch(
        _event(CallEventType.incomingValidated, occurredAt: _now),
      );
      await coordinator.dispatch(
        _event(CallEventType.systemUiPresented, occurredAt: _now),
      );
      await coordinator.dispatch(
        _event(CallEventType.answer, occurredAt: _now),
      );
      await coordinator.dispatch(
        _event(CallEventType.negotiationReady, occurredAt: _now),
      );
      await coordinator.dispatch(
        _event(CallEventType.mediaConnected, occurredAt: _now),
      );
      await coordinator.dispatch(
        _event(CallEventType.appShutdown, occurredAt: _now),
      );

      final terminal = coordinator.lastSnapshot!;
      final row = history.rows[_callId]!;
      expect(terminal.startedAt, inviteAt);
      expect(terminal.acceptedAt, inviteAt);
      expect(terminal.connectedAt, inviteAt);
      expect(terminal.endedAt, inviteAt);
      expect(row.startedAt, inviteAt);
      expect(row.connectedAt, inviteAt);
      expect(row.endedAt, inviteAt);
      expect(row.duration, Duration.zero);
    },
  );

  test('terminal cleanup survives a hung signaling effect', () async {
    final history = _MemoryHistoryRepository();
    final never = Completer<void>();
    var cleanups = 0;
    final coordinator = _coordinator(
      history: history,
      executor: _RecordingExecutor(
        gate: never,
        blockedEffect: CallEffectType.sendTerminate,
      ),
      cleanup: CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('media', (_) async => cleanups++),
      ]),
      terminalEffectTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(coordinator.dispose);
    await coordinator.dispatch(_event(CallEventType.place));

    await expectLater(
      coordinator.dispatch(_event(CallEventType.cancel)),
      throwsA(isA<TimeoutException>()),
    );

    expect(cleanups, 1);
    expect(coordinator.activeSession, isNull);
    expect(history.rows, hasLength(1));
  });

  test(
    'nonterminal effect timeout canonicalizes failure and cleanup',
    () async {
      final history = _MemoryHistoryRepository();
      final never = Completer<void>();
      var cleanups = 0;
      final coordinator = _coordinator(
        history: history,
        executor: _RecordingExecutor(
          gate: never,
          blockedEffect: CallEffectType.startNegotiation,
        ),
        cleanup: CallCleanupCoordinator(<CallCleanupStep>[
          CallCleanupStep('media', (_) async => cleanups++),
        ]),
        effectTimeout: const Duration(milliseconds: 10),
        mediaPreparationTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(coordinator.dispose);
      await coordinator.dispatch(_event(CallEventType.place));
      await coordinator.dispatch(_event(CallEventType.outgoingInviteReady));

      await expectLater(
        coordinator.dispatch(_event(CallEventType.remoteAccept)),
        throwsA(isA<TimeoutException>()),
      );

      expect(cleanups, 1);
      expect(coordinator.activeSession, isNull);
      expect(coordinator.lastSnapshot?.endReason, CallEndReason.mediaFailed);
      expect(history.rows, hasLength(1));
    },
  );

  test(
    'terminal cleanup starts before best-effort signaling settles',
    () async {
      final history = _MemoryHistoryRepository();
      final sendGate = Completer<void>();
      var cleanups = 0;
      final coordinator = _coordinator(
        history: history,
        executor: _RecordingExecutor(
          gate: sendGate,
          blockedEffect: CallEffectType.sendTerminate,
        ),
        cleanup: CallCleanupCoordinator(<CallCleanupStep>[
          CallCleanupStep('media', (_) async => cleanups++),
        ]),
      );
      addTearDown(coordinator.dispose);
      await coordinator.dispatch(_event(CallEventType.place));

      final terminal = coordinator.dispatch(_event(CallEventType.cancel));
      await Future<void>.delayed(Duration.zero);
      expect(cleanups, 1);

      sendGate.complete();
      await terminal;
      expect(coordinator.activeSession, isNull);
    },
  );

  test('concurrent dispose callers await one terminal cleanup', () async {
    final history = _MemoryHistoryRepository();
    final cleanupGate = Completer<void>();
    var cleanups = 0;
    final coordinator = _coordinator(
      history: history,
      cleanup: CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('gate', (_) async {
          cleanups++;
          await cleanupGate.future;
        }),
      ]),
    );
    await coordinator.dispatch(_event(CallEventType.place));

    final first = coordinator.dispose();
    final second = coordinator.dispose();
    var secondCompleted = false;
    unawaited(second.then((_) => secondCompleted = true));
    await Future<void>.delayed(Duration.zero);

    expect(secondCompleted, isFalse);
    cleanupGate.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(cleanups, 1);
    expect(history.rows, hasLength(1));
  });

  test(
    'dispose finalizes timers and snapshot stream after shutdown failure',
    () async {
      final timers = _FakeTimerScheduler();
      final coordinator = CallCoordinator(
        reducer: const CallReducer(),
        cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
        historyProjector: CallHistoryProjector(_ThrowingHistoryRepository()),
        effectExecutor: _RecordingExecutor(),
        clock: () => _now,
        idSource: () => _callId,
        timerScheduler: timers,
      );
      var streamDone = false;
      final subscription = coordinator.snapshots.listen(
        (_) {},
        onDone: () => streamDone = true,
      );

      await coordinator.dispatch(_event(CallEventType.place));
      await coordinator.dispatch(_event(CallEventType.outgoingInviteReady));
      expect(timers.scheduled.where((timer) => !timer.canceled), isNotEmpty);
      await expectLater(coordinator.dispose(), throwsStateError);
      await Future<void>.delayed(Duration.zero);

      expect(streamDone, isTrue);
      expect(timers.scheduled.every((timer) => timer.canceled), isTrue);
      await expectLater(coordinator.dispose(), completes);
      await expectLater(
        coordinator.dispatch(
          _event(CallEventType.place, eventId: 'late-place'),
        ),
        throwsStateError,
      );
      await subscription.cancel();
    },
  );
}
