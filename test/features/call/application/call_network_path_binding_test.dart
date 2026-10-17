import 'dart:async';

import 'package:flutter_app/core/services/network_path_source.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_network_path_binding.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _callId = CallId.parse('55555555-5555-4555-8555-555555555555');
final _now = DateTime.utc(2026, 10, 16, 12);

CallEvent _event(CallEventType type) => CallEvent(
  type: type,
  eventId: type.name,
  occurredAt: _now,
  callId: _callId,
  contactPeerId: 'contact-a',
  localAccountPeerId: 'local-account',
  localDeviceId: 'local-device',
  remoteAccountPeerId: 'contact-a',
  remoteDeviceId: 'contact-device',
);

Map<String, dynamic> _push(String event, int epoch) => <String, dynamic>{
  'event': event,
  'epoch': epoch,
  'ownerGeneration': 2,
};

Future<void> _settle([int turns = 12]) async {
  for (var index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _History implements CallHistoryRepository {
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      const <CallHistoryEntry>[];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {}
}

final class _RecordingExecutor implements CallEffectExecutor {
  final List<CallEffectType> effects = <CallEffectType>[];

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    effects.add(effect.type);
    return null;
  }

  int count(CallEffectType type) => effects.where((e) => e == type).length;
}

final class _Scheduled {
  _Scheduled(this.delay, this.callback);
  final Duration delay;
  final Future<void> Function() callback;
  bool canceled = false;
  bool fired = false;

  Future<void> fire() {
    fired = true;
    return callback();
  }
}

final class _TimerHandle implements CallTimerHandle {
  _TimerHandle(this.scheduled);
  final _Scheduled scheduled;

  @override
  bool get isActive => !scheduled.canceled;

  @override
  void cancel() => scheduled.canceled = true;
}

final class _TimerScheduler implements CallTimerScheduler {
  final List<_Scheduled> scheduled = <_Scheduled>[];

  @override
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback) {
    final value = _Scheduled(delay, callback);
    scheduled.add(value);
    return _TimerHandle(value);
  }

  List<_Scheduled> live(Duration delay) => scheduled
      .where((timer) => timer.delay == delay && !timer.canceled && !timer.fired)
      .toList(growable: false);
}

final class _Harness {
  _Harness() {
    coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
      historyProjector: CallHistoryProjector(_History()),
      effectExecutor: executor,
      clock: () => _now,
      idSource: () => _callId,
      timerScheduler: timers,
    );
    source = NetworkPathSource(events: pushes.stream);
    binding = CallNetworkPathBinding(
      outcomes: source.outcomes,
      coordinator: coordinator,
      clock: () => _now,
    );
  }

  final pushes = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final executor = _RecordingExecutor();
  final timers = _TimerScheduler();
  late final CallCoordinator coordinator;
  late final NetworkPathSource source;
  late final CallNetworkPathBinding binding;

  CallSessionSnapshot? get active => coordinator.activeSession;

  Future<void> connectOutgoing() async {
    for (final type in <CallEventType>[
      CallEventType.place,
      CallEventType.outgoingInviteReady,
      CallEventType.remoteAccept,
      CallEventType.negotiationReady,
      CallEventType.mediaConnected,
    ]) {
      await coordinator.dispatch(_event(type));
    }
    expect(active?.state, CallState.connected);
  }

  Future<void> push(String event, int epoch) async {
    pushes.add(_push(event, epoch));
    await _settle();
  }

  Future<void> dispose() async {
    await binding.dispose();
    await source.dispose();
    await pushes.close();
    await coordinator.dispose();
  }
}

void main() {
  late _Harness h;
  const reconnectWindow = Duration(seconds: 15);

  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  test('no active call means no ICE action', () async {
    await h.push(NetworkPathEvents.changing, 7);
    await h.push(NetworkPathEvents.relayReady, 7);

    expect(h.active, isNull);
    expect(h.executor.effects, isEmpty);
    expect(h.timers.scheduled, isEmpty);
  });

  test('a connected caller restarts once, after readiness of the latest '
      'epoch', () async {
    await h.connectOutgoing();
    final effectsBefore = h.executor.effects.length;

    await h.push(NetworkPathEvents.changing, 7);
    expect(h.active?.state, CallState.connected);
    expect(h.active?.pendingPathEpoch, 7);
    await h.push(NetworkPathEvents.changing, 8);
    await h.push(NetworkPathEvents.relayReady, 7);
    expect(h.active?.state, CallState.connected);
    expect(h.executor.effects.length, effectsBefore);
    expect(h.timers.live(reconnectWindow), isEmpty);

    await h.push(NetworkPathEvents.relayReady, 8);
    expect(h.active?.state, CallState.reconnecting);
    expect(h.active?.reconnectGeneration, 1);
    expect(h.active?.pendingPathEpoch, isNull);
    expect(h.executor.effects.sublist(effectsBefore), <CallEffectType>[
      CallEffectType.restartIce,
    ]);
    expect(h.timers.live(reconnectWindow), hasLength(1));
  });

  test(
    'losing the previous network after recovery restarts once more',
    () async {
      await h.connectOutgoing();
      await h.push(NetworkPathEvents.changing, 7);
      await h.push(NetworkPathEvents.relayReady, 7);
      await h.coordinator.dispatch(_event(CallEventType.mediaRecovered));
      await _settle();
      expect(h.active?.state, CallState.connected);
      final effectsBefore = h.executor.effects.length;

      await h.push(NetworkPathEvents.previousLost, 7);
      await h.push(NetworkPathEvents.previousLost, 7);

      expect(h.active?.state, CallState.reconnecting);
      expect(h.active?.reconnectGeneration, 2);
      expect(h.executor.effects.sublist(effectsBefore), <CallEffectType>[
        CallEffectType.restartIce,
      ]);
      expect(h.timers.live(reconnectWindow), hasLength(1));
    },
  );

  test('a previous-network loss with no active call does nothing', () async {
    await h.push(NetworkPathEvents.changing, 7);
    await h.push(NetworkPathEvents.relayReady, 7);
    await h.push(NetworkPathEvents.previousLost, 7);

    expect(h.active, isNull);
    expect(h.executor.effects, isEmpty);
  });

  test('a replayed attempt after a failed one restarts once', () async {
    await h.connectOutgoing();
    final effectsBefore = h.executor.effects.length;

    await h.push(NetworkPathEvents.changing, 7);
    await h.push(NetworkPathEvents.relayFailed, 7);
    await h.push(NetworkPathEvents.changing, 7);
    await h.push(NetworkPathEvents.relayReady, 7);

    expect(h.active?.state, CallState.reconnecting);
    expect(h.executor.effects.sublist(effectsBefore), <CallEffectType>[
      CallEffectType.restartIce,
    ]);
    expect(h.timers.live(reconnectWindow), hasLength(1));
  });

  test('relay failure launches no restart', () async {
    await h.connectOutgoing();
    final effectsBefore = h.executor.effects.length;

    await h.push(NetworkPathEvents.changing, 7);
    await h.push(NetworkPathEvents.relayFailed, 7);
    await h.push(NetworkPathEvents.relayReady, 7);

    expect(h.active?.state, CallState.connected);
    expect(h.active?.pendingPathEpoch, isNull);
    expect(h.executor.effects.length, effectsBefore);
    expect(h.timers.live(reconnectWindow), isEmpty);
  });

  test('a hang-up during the wait ends the call at once and a late readiness '
      'changes nothing', () async {
    await h.connectOutgoing();
    await h.push(NetworkPathEvents.changing, 7);

    await h.coordinator.dispatch(_event(CallEventType.end));
    expect(h.active, isNull);
    expect(h.coordinator.lastSnapshot?.state, CallState.ended);
    expect(h.coordinator.lastSnapshot?.endReason, CallEndReason.localHangup);
    final effectsAfterEnd = List<CallEffectType>.of(h.executor.effects);

    await h.push(NetworkPathEvents.relayReady, 7);
    expect(h.coordinator.lastSnapshot?.state, CallState.ended);
    expect(h.executor.effects, effectsAfterEnd);
    expect(h.executor.count(CallEffectType.restartIce), 0);
  });

  test('media loss during the wait keeps one episode and one deadline across '
      'flaps, then resumes sealed signals', () async {
    await h.connectOutgoing();
    await h.push(NetworkPathEvents.changing, 7);
    await h.coordinator.dispatch(_event(CallEventType.mediaLost));
    expect(h.active?.state, CallState.reconnecting);
    expect(h.active?.reconnectGeneration, 1);
    expect(h.active?.pendingPathEpoch, 7);
    final deadline = h.timers.live(reconnectWindow).single;

    await h.push(NetworkPathEvents.changing, 8);
    await h.push(NetworkPathEvents.changing, 9);
    await h.push(NetworkPathEvents.relayReady, 8);
    expect(h.executor.count(CallEffectType.resumeRecoverySignals), 0);
    await h.push(NetworkPathEvents.relayReady, 9);

    expect(h.active?.state, CallState.reconnecting);
    expect(h.active?.reconnectGeneration, 1);
    expect(h.active?.pendingPathEpoch, isNull);
    expect(h.executor.count(CallEffectType.restartIce), 1);
    expect(h.executor.count(CallEffectType.resumeRecoverySignals), 1);
    expect(h.timers.live(reconnectWindow), <_Scheduled>[deadline]);
  });

  test('readiness after the original expiry cannot revive the call', () async {
    await h.connectOutgoing();
    await h.push(NetworkPathEvents.changing, 7);
    await h.coordinator.dispatch(_event(CallEventType.mediaLost));
    final deadline = h.timers.live(reconnectWindow).single;

    await deadline.fire();
    await _settle();
    expect(h.active, isNull);
    expect(h.coordinator.lastSnapshot?.state, CallState.ended);
    expect(
      h.coordinator.lastSnapshot?.endReason,
      CallEndReason.reconnectFailed,
    );
    final effectsAfterExpiry = List<CallEffectType>.of(h.executor.effects);

    await h.push(NetworkPathEvents.relayReady, 7);
    expect(h.coordinator.lastSnapshot?.state, CallState.ended);
    expect(h.executor.effects, effectsAfterExpiry);
    expect(h.timers.live(reconnectWindow), isEmpty);
  });

  test('a disposed binding delivers nothing', () async {
    await h.connectOutgoing();
    await h.binding.dispose();

    await h.push(NetworkPathEvents.changing, 7);
    await h.push(NetworkPathEvents.relayReady, 7);

    expect(h.active?.state, CallState.connected);
    expect(h.active?.pendingPathEpoch, isNull);
    expect(h.executor.count(CallEffectType.restartIce), 0);
  });
}
