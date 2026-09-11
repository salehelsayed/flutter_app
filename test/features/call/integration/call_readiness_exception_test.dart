import 'dart:async';

import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
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
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/webrtc_types.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 9, 11);
final _firstId = CallId.parse('11111111-1111-4111-8111-111111111111');
final _nextId = CallId.parse('22222222-2222-4222-8222-222222222222');
const _configuration = CallConnectionConfiguration(
  transportPolicy: CallTransportPolicy.relayOnly,
  receiveAudio: true,
  receiveVideo: false,
  captureAudio: true,
  captureVideo: false,
);
const _observationError = WebRtcAdapterException(WebRtcFailureReason.other);
const _unsafeText = 'v=0 private-sdp 192.0.2.7 turn:private password=secret';

void main() {
  for (final entry in <WebRtcFailureReason, String>{
    WebRtcFailureReason.other: 'observationUnavailable',
    WebRtcFailureReason.notReady: 'notReady',
    WebRtcFailureReason.transportUnavailable: 'transportUnavailable',
    WebRtcFailureReason.configurationRejected: 'configurationRejected',
    WebRtcFailureReason.closed: 'closed',
    WebRtcFailureReason.none: 'other',
  }.entries) {
    test('real engine normalizes snapshot ${entry.key.name}', () async {
      final native = _Native()
        ..snapshotError = WebRtcAdapterException(entry.key);
      final engine = FlutterWebRtcCallEngine(adapter: native);
      try {
        await engine.createConnection(_configuration);
        await expectLater(
          engine.snapshot(),
          throwsA(
            isA<CallEngineException>().having(
              (error) => error.code.name,
              'code',
              entry.value,
            ),
          ),
        );
        expect(native.snapshotCalls, 1);
        expect(native.closeCalls, 0);
      } finally {
        await engine.close();
      }
    });
  }

  for (final laterPoll in [false, true]) {
    test(
      '${laterPoll ? 'later poll' : 'initial event drain'} retries an adapter '
      'observation failure without claiming readiness',
      () => _guarded(() async {
        final h = _Harness();
        try {
          final b = await h.start();
          b.native.snapshotError = laterPoll ? null : _observationError;
          b.native.emit(WebRtcConnectionState.connected);
          await _settle();
          if (laterPoll) {
            expect(b.native.snapshotCalls, 1);
            b.native.snapshotError = _observationError;
            b.polls.fireNext();
            await _settle();
          }
          expect(h.coordinator.activeSession?.state, CallState.negotiating);
          expect(h.mediaConnected, isEmpty);
          expect(h.failures, isEmpty);
          expect(b.native.closeCalls, 0);
          expect(b.native.microphoneOwned, isTrue);
          expect(b.executor.toDiagnosticMap()['observationFailureCount'], 1);
          expect(
            b.executor.toDiagnosticMap()['lastFailureCode'],
            'observationUnavailable',
          );
          expect(
            b.executor.toDiagnosticMap()['engineEventDrainInFlight'],
            isFalse,
          );
          expect(b.polls.active, hasLength(1));

          b.native.snapshotError = null;
          b.native.ready = true;
          b.polls.fireNext();
          await _settle();
          expect(h.coordinator.activeSession?.state, CallState.connected);
          expect(h.mediaConnected, hasLength(1));
          expect(b.polls.active, isEmpty);
          expect(h.deadlines.active, isEmpty);
          b.native.emit(WebRtcConnectionState.connected);
          await _settle();
          expect(h.mediaConnected, hasLength(1));
          await h.hangup();
          h.expectReleased(b);
        } finally {
          await h.close();
        }
      }),
    );
  }

  for (final sampleLimit in <int?>[null, 3]) {
    test(
      'observation failures preserve the coordinator deadline '
      'with sample limit $sampleLimit',
      () => _guarded(() async {
        final h = _Harness(maxSamples: sampleLimit);
        try {
          final b = await h.start();
          final deadline = h.deadlines.active.single;
          b.native.snapshotError = _observationError;
          b.native.emit(WebRtcConnectionState.connected);
          await _settle();
          for (var i = 0; i < 2; i++) {
            b.polls.fireNext();
            await _settle();
          }
          expect(b.native.snapshotCalls, 3);
          expect(b.executor.toDiagnosticMap()['observationFailureCount'], 3);
          expect(b.polls.active, hasLength(sampleLimit == null ? 1 : 0));
          expect(h.deadlines.active.single, same(deadline));
          expect(h.coordinator.activeSession?.state, CallState.negotiating);
          expect(h.failures, isEmpty);
          expect(h.mediaConnected, isEmpty);
          expect(b.native.closeCalls, 0);
          b.native.emit(WebRtcConnectionState.connected);
          await _settle();
          expect(b.native.snapshotCalls, 3);
          h.deadlines.fireNext();
          await _settle();
          expect(h.coordinator.activeSession, isNull);
          expect(
            h.coordinator.lastSnapshot?.endReason,
            CallEndReason.mediaFailed,
          );
          h.expectReleased(b);
        } finally {
          await h.close();
        }
      }),
    );
  }

  for (final fatal in [
    'transportUnavailable',
    'configurationRejected',
    'closed',
    'relayPolicyViolation',
    'unexpected',
    'failedSnapshot',
    'closedSnapshot',
  ]) {
    test(
      '$fatal produces one exact-call terminal transition and cleanup',
      () => _guarded(() async {
        final h = _Harness();
        try {
          final b = await h.start();
          switch (fatal) {
            case 'relayPolicyViolation':
              b.native.transport = WebRtcTransportClass.direct;
            case 'unexpected':
              b.native.snapshotError = StateError(_unsafeText);
            case 'failedSnapshot':
              b.native.state = WebRtcConnectionState.failed;
            case 'closedSnapshot':
              b.native.snapshotClosed = true;
            default:
              b.native.snapshotError = WebRtcAdapterException(
                WebRtcFailureReason.values.byName(fatal),
              );
          }
          b.native.ready = true;
          b.native.emit(WebRtcConnectionState.connected);
          b.native.emit(WebRtcConnectionState.connected);
          await _settle();
          expect(h.coordinator.activeSession, isNull);
          expect(
            h.coordinator.lastSnapshot?.endReason,
            CallEndReason.mediaFailed,
          );
          expect(h.failures.map((event) => event.callId), [_firstId]);
          expect(h.mediaConnected, isEmpty);
          expect(h.history.entries, hasLength(1));
          final diagnostics = b.executor.toDiagnosticMap();
          expect(diagnostics['lastFailureStage'], 'mediaReadiness');
          expect(
            diagnostics['unexpectedFailureCount'],
            fatal == 'unexpected' ? 1 : 0,
          );
          expect(diagnostics['lastFailureCode'], switch (fatal) {
            'unexpected' => 'unexpected',
            'failedSnapshot' => 'transportUnavailable',
            'closedSnapshot' => 'closed',
            _ => fatal,
          });
          expect(diagnostics.toString(), isNot(contains(_unsafeText)));
          expect(diagnostics.toString(), isNot(contains(_firstId.value)));
          h.expectReleased(b);
          await h.coordinator.retryTerminalCleanup(_firstId);
          h.expectReleased(b);
        } finally {
          await h.close();
        }
      }),
    );
  }

  test(
    'event drain releases in-flight state and processes a queued recovery '
    'after an obsolete observation error',
    () => _guarded(() async {
      final h = _Harness();
      try {
        final b = await h.start();
        final pending = b.native.pendingSnapshot =
            Completer<WebRtcPeerConnectionSnapshot>();
        b.native.emit(WebRtcConnectionState.connected);
        await _settle();
        expect(b.native.snapshotCalls, 1);
        b.native.emit(WebRtcConnectionState.disconnected);
        b.native.emit(WebRtcConnectionState.connected);
        b.native.pendingSnapshot = null;
        b.native.ready = true;
        pending.completeError(_observationError);
        await _settle();
        expect(b.native.snapshotCalls, 2);
        expect(h.coordinator.activeSession?.state, CallState.connected);
        expect(h.mediaConnected, hasLength(1));
        expect(h.failures, isEmpty);
        expect(
          b.executor.toDiagnosticMap()['engineEventDrainInFlight'],
          isFalse,
        );
        expect(b.executor.toDiagnosticMap()['staleCompletionCount'], 1);
        await h.hangup();
        h.expectReleased(b);
      } finally {
        await h.close();
      }
    }),
  );

  for (final inTimer in [false, true]) {
    test(
      'unexpected ${inTimer ? 'timer' : 'event drain'} callback failure '
      'is observed and terminates through the coordinator',
      () => _guarded(() async {
        final h = _Harness();
        try {
          final b = await h.start();
          b.polls.failSchedule = !inTimer;
          b.native.emit(WebRtcConnectionState.connected);
          await _settle();
          if (inTimer) {
            b.polls.failSchedule = true;
            b.polls.fireNext();
            await _settle();
          }
          expect(h.failures, hasLength(1));
          expect(
            h.coordinator.lastSnapshot?.endReason,
            CallEndReason.mediaFailed,
          );
          expect(b.executor.toDiagnosticMap()['unexpectedFailureCount'], 1);
          expect(
            b.executor.toDiagnosticMap()['lastFailureStage'],
            inTimer ? 'mediaReadinessTimer' : 'engineEventDrain',
          );
          h.expectReleased(b);
        } finally {
          await h.close();
        }
      }),
    );
  }

  test(
    'unexpected effect error returns a controlled canonical failure',
    () => _guarded(() async {
      final h = _Harness();
      try {
        final b = await h.start(offerError: StateError(_unsafeText));
        expect(h.coordinator.activeSession, isNull);
        expect(
          h.coordinator.lastSnapshot?.endReason,
          CallEndReason.mediaFailed,
        );
        expect(h.history.entries, hasLength(1));
        expect(b.executor.toDiagnosticMap()['lastFailureStage'], 'effect');
        expect(b.executor.toDiagnosticMap()['unexpectedFailureCount'], 1);
        h.expectReleased(b);
      } finally {
        await h.close();
      }
    }),
  );

  test(
    'failed canonical dispatch is recorded once and preserves deadline cleanup',
    () => _guarded(() async {
      final h = _Harness();
      try {
        final b = await h.start();
        h.dispatchError = StateError(_unsafeText);
        b.native.snapshotError = const WebRtcAdapterException(
          WebRtcFailureReason.transportUnavailable,
        );
        b.native.emit(WebRtcConnectionState.connected);
        await _settle();
        for (var i = 0; i < 3; i++) {
          b.native.emit(WebRtcConnectionState.failed);
          await _settle();
        }
        expect(h.failures, hasLength(1));
        expect(b.executor.toDiagnosticMap()['dispatchFailureCount'], 1);
        expect(b.executor.toDiagnosticMap()['lastFailureStage'], 'dispatch');
        expect(b.executor.toDiagnosticMap()['unexpectedFailureCount'], 1);
        expect(
          b.executor.toDiagnosticMap()['engineEventDrainInFlight'],
          isFalse,
        );
        expect(b.polls.active, isEmpty);
        expect(h.deadlines.active, hasLength(1));
        h.deadlines.fireNext();
        await _settle();
        expect(
          h.coordinator.lastSnapshot?.endReason,
          CallEndReason.mediaFailed,
        );
        h.expectReleased(b);
      } finally {
        await h.close();
      }
    }),
  );

  for (final fail in [false, true]) {
    test(
      'hangup retires a pending initial event drain with ${fail ? 'error' : 'result'}',
      () => _guarded(() async {
        final h = _Harness();
        try {
          final old = await h.start();
          final pending = old.native.pendingSnapshot =
              Completer<WebRtcPeerConnectionSnapshot>();
          old.native.emit(WebRtcConnectionState.connected);
          await _settle();
          expect(
            old.executor.toDiagnosticMap()['engineEventDrainInFlight'],
            isTrue,
          );
          await h.hangup();
          h.expectReleased(old);
          final next = await h.start(callId: _nextId);
          if (fail) {
            pending.completeError(_observationError);
          } else {
            pending.complete(_snapshot(ready: true));
          }
          await _settle();
          expect(
            old.executor.toDiagnosticMap()['engineEventDrainInFlight'],
            isFalse,
          );
          expect(old.executor.toDiagnosticMap()['staleCompletionCount'], 1);
          expect(h.failures, isEmpty);
          expect(h.mediaConnected, isEmpty);
          expect(h.coordinator.activeSession?.callId, _nextId);
          expect(next.native.microphoneOwned, isTrue);
          expect(next.native.closeCalls, 0);
          await h.hangup();
          h.expectReleased(next);
        } finally {
          await h.close();
        }
      }),
    );
  }

  for (final completion in ['ready', 'adapterError', 'unexpectedError']) {
    test(
      'hangup fences pending $completion and leaves the subsequent call healthy',
      () => _guarded(() async {
        final h = _Harness();
        try {
          final old = await h.start();
          old.native.emit(WebRtcConnectionState.connected);
          await _settle();
          final staleTimer = old.polls.active.single;
          final pending = old.native.pendingSnapshot =
              Completer<WebRtcPeerConnectionSnapshot>();
          old.polls.fireNext();
          await _settle();
          expect(old.native.snapshotCalls, 2);
          await h.hangup();
          h.expectReleased(old);
          final next = await h.start(callId: _nextId);
          switch (completion) {
            case 'ready':
              pending.complete(_snapshot(ready: true));
            case 'adapterError':
              pending.completeError(_observationError);
            default:
              pending.completeError(StateError(_unsafeText));
          }
          unawaited(staleTimer.callback());
          await _settle();
          expect(h.coordinator.activeSession?.callId, _nextId);
          expect(h.coordinator.activeSession?.state, CallState.negotiating);
          expect(h.failures, isEmpty);
          expect(h.mediaConnected, isEmpty);
          expect(old.native.snapshotCalls, 2);
          expect(next.native.closeCalls, 0);
          expect(next.native.microphoneOwned, isTrue);
          next.native.ready = true;
          next.native.emit(WebRtcConnectionState.connected);
          await _settle();
          expect(h.coordinator.activeSession?.state, CallState.connected);
          expect(h.mediaConnected.map((event) => event.callId), [_nextId]);
          await h.hangup();
          h.expectReleased(old);
          h.expectReleased(next);
          expect(h.history.entries.map((entry) => entry.terminalReason), [
            CallEndReason.localHangup,
            CallEndReason.localHangup,
          ]);
        } finally {
          await h.close();
        }
      }),
    );
  }
}

/// Stream listeners and timer callbacks deliberately launch unawaited work,
/// like production. Assertions cross the zone explicitly so a failing body
/// cannot strand the test in a different error zone.
Future<void> _guarded(Future<void> Function() body) async {
  final escaped = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    try {
      await body();
      await _settle();
      done.complete();
    } catch (error, stack) {
      done.completeError(error, stack);
    }
  }, (error, _) => escaped.add(error));
  await done.future;
  expect(escaped, isEmpty, reason: 'no unhandled callback or future errors');
}

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Harness implements CallEffectExecutor {
  _Harness({this.maxSamples}) {
    coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator([
        CallCleanupStep('media', (snapshot) async {
          final bundle = bundles.singleWhere(
            (b) => b.callId == snapshot.callId,
          );
          bundle.cleanupCalls++;
          await bundle.executor.close();
          await bundle.audio.close();
        }, requiredForTerminalAck: true),
      ]),
      historyProjector: CallHistoryProjector(history, clock: () => _now),
      effectExecutor: this,
      clock: () => _now,
      idSource: () => current.callId,
      timerScheduler: deadlines,
    );
  }

  final int? maxSamples;
  final deadlines = _Timers();
  final history = _History();
  final shared = _SharedSignaling();
  final bundles = <_Bundle>[];
  final events = <CallEvent>[];
  late final CallCoordinator coordinator;
  late _Bundle current;
  int sequence = 0;
  Object? dispatchError;

  Iterable<CallEvent> get failures =>
      events.where((e) => e.type == CallEventType.negotiationFailed);
  Iterable<CallEvent> get mediaConnected =>
      events.where((e) => e.type == CallEventType.mediaConnected);

  Future<_Bundle> start({CallId? callId, Object? offerError}) async {
    current = _Bundle(this, callId ?? _firstId);
    current.native.offerError = offerError;
    bundles.add(current);
    await coordinator.placeCall(
      contactPeerId: 'remote-account',
      localAccountPeerId: 'local-account',
      localDeviceId: 'local-device',
    );
    await coordinator.dispatch(event(CallEventType.outgoingInviteReady));
    await coordinator.dispatch(event(CallEventType.remoteAccept));
    if (offerError == null) {
      expect(coordinator.activeSession?.state, CallState.negotiating);
      expect(current.audio.state.active, isTrue);
    }
    return current;
  }

  CallEvent event(CallEventType type) => CallEvent(
    type: type,
    eventId: 'local-${sequence++}',
    occurredAt: _now,
    callId: current.callId,
  );

  Future<void> hangup() async {
    await coordinator.dispatch(event(CallEventType.end));
    await _settle();
  }

  @override
  Future<CallEvent?> execute(CallEffect effect, CallSessionSnapshot snapshot) =>
      current.executor.execute(effect, snapshot);

  void expectReleased(_Bundle b) {
    expect(b.cleanupCalls, 1);
    expect(coordinator.terminalCleanupAckReady(b.callId), isTrue);
    expect(b.native.closeCalls, 1);
    expect(b.native.microphoneOwned, isFalse);
    expect(b.native.eventsController.hasListener, isFalse);
    expect(b.native.candidates.hasListener, isFalse);
    expect(b.session.interruptionsController.hasListener, isFalse);
    expect(b.session.ownsSession, isFalse);
    expect(b.conflicts.owned, isFalse);
    expect(b.conflicts.releaseCalls, 1);
    expect(b.audio.state.active, isFalse);
    expect(b.engine.isClosed, isTrue);
    expect(b.executor.toDiagnosticMap()['closed'], isTrue);
    expect(b.executor.toDiagnosticMap()['mediaReadinessSampling'], isFalse);
    expect(b.polls.active, isEmpty);
    if (coordinator.activeSession == null) expect(deadlines.active, isEmpty);
    shared.sendChatProbe();
    expect(shared.shutdownCalls, 0);
  }

  Future<void> close() async {
    await coordinator.dispose();
    for (final b in bundles) {
      await b.executor.close();
      await b.audio.close();
      await b.session.interruptionsController.close();
    }
  }
}

final class _Bundle implements CallNegotiationMediaPreparer {
  _Bundle(_Harness h, this.callId) {
    engine = FlutterWebRtcCallEngine(adapter: native);
    audio = CallAudioController(
      engine: engine,
      microphonePermission: _Permission(),
      mediaConflicts: conflicts,
      audioSession: session,
    );
    executor = CallNegotiationEffectExecutor(
      engine: engine,
      materialStore: CallNegotiationMaterialStore(),
      mediaPreparer: this,
      signaling: h.shared,
      configuration: _configuration,
      dispatchEvent: (event) async {
        h.events.add(event);
        if (h.dispatchError case final error?) throw error;
        await h.coordinator.dispatch(event);
      },
      readActiveSnapshot: () => h.coordinator.activeSession,
      readStagedIceServers: (_) async => const [],
      clock: () => _now,
      mediaReadinessTimerScheduler: polls,
      maxMediaReadinessSamples: h.maxSamples,
    );
  }

  final CallId callId;
  final native = _Native();
  final polls = _Timers();
  final session = _AudioSession();
  final conflicts = _Conflicts();
  late final FlutterWebRtcCallEngine engine;
  late final CallAudioController audio;
  late final CallNegotiationEffectExecutor executor;
  int cleanupCalls = 0;

  @override
  Future<void> prepareLocallyAcceptedMedia({
    required CallSessionSnapshot snapshot,
    required CallConnectionConfiguration configuration,
  }) async {
    final result = await audio.start(
      locallyAccepted: true,
      configuration: configuration,
    );
    if (result.status != CallAudioStartStatus.started) {
      throw const CallNegotiationPortException(
        CallNegotiationPortErrorCode.mediaUnavailable,
      );
    }
  }
}

WebRtcPeerConnectionSnapshot _snapshot({
  bool ready = false,
  WebRtcTransportClass transport = WebRtcTransportClass.relay,
  WebRtcConnectionState state = WebRtcConnectionState.connected,
  bool isClosed = false,
}) => WebRtcPeerConnectionSnapshot(
  isClosed: isClosed,
  iceTransportPolicy: WebRtcIceTransportPolicy.relayOnly,
  localAudioCaptureTrackCount: 1,
  localVideoCaptureTrackCount: 0,
  audioReceiveTransceiverCount: 1,
  videoTransceiverCount: 0,
  connectionState: state,
  transport: transport,
  selectedPairSucceeded: ready,
  selectedPairNominated: ready,
  dtlsReady: ready,
  localAudioSenderAttached: true,
  localAudioTrackLive: true,
  remoteAudioReceiverAttached: true,
  remoteAudioTrackLive: true,
);

final class _Native
    implements WebRtcPeerConnectionAdapter, WebRtcLocalCandidateSource {
  final eventsController =
      StreamController<WebRtcPeerConnectionEvent>.broadcast(sync: true);
  final candidates = StreamController<CallIceCandidate>.broadcast(sync: true);
  Object? snapshotError;
  Object? offerError;
  Completer<WebRtcPeerConnectionSnapshot>? pendingSnapshot;
  int snapshotCalls = 0;
  int closeCalls = 0;
  bool microphoneOwned = false;
  bool ready = false;
  bool snapshotClosed = false;
  WebRtcTransportClass transport = WebRtcTransportClass.relay;
  WebRtcConnectionState state = WebRtcConnectionState.connected;

  void emit(WebRtcConnectionState state) => eventsController.add(
    WebRtcPeerConnectionEvent(
      kind: WebRtcPeerConnectionEventKind.state,
      connectionState: state,
      transport: WebRtcTransportClass.relay,
      quality: WebRtcQualityBand.unknown,
      failureReason: WebRtcFailureReason.none,
    ),
  );

  @override
  bool isClosed = false;
  @override
  Stream<WebRtcPeerConnectionEvent> get events => eventsController.stream;
  @override
  Stream<CallIceCandidate> get localCandidates => candidates.stream;
  @override
  Future<void> create(WebRtcPeerConnectionConfiguration configuration) async {
    microphoneOwned = configuration.captureAudio;
  }

  @override
  Future<CallSessionDescription> createOffer() async {
    if (offerError case final error?) throw error;
    return const CallSessionDescription(
      type: CallSessionDescriptionType.offer,
      value:
          'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:0\r\n'
          'a=fingerprint:sha-256 00:01:02:03:04:05:06:07:08:09:0A:0B:0C:0D:0E:0F:'
          '10:11:12:13:14:15:16:17:18:19:1A:1B:1C:1D:1E:1F\r\na=sendrecv',
    );
  }

  @override
  Future<CallSessionDescription> createAnswer() => throw UnimplementedError();
  @override
  Future<void> setLocalDescription(CallSessionDescription description) async {}
  @override
  Future<void> setRemoteDescription(CallSessionDescription description) async {}
  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) async {}
  @override
  Future<void> restartIce() async {}
  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {}
  @override
  Future<WebRtcPeerConnectionSnapshot> snapshot() async {
    snapshotCalls++;
    if (pendingSnapshot case final pending?) return pending.future;
    if (snapshotError case final error?) throw error;
    return _snapshot(
      ready: ready,
      transport: transport,
      state: state,
      isClosed: snapshotClosed,
    );
  }

  @override
  Future<void> close() async {
    closeCalls++;
    isClosed = true;
    microphoneOwned = false;
    await eventsController.close();
    await candidates.close();
  }
}

final class _Timer implements CallTimerHandle {
  _Timer(this.callback);
  final Future<void> Function() callback;
  @override
  bool isActive = true;
  @override
  void cancel() => isActive = false;
}

final class _Timers implements CallTimerScheduler {
  final timers = <_Timer>[];
  bool failSchedule = false;
  List<_Timer> get active => timers.where((timer) => timer.isActive).toList();
  @override
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback) {
    if (failSchedule) throw StateError(_unsafeText);
    final timer = _Timer(callback);
    timers.add(timer);
    return timer;
  }

  void fireNext() {
    final timer = active.first;
    timer.isActive = false;
    unawaited(timer.callback());
  }
}

final class _Permission implements CallMicrophonePermission {
  @override
  Future<MicPermissionStatus> request() async => MicPermissionStatus.granted;
}

final class _Conflicts
    implements CallMediaConflictPort, CallMediaConflictLease {
  bool owned = false;
  int releaseCalls = 0;
  @override
  Future<CallMediaConflictLease> acquireForCall() async {
    owned = true;
    return this;
  }

  @override
  Future<void> release() async {
    owned = false;
    releaseCalls++;
  }
}

final class _AudioSession implements CallForegroundAudioSession {
  final interruptionsController =
      StreamController<CallAudioSessionInterruption>.broadcast();
  @override
  bool ownsSession = false;
  @override
  Stream<CallAudioSessionInterruption> get interruptions =>
      interruptionsController.stream;
  @override
  Future<void> activate() async => ownsSession = true;
  @override
  Future<void> deactivate() async => ownsSession = false;
}

final class _SharedSignaling implements CallNegotiationSignalingPort {
  int shutdownCalls = 0;
  void shutdownSharedConnection() => shutdownCalls++;
  void sendChatProbe() => expect(shutdownCalls, 0);
  @override
  Future<void> sendIceRestart({
    required CallId callId,
    required int iceGeneration,
  }) async {}
  @override
  Future<void> sendDescription({
    required CallId callId,
    required CallSessionDescription description,
    required int iceGeneration,
  }) async {}
  @override
  Future<void> sendCandidates({
    required CallId callId,
    required List<CallIceCandidate> candidates,
  }) async {}
}

final class _History implements CallHistoryRepository {
  final entries = <CallHistoryEntry>[];
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;
  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      const [];
  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async =>
      entries.add(entry);
}
