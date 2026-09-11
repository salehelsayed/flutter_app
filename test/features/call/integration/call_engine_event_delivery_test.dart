import 'dart:async';

import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_negotiation_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_negotiation_material_store.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/webrtc_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

const _connected =
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected;
const _disconnected =
    webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected;
const _failed = webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed;
const _configuration = CallConnectionConfiguration(
  transportPolicy: CallTransportPolicy.all,
  receiveAudio: true,
  receiveVideo: false,
  captureAudio: false,
  captureVideo: false,
);
final _now = DateTime.utc(2026, 9, 11);
final _callId = CallId.parse('11111111-1111-4111-8111-111111111111');
final _nextId = CallId.parse('22222222-2222-4222-8222-222222222222');

void main() {
  for (final count in [65, 256, 1000]) {
    test(
      '$count processed native and engine events have no lifetime quota',
      () => _guarded(() async {
        final h = _Harness();
        try {
          await h.start();
          final nativeBefore = h.nativeEvents.length;
          final engineBefore = h.engineEvents.length;
          for (var i = 0; i < count; i++) {
            h.peer.emit(_connected);
            await h.drain();
          }
          expect(h.nativeEvents.length - nativeBefore, count);
          expect(h.engineEvents.length - engineBefore, count);
          expect(
            h.nativeEvents.any(
              (e) => e.kind == WebRtcPeerConnectionEventKind.overflow,
            ),
            isFalse,
          );
          expect(
            h.engineEvents.any((e) => e.type == CallEngineEventType.overflow),
            isFalse,
          );
          expect(h.adapter.recentEvents, hasLength(64));
          expect(h.engine.recentEvents, hasLength(64));
          expect(h.adapter.recentEvents.last, same(h.nativeEvents.last));
          expect(h.engine.recentEvents.last, same(h.engineEvents.last));
          expect(h.coordinator.activeSession?.state, CallState.connected);
          expect(h.dispatches, isEmpty);
          expect(h.peer.restartCalls, 0);
          expect(h.cleanupCalls, 0);
          await h.hangup();
          h.expectReleased();
        } finally {
          await h.close();
        }
      }),
    );
  }

  for (final fatal in [false, true]) {
    test(
      '${fatal ? 'failure' : 'disconnect'} after 1000 events reaches the coordinator',
      () => _guarded(() async {
        final h = _Harness();
        try {
          await h.start();
          for (var i = 0; i < 1000; i++) {
            h.peer.emit(_connected);
            await h.drain();
          }
          h.peer.emit(fatal ? _failed : _disconnected);
          await h.drain();
          expect(h.dispatches.map((e) => e.type), [
            fatal ? CallEventType.negotiationFailed : CallEventType.mediaLost,
          ]);
          if (fatal) {
            expect(
              h.coordinator.lastSnapshot?.endReason,
              CallEndReason.mediaFailed,
            );
            h.expectReleased();
          } else {
            expect(h.coordinator.activeSession?.state, CallState.reconnecting);
            expect(h.cleanupCalls, 0);
            await h.hangup();
            h.expectReleased();
          }
        } finally {
          await h.close();
        }
      }),
    );
  }

  test(
    'slow readiness consumer coalesces 1000 updates into bounded work',
    () => _guarded(() async {
      final h = _Harness();
      final gate = Completer<List<webrtc.RTCRtpSender>>();
      try {
        await h.start(connected: false);
        h.peer.sendersGate = gate;
        h.peer.emit(_connected);
        await _until(() => h.peer.senderReads == 1);
        for (var i = 0; i < 1000; i++) {
          h.peer.emit(_connected);
        }
        expect(h.peer.senderReads, 1);
        expect(h.dispatches, isEmpty);
        expect(h.adapter.recentEvents, hasLength(64));
        expect(h.engine.recentEvents, hasLength(64));
        expect(
          h.executor.toDiagnosticMap()['engineEventDrainInFlight'],
          isTrue,
        );
        expect(h.executor.toDiagnosticMap()['pendingEngineEventCount'], 1);
        gate.complete([]);
        await h.drain();
        expect(
          h.peer.senderReads,
          1,
          reason: 'duplicates reuse the active readiness watch',
        );
        expect(h.polls.active, hasLength(1));
        expect(h.coordinator.activeSession?.state, CallState.negotiating);
        expect(h.cleanupCalls, 0);
        await h.hangup();
        h.expectReleased();
      } finally {
        if (!gate.isCompleted) gate.complete([]);
        await h.close();
      }
    }),
  );

  test(
    'failure behind ordinary updates survives later ordinary updates',
    () => _guarded(() async {
      final h = _Harness();
      final gate = Completer<List<webrtc.RTCRtpSender>>();
      try {
        await h.start(connected: false);
        h.peer.sendersGate = gate;
        h.peer.emit(_connected);
        await _until(() => h.peer.senderReads == 1);
        for (var i = 0; i < 256; i++) {
          h.peer.emit(_connected);
        }
        h.peer.emit(_failed);
        for (var i = 0; i < 256; i++) {
          h.peer.emit(_connected);
        }
        expect(h.executor.toDiagnosticMap()['pendingEngineEventCount'], 1);
        expect(
          h.engineEvents.any((e) => e.type == CallEngineEventType.overflow),
          isFalse,
        );
        gate.complete([]);
        await h.drain();
        expect(h.dispatches.map((e) => e.type), [
          CallEventType.negotiationFailed,
        ]);
        expect(h.coordinator.lastSnapshot?.callId, _callId);
        expect(
          h.coordinator.lastSnapshot?.endReason,
          CallEndReason.mediaFailed,
        );
        h.expectReleased();
      } finally {
        if (!gate.isCompleted) gate.complete([]);
        await h.close();
      }
    }),
  );

  test(
    'queued disconnect survives ordinary updates without losing recovery state',
    () => _guarded(() async {
      final h = _Harness();
      try {
        await h.start();
        // The first synchronous callback claims the drain until its future
        // completes. All following callbacks arrive during that same drain.
        h.peer.emit(_connected);
        h.peer.emit(_disconnected);
        for (var i = 0; i < 256; i++) {
          h.peer.emit(_connected);
        }
        expect(h.executor.toDiagnosticMap()['pendingEngineEventCount'], 2);
        await h.drain();
        expect(h.dispatches.map((e) => e.type), [CallEventType.mediaLost]);
        expect(h.coordinator.activeSession?.state, CallState.reconnecting);
        expect(
          h.peer.senderReads,
          1,
          reason: 'latest connected still starts recovery observation',
        );
        expect(h.polls.active, hasLength(1));
        await h.hangup();
        h.expectReleased();
      } finally {
        await h.close();
      }
    }),
  );

  test(
    'close during synchronous delivery fences captured native callbacks',
    () => _guarded(() async {
      final h = _Harness();
      final next = _Harness(callId: _nextId);
      try {
        await h.start();
        final lateCallback = h.peer.onConnectionState!;
        Future<void>? hangup;
        final subscription = h.engine.events.listen((_) {
          hangup ??= h.hangup();
        });
        h.peer.emit(_connected);
        await hangup;
        await subscription.cancel();
        h.expectReleased();
        await next.start();
        final retiredCount = h.engineEvents.length;
        for (var i = 0; i < 1000; i++) {
          lateCallback(_failed);
        }
        await next.drain();
        expect(h.engineEvents, hasLength(retiredCount));
        expect(next.coordinator.activeSession?.callId, _nextId);
        expect(next.coordinator.activeSession?.state, CallState.connected);
        expect(next.dispatches, isEmpty);
        expect(next.cleanupCalls, 0);
        await next.hangup();
        next.expectReleased();
      } finally {
        await h.close();
        await next.close();
      }
    }),
  );

  for (final fatal in [false, true]) {
    test(
      'reentrant callbacks coalesce and preserve ${fatal ? 'failure' : 'disconnect'}',
      () => _guarded(() async {
        final h = _Harness();
        StreamSubscription<WebRtcPeerConnectionEvent>? subscription;
        try {
          await h.start();
          var entered = false;
          final before = h.nativeEvents.length;
          subscription = h.adapter.events.listen((_) {
            if (entered) return;
            entered = true;
            for (var i = 0; i < 1000; i++) {
              h.peer.emit(_connected);
            }
            h.peer.emit(fatal ? _failed : _disconnected);
            for (var i = 0; i < 1000; i++) {
              h.peer.emit(_connected);
            }
          });
          h.peer.emit(_connected);
          await h.drain();
          expect(
            h.nativeEvents.skip(before).map((e) => e.connectionState),
            [
              WebRtcConnectionState.connected,
              if (fatal) ...[
                WebRtcConnectionState.failed,
                WebRtcConnectionState.closed,
              ] else ...[
                WebRtcConnectionState.disconnected,
                WebRtcConnectionState.connected,
              ],
            ],
            reason:
                'bounded coalescing preserves the edge and terminal delivery',
          );
          expect(h.dispatches.map((e) => e.type), [
            fatal ? CallEventType.negotiationFailed : CallEventType.mediaLost,
          ]);
          expect(h.adapter.recentEvents.length, lessThanOrEqualTo(64));
          expect(h.engine.recentEvents.length, lessThanOrEqualTo(64));
          await subscription.cancel();
          if (!fatal) await h.hangup();
          h.expectReleased();
        } finally {
          await subscription?.cancel();
          await h.close();
        }
      }),
    );
  }

  test(
    'failure during disconnect dispatch precedes queued recovery observation',
    () => _guarded(() async {
      final h = _Harness();
      final gate = Completer<void>();
      try {
        await h.start();
        h.dispatchGate = gate;
        h.blockedDispatchType = CallEventType.mediaLost;
        h.peer.emit(_connected);
        h.peer.emit(_disconnected);
        h.peer.emit(_connected);
        await _until(() => h.dispatches.isNotEmpty);
        h.peer.emit(_failed);
        for (var i = 0; i < 1000; i++) {
          h.peer.emit(_connected);
        }
        expect(h.executor.toDiagnosticMap()['pendingEngineEventCount'], 1);
        gate.complete();
        await h.drain();
        expect(h.dispatches.map((e) => e.type), [
          CallEventType.mediaLost,
          CallEventType.negotiationFailed,
        ]);
        expect(
          h.peer.senderReads,
          0,
          reason: 'pending failure supersedes recovery work',
        );
        h.expectReleased();
      } finally {
        if (!gate.isCompleted) gate.complete();
        await h.close();
      }
    }),
  );

  test(
    'native close during reentrant delivery clears pending state',
    () => _guarded(() async {
      final h = _Harness();
      StreamSubscription<WebRtcPeerConnectionEvent>? subscription;
      try {
        await h.start();
        var entered = false;
        Future<void>? closing;
        final before = h.nativeEvents.length;
        subscription = h.adapter.events.listen((_) {
          if (entered) return;
          entered = true;
          h.peer.emit(_disconnected);
          h.peer.emit(_connected);
          closing = h.adapter.close();
        });
        h.peer.emit(_connected);
        await closing;
        await h.drain();
        expect(h.nativeEvents.skip(before).map((e) => e.connectionState), [
          WebRtcConnectionState.connected,
          WebRtcConnectionState.closed,
        ]);
        expect(h.dispatches.map((e) => e.type), [
          CallEventType.negotiationFailed,
        ]);
        h.expectReleased();
      } finally {
        await subscription?.cancel();
        await h.close();
      }
    }),
  );

  test(
    'ICE restart preserves generation and delivery after a full history',
    () => _guarded(() async {
      final h = _Harness(historyCapacity: 3);
      try {
        await h.start();
        for (var i = 0; i < 256; i++) {
          h.peer.emit(_connected);
          await h.drain();
        }
        expect(h.dispatches, isEmpty);
        expect(h.peer.restartCalls, 0);
        expect(await h.engine.restartIce(), 1);
        expect(h.peer.restartCalls, 1);
        final before = h.engineEvents.length;
        for (var i = 0; i < 256; i++) {
          h.peer.emit(_connected);
          await h.drain();
        }
        expect(h.engineEvents.length - before, 256);
        expect(h.adapter.recentEvents, hasLength(3));
        expect(h.engine.recentEvents, hasLength(3));
        expect(h.dispatches, isEmpty);
        expect(h.coordinator.activeSession?.state, CallState.connected);
        await h.hangup();
        h.expectReleased();
      } finally {
        await h.close();
      }
    }),
  );
}

Future<void> _guarded(Future<void> Function() body) async {
  final errors = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    try {
      await body();
      done.complete();
    } catch (error, stack) {
      done.completeError(error, stack);
    }
  }, (error, _) => errors.add(error));
  await done.future;
  expect(errors, isEmpty, reason: 'no unobserved stream or drain errors');
}

/// Pump only scheduled future continuations, never elapsed wall-clock time.
Future<void> _until(bool Function() complete) async {
  for (var i = 0; i < 500 && !complete(); i++) {
    await Future<void>.value();
  }
  expect(complete(), isTrue, reason: 'controlled asynchronous work completed');
}

final class _Harness {
  _Harness({CallId? callId, int historyCapacity = 64})
    : callId = callId ?? _callId {
    adapter = FlutterWebRtcPeerConnectionAdapter(
      eventBufferCapacity: historyCapacity,
      configureAndroidAudioFocus: () async {},
      peerConnectionFactory: (_) async => peer,
    );
    engine = FlutterWebRtcCallEngine(
      adapter: adapter,
      eventBufferCapacity: historyCapacity,
    );
    nativeSubscription = adapter.events.listen(
      nativeEvents.add,
      onDone: () => nativeDone = true,
    );
    engineSubscription = engine.events.listen(
      engineEvents.add,
      onDone: () => engineDone = true,
    );
    executor = CallNegotiationEffectExecutor(
      engine: engine,
      materialStore: CallNegotiationMaterialStore(),
      mediaPreparer: _UnusedPreparer(),
      signaling: _UnusedSignaling(),
      configuration: _configuration,
      dispatchEvent: (event) async {
        dispatches.add(event);
        if (event.type == blockedDispatchType && dispatchGate != null) {
          await dispatchGate!.future;
        }
        await coordinator.dispatch(event);
      },
      readActiveSnapshot: () => coordinator.activeSession,
      readStagedIceServers: (_) async => [],
      clock: () => _now,
      mediaReadinessTimerScheduler: polls,
    );
    coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator([
        CallCleanupStep('media', (_) async {
          cleanupCalls++;
          await executor.close();
        }, requiredForTerminalAck: true),
      ]),
      historyProjector: CallHistoryProjector(history, clock: () => _now),
      clock: () => _now,
      idSource: () => this.callId,
      timerScheduler: deadlines,
    );
  }

  final CallId callId;
  final peer = _NativePeer();
  final nativeEvents = <WebRtcPeerConnectionEvent>[];
  final engineEvents = <CallEngineEvent>[];
  final dispatches = <CallEvent>[];
  final history = _History();
  final polls = _Timers();
  final deadlines = _Timers();
  late final FlutterWebRtcPeerConnectionAdapter adapter;
  late final FlutterWebRtcCallEngine engine;
  late final CallNegotiationEffectExecutor executor;
  late final CallCoordinator coordinator;
  late final StreamSubscription<WebRtcPeerConnectionEvent> nativeSubscription;
  late final StreamSubscription<CallEngineEvent> engineSubscription;
  bool nativeDone = false;
  bool engineDone = false;
  int cleanupCalls = 0;
  int sequence = 0;
  CallEventType? blockedDispatchType;
  Completer<void>? dispatchGate;

  Future<void> start({bool connected = true}) async {
    await engine.createConnection(_configuration);
    await coordinator.placeCall(
      contactPeerId: 'remote',
      localAccountPeerId: 'local',
      localDeviceId: 'device',
    );
    await coordinator.dispatch(event(CallEventType.outgoingInviteReady));
    await coordinator.dispatch(event(CallEventType.remoteAccept));
    await coordinator.dispatch(event(CallEventType.negotiationReady));
    if (connected) {
      await coordinator.dispatch(event(CallEventType.mediaConnected));
    }
    expect(
      coordinator.activeSession?.state,
      connected ? CallState.connected : CallState.negotiating,
    );
  }

  CallEvent event(CallEventType type) => CallEvent(
    type: type,
    eventId: 'fixture-${sequence++}',
    occurredAt: _now,
    callId: callId,
  );

  Future<void> drain() => _until(
    () => executor.toDiagnosticMap()['engineEventDrainInFlight'] == false,
  );

  Future<void> hangup() async {
    await coordinator.dispatch(event(CallEventType.end));
    await drain();
  }

  void expectReleased() {
    expect(cleanupCalls, 1);
    expect(coordinator.terminalCleanupAckReady(callId), isTrue);
    expect(coordinator.activeSession, isNull);
    expect(history.entries, hasLength(1));
    expect(adapter.isClosed, isTrue);
    expect(engine.isClosed, isTrue);
    expect(peer.closeCalls, 1);
    expect(peer.disposeCalls, 1);
    expect(peer.onConnectionState, isNull);
    expect(nativeDone, isTrue);
    expect(engineDone, isTrue);
    expect(polls.active, isEmpty);
    expect(deadlines.active, isEmpty);
    expect(executor.toDiagnosticMap()['closed'], isTrue);
    expect(executor.toDiagnosticMap()['engineEventDrainInFlight'], isFalse);
    expect(executor.toDiagnosticMap()['pendingEngineEventCount'], 0);
  }

  Future<void> close() async {
    await coordinator.dispose();
    await executor.close();
    await nativeSubscription.cancel();
    await engineSubscription.cancel();
  }
}

final class _NativePeer implements webrtc.RTCPeerConnection {
  @override
  void Function(webrtc.RTCPeerConnectionState)? onConnectionState;
  @override
  webrtc.RTCPeerConnectionState get connectionState => _connected;
  Completer<List<webrtc.RTCRtpSender>>? sendersGate;
  int senderReads = 0;
  int restartCalls = 0;
  int closeCalls = 0;
  int disposeCalls = 0;
  void emit(webrtc.RTCPeerConnectionState state) =>
      onConnectionState?.call(state);

  @override
  Future<webrtc.RTCRtpTransceiver> addTransceiver({
    webrtc.MediaStreamTrack? track,
    webrtc.RTCRtpMediaType? kind,
    webrtc.RTCRtpTransceiverInit? init,
  }) async => _Transceiver();
  @override
  Future<List<webrtc.RTCRtpSender>> getSenders() async {
    senderReads++;
    return sendersGate?.future ?? [];
  }

  @override
  Future<List<webrtc.RTCRtpTransceiver>> getTransceivers() async => [];
  @override
  Future<List<webrtc.RTCRtpReceiver>> getReceivers() async => [];
  @override
  Future<List<webrtc.StatsReport>> getStats([
    webrtc.MediaStreamTrack? track,
  ]) async => [];
  @override
  Future<void> setConfiguration(Map<String, dynamic> configuration) async {}

  @override
  Future<void> restartIce() async => restartCalls++;
  @override
  Future<void> close() async => closeCalls++;
  @override
  Future<void> dispose() async => disposeCalls++;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

final class _Transceiver implements webrtc.RTCRtpTransceiver {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedPreparer implements CallNegotiationMediaPreparer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedSignaling implements CallNegotiationSignalingPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Timer implements CallTimerHandle {
  @override
  bool isActive = true;
  @override
  void cancel() => isActive = false;
}

final class _Timers implements CallTimerScheduler {
  final timers = <_Timer>[];
  Iterable<_Timer> get active => timers.where((t) => t.isActive);
  @override
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback) {
    final timer = _Timer();
    timers.add(timer);
    return timer;
  }
}

final class _History implements CallHistoryRepository {
  final entries = <CallHistoryEntry>[];
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;
  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async => [];
  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async =>
      entries.add(entry);
}
