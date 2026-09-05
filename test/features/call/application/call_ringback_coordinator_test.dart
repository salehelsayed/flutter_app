import 'dart:async';

import 'package:flutter_app/features/call/application/call_ringback_coordinator.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ringback is the tone the caller hears while the far end rings. The
/// coordinator turns call snapshots into exactly one start and one stop per
/// ringing outgoing call, never overlaps the two, and keeps trying to stop.
final _callA = CallId.parse('11111111-1111-4111-8111-111111111111');
final _callB = CallId.parse('22222222-2222-4222-8222-222222222222');
final _now = DateTime.utc(2026, 9, 5, 12);

const _outgoingStates = <CallState>[
  CallState.preparing,
  CallState.inviting,
  CallState.ringing,
  CallState.accepted,
  CallState.negotiating,
  CallState.connected,
  CallState.reconnecting,
  CallState.ending,
  CallState.ended,
];

const _incomingStates = <CallState>[
  CallState.incomingValidating,
  CallState.ringing,
  CallState.accepted,
  CallState.negotiating,
  CallState.connected,
  CallState.reconnecting,
  CallState.ending,
  CallState.ended,
];

void main() {
  test('ringback is wanted only for an outgoing call that is ringing', () {
    expect(ringbackWanted(CallSessionSnapshot.idle(now: _now)), isFalse);
    for (final state in _outgoingStates) {
      expect(
        ringbackWanted(_session(state)),
        state == CallState.ringing,
        reason: 'outgoing $state',
      );
    }
    for (final state in _incomingStates) {
      expect(
        ringbackWanted(_session(state, direction: CallDirection.incoming)),
        isFalse,
        reason: 'incoming $state',
      );
    }
  });

  test(
    'an outgoing call rings back from the far-end ring until it is accepted',
    () async {
      final port = _RecordingPort();
      final results = <String>[];
      final coordinator = _coordinator(port, results);

      for (final state in const <CallState>[
        CallState.preparing,
        CallState.inviting,
        CallState.ringing,
        CallState.ringing,
        CallState.accepted,
        CallState.negotiating,
        CallState.connected,
        CallState.ended,
      ]) {
        coordinator.onSession(_session(state));
      }
      await coordinator.settled;

      expect(port.calls, ['start:${_callA.value}', 'stop:${_callA.value}']);
      expect(results, ['start:ok', 'stop:ok']);
      expect(coordinator.isArmed, isFalse);

      await coordinator.dispose();
      expect(port.calls, hasLength(2), reason: 'nothing left to stop');
    },
  );

  test('a cancelled or timed-out ring stops the tone exactly once', () async {
    final port = _RecordingPort();
    final results = <String>[];
    final coordinator = _coordinator(port, results);

    coordinator.onSession(_session(CallState.inviting));
    coordinator.onSession(_session(CallState.ringing));
    coordinator.onSession(_session(CallState.ended));
    await coordinator.settled;
    await coordinator.dispose();

    expect(port.calls, ['start:${_callA.value}', 'stop:${_callA.value}']);
    expect(results, ['start:ok', 'stop:ok']);
  });

  test('disposing while the far end rings stops the tone', () async {
    final port = _RecordingPort();
    final results = <String>[];
    final coordinator = _coordinator(port, results);

    coordinator.onSession(_session(CallState.ringing));
    await coordinator.settled;
    expect(port.calls, ['start:${_callA.value}']);

    await coordinator.dispose();
    expect(port.calls, ['start:${_callA.value}', 'stop:${_callA.value}']);
    expect(coordinator.isArmed, isFalse);

    coordinator.onSession(_session(CallState.ringing));
    await coordinator.settled;
    expect(port.calls, hasLength(2), reason: 'a disposed coordinator is inert');
  });

  test('an incoming call never plays ringback', () async {
    final port = _RecordingPort();
    final results = <String>[];
    final coordinator = _coordinator(port, results);

    for (final state in _incomingStates) {
      coordinator.onSession(_session(state, direction: CallDirection.incoming));
    }
    await coordinator.settled;
    await coordinator.dispose();

    expect(port.calls, isEmpty);
    expect(results, isEmpty);
  });

  test(
    'a refused or failing start is reported once and not retried per snapshot',
    () async {
      final refused = _RecordingPort()..startResult = false;
      final refusedResults = <String>[];
      final refusedCoordinator = _coordinator(refused, refusedResults);
      refusedCoordinator.onSession(_session(CallState.ringing));
      refusedCoordinator.onSession(_session(CallState.ringing));
      await refusedCoordinator.settled;
      expect(refused.calls, ['start:${_callA.value}']);
      expect(refusedResults, ['start:refused']);
      refusedCoordinator.onSession(_session(CallState.ended));
      await refusedCoordinator.settled;
      expect(refused.calls, ['start:${_callA.value}', 'stop:${_callA.value}']);
      expect(refusedResults, ['start:refused', 'stop:ok']);

      final failing = _RecordingPort()..startError = StateError('no tone');
      final failingResults = <String>[];
      final failingCoordinator = _coordinator(failing, failingResults);
      failingCoordinator.onSession(_session(CallState.ringing));
      failingCoordinator.onSession(_session(CallState.ringing));
      failingCoordinator.onSession(_session(CallState.accepted));
      await failingCoordinator.settled;
      expect(failing.calls, ['start:${_callA.value}', 'stop:${_callA.value}']);
      expect(failingResults, ['start:failed', 'stop:ok']);
    },
  );

  test(
    'a failing stop is retried on the next snapshot and on dispose',
    () async {
      final port = _RecordingPort();
      final results = <String>[];
      final coordinator = _coordinator(port, results);

      coordinator.onSession(_session(CallState.ringing));
      await coordinator.settled;
      port.stopError = StateError('tone stuck');
      coordinator.onSession(_session(CallState.accepted));
      await coordinator.settled;
      expect(results, ['start:ok', 'stop:failed']);
      expect(coordinator.isArmed, isTrue, reason: 'a failed stop stays armed');

      coordinator.onSession(_session(CallState.connected));
      await coordinator.settled;
      expect(results, ['start:ok', 'stop:failed', 'stop:failed']);

      port.stopError = null;
      await coordinator.dispose();
      expect(results, ['start:ok', 'stop:failed', 'stop:failed', 'stop:ok']);
      expect(
        port.calls.where((call) => call.startsWith('start:')),
        hasLength(1),
      );
      expect(coordinator.isArmed, isFalse);
    },
  );

  test('stop never overlaps a start still in flight', () async {
    final port = _RecordingPort()..startGate = Completer<void>();
    final results = <String>[];
    final coordinator = _coordinator(port, results);

    coordinator.onSession(_session(CallState.ringing));
    coordinator.onSession(_session(CallState.accepted));
    await pumpEventQueue();
    expect(port.calls, ['start:${_callA.value}']);
    expect(results, isEmpty);

    port.startGate!.complete();
    await coordinator.settled;
    expect(port.calls, ['start:${_callA.value}', 'stop:${_callA.value}']);
    expect(results, ['start:ok', 'stop:ok']);
  });

  test('a later call rings back again after the first one ended', () async {
    final port = _RecordingPort();
    final results = <String>[];
    final coordinator = _coordinator(port, results);

    coordinator.onSession(_session(CallState.ringing));
    coordinator.onSession(_session(CallState.ended));
    coordinator.onSession(_session(CallState.ringing, callId: _callB));
    coordinator.onSession(_session(CallState.ended, callId: _callB));
    await coordinator.settled;

    expect(port.calls, [
      'start:${_callA.value}',
      'stop:${_callA.value}',
      'start:${_callB.value}',
      'stop:${_callB.value}',
    ]);
  });
}

CallRingbackCoordinator _coordinator(
  _RecordingPort port,
  List<String> results,
) => CallRingbackCoordinator(
  port: port,
  onResult: (action, outcome) => results.add('${action.name}:$outcome'),
);

CallSessionSnapshot _session(
  CallState state, {
  CallDirection direction = CallDirection.outgoing,
  CallId? callId,
}) {
  final outgoing = direction == CallDirection.outgoing;
  return CallSessionSnapshot.active(
    callId: callId ?? _callA,
    contactPeerId: 'remote-account',
    direction: direction,
    state: state,
    callerAccountPeerId: outgoing ? 'local-account' : 'remote-account',
    callerDeviceId: outgoing ? 'local-device' : 'remote-device',
    startedAt: _now,
    ringingAt: state.index >= CallState.ringing.index ? _now : null,
    acceptedAt: state.index >= CallState.accepted.index ? _now : null,
    connectedAt: state == CallState.connected || state == CallState.reconnecting
        ? _now
        : null,
    endedAt: state == CallState.ended ? _now : null,
    endReason: state == CallState.ended ? CallEndReason.localHangup : null,
  );
}

final class _RecordingPort implements CallRingbackPort {
  final List<String> calls = <String>[];
  bool startResult = true;
  bool stopResult = true;
  Object? startError;
  Object? stopError;
  Completer<void>? startGate;

  @override
  Future<bool> start(CallId callId) async {
    calls.add('start:${callId.value}');
    final gate = startGate;
    if (gate != null) await gate.future;
    final error = startError;
    if (error != null) throw error;
    return startResult;
  }

  @override
  Future<bool> stop(CallId callId) async {
    calls.add('stop:${callId.value}');
    final error = stopError;
    if (error != null) throw error;
    return stopResult;
  }
}
