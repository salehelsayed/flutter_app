import 'dart:async';

import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_audio_negotiation_preparer.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_control_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_negotiation_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_negotiation_material_store.dart';
import 'package:flutter_app/features/call/application/call_scoped_media_bundle_owner.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/call_audio_route_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/webrtc_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// A blocked microphone must end the call as a microphone problem, not as a
/// generic media failure. The callee sees the Settings notice only for
/// [CallEndReason.permissionDenied], and the peer must receive the
/// `permission_denied` wire reason. This wires the production per-call media
/// bundle (real WebRTC engine over a fake native adapter, real audio
/// controller, real preparer, real negotiation and control executors) around
/// one real coordinator.
void main() {
  for (final direction in CallDirection.values) {
    for (final status in <MicPermissionStatus>[
      MicPermissionStatus.permanentlyDenied,
      MicPermissionStatus.denied,
    ]) {
      test(
        '${direction.name} call with microphone ${status.name} ends as '
        'permissionDenied and terminates the peer with permission_denied',
        () async {
          final h = _Harness(permission: status);
          try {
            await h.accept(direction);
            await _settle();

            final terminal = h.coordinator.lastSnapshot;
            expect(
              terminal?.endReason,
              CallEndReason.permissionDenied,
              reason:
                  'terminal snapshot: $terminal\n'
                  'negotiation events: ${h.negotiationEvents}\n'
                  'audio start results: ${h.startResults}',
            );
            expect(terminal?.state, CallState.ended);
            expect(h.coordinator.activeSession, isNull);
            expect(h.startResults, <CallAudioStartStatus>[
              CallAudioStartStatus.permissionDenied,
            ]);
            final terminates = h.sentSignals
                .where((signal) => signal.event == CallSignalType.terminate)
                .toList();
            expect(terminates, hasLength(1), reason: 'sent: ${h.sentSignals}');
            expect(terminates.single.payload, <String, Object?>{
              'reason': 'permission_denied',
            });
            expect(h.engine.isClosed, isTrue);
            expect(h.audio.state.active, isFalse);
          } finally {
            await h.close();
          }
        },
      );
    }
  }

  test(
    'engine closing after media was prepared still ends as mediaFailed',
    () async {
      final h = _Harness(permission: MicPermissionStatus.granted);
      try {
        await h.placeCallAndGetAccepted();
        await _settle();
        expect(h.coordinator.activeSession?.state, CallState.negotiating);
        expect(h.startResults, <CallAudioStartStatus>[
          CallAudioStartStatus.started,
        ]);

        h.native.emitClosed();
        await _settle();

        final terminal = h.coordinator.lastSnapshot;
        expect(
          terminal?.endReason,
          CallEndReason.mediaFailed,
          reason: 'negotiation events: ${h.negotiationEvents}',
        );
        final terminates = h.sentSignals
            .where((signal) => signal.event == CallSignalType.terminate)
            .toList();
        expect(terminates, hasLength(1), reason: 'sent: ${h.sentSignals}');
        expect(terminates.single.payload, <String, Object?>{
          'reason': 'media_failed',
        });
        expect(h.failureObservations, _closedFailureObservation);
      } finally {
        await h.close();
      }
    },
  );

  // A real native close that arrives while media preparation is still in
  // flight, and the preparation then succeeds, must still end the call as
  // mediaFailed before media is accepted. It must not leave the call in
  // accepted with no terminal reason until a deadline.
  for (final direction in CallDirection.values) {
    test('${direction.name} call: native close during connection create, '
        'preparation then succeeds, ends as mediaFailed', () async {
      final h = _Harness(permission: MicPermissionStatus.granted);
      h.native.onCreate = h.native.emitClosed;
      try {
        await h.accept(direction);
        await _settle();
        _expectEndedAsMediaFailedAfterStartedAudio(h);
      } finally {
        await h.close();
      }
    });

    test(
      '${direction.name} call: native close during route enumeration after '
      'connection create, preparation then succeeds, ends as mediaFailed',
      () async {
        late final _Harness h;
        var closeEmitted = false;
        final routes = CallAudioRouteAdapter(
          enumerateOutputs: () async {
            // Terminal cleanup enumerates routes again. Emit the close once.
            if (!closeEmitted) {
              closeEmitted = true;
              h.native.emitClosed();
            }
            return const <CallAudioOutputRoute>[
              CallAudioOutputRoute.systemDefault,
            ];
          },
          selectOutput: (_) async {},
          setSpeakerphone: null,
        );
        h = _Harness(
          permission: MicPermissionStatus.granted,
          audioRoutePort: routes,
        );
        try {
          await h.accept(direction);
          await _settle();
          _expectEndedAsMediaFailedAfterStartedAudio(h);
        } finally {
          await h.close();
        }
      },
    );
  }

  for (final status in <MicPermissionStatus>[
    MicPermissionStatus.permanentlyDenied,
    MicPermissionStatus.denied,
  ]) {
    test(
      'a native close pending during preparation does not pre-empt '
      'microphone ${status.name}: the call still ends as permissionDenied',
      () async {
        late final _Harness h;
        h = _Harness(
          permission: status,
          beforeMicPermissionResult: () => h.native.emitClosed(),
        );
        try {
          await h.answerIncomingCall();
          await _settle();

          final terminal = h.coordinator.lastSnapshot;
          expect(
            terminal?.endReason,
            CallEndReason.permissionDenied,
            reason:
                'terminal snapshot: $terminal\n'
                'negotiation events: ${h.negotiationEvents}\n'
                'audio start results: ${h.startResults}',
          );
          expect(terminal?.state, CallState.ended);
          expect(h.coordinator.activeSession, isNull);
          expect(h.startResults, <CallAudioStartStatus>[
            CallAudioStartStatus.permissionDenied,
          ]);
          final terminates = h.sentSignals
              .where((signal) => signal.event == CallSignalType.terminate)
              .toList();
          expect(terminates, hasLength(1), reason: 'sent: ${h.sentSignals}');
          expect(terminates.single.payload, <String, Object?>{
            'reason': 'permission_denied',
          });
          // A typed denial is the call's reason. The held close is not
          // replayed, so no media failure is recorded.
          expect(h.failureObservations, isEmpty);
        } finally {
          await h.close();
        }
      },
    );
  }

  test('local hang-up during preparation followed by a native close keeps '
      'localHangup, never mediaFailed', () async {
    late final _Harness h;
    var interrupted = false;
    final routes = CallAudioRouteAdapter(
      enumerateOutputs: () async {
        if (!interrupted) {
          interrupted = true;
          // The hang-up is requested first; the native close lands while
          // the hang-up reduction is still waiting on the preparation fence.
          unawaited(h.hangUp());
          h.native.emitClosed();
        }
        return const <CallAudioOutputRoute>[CallAudioOutputRoute.systemDefault];
      },
      selectOutput: (_) async {},
      setSpeakerphone: null,
    );
    h = _Harness(
      permission: MicPermissionStatus.granted,
      audioRoutePort: routes,
    );
    try {
      await h.answerIncomingCall();
      await _settle();

      final terminal = h.coordinator.lastSnapshot;
      expect(
        terminal?.endReason,
        CallEndReason.localHangup,
        reason:
            'terminal snapshot: $terminal\n'
            'negotiation events: ${h.negotiationEvents}\n'
            'audio start results: ${h.startResults}',
      );
      expect(terminal?.state, CallState.ended);
      expect(h.coordinator.activeSession, isNull);
      final terminates = h.sentSignals
          .where((signal) => signal.event == CallSignalType.terminate)
          .toList();
      expect(terminates, hasLength(1), reason: 'sent: ${h.sentSignals}');
      expect(terminates.single.payload, <String, Object?>{
        'reason': 'local_hangup',
      });
      // The hang-up is still queued behind the preparation fence, so the
      // call is current when the close is replayed. The engine did close, so
      // it is recorded once, as an unheld close racing a hang-up would be.
      // The end reason above stays localHangup.
      expect(h.failureObservations, _closedFailureObservation);
    } finally {
      await h.close();
    }
  });
}

void _expectEndedAsMediaFailedAfterStartedAudio(_Harness h) {
  final terminal = h.coordinator.lastSnapshot;
  expect(
    terminal?.endReason,
    CallEndReason.mediaFailed,
    reason:
        'terminal snapshot: $terminal\n'
        'negotiation events: ${h.negotiationEvents}\n'
        'audio start results: ${h.startResults}',
  );
  expect(terminal?.state, CallState.ended);
  expect(h.coordinator.activeSession, isNull);
  expect(h.startResults, <CallAudioStartStatus>[CallAudioStartStatus.started]);
  final terminates = h.sentSignals
      .where((signal) => signal.event == CallSignalType.terminate)
      .toList();
  expect(terminates, hasLength(1), reason: 'sent: ${h.sentSignals}');
  expect(terminates.single.payload, <String, Object?>{
    'reason': 'media_failed',
  });
  // The held close is recorded once when it is replayed, exactly as a close
  // after preparation would be.
  expect(h.failureObservations, _closedFailureObservation);
}

const _closedFailureObservation = <String>['none:terminal'];

final _now = DateTime.utc(2026, 10, 15, 23, 6, 30);
final _callId = CallId.parse('11111111-1111-4111-8111-111111111111');
const _callHandle = '22222222-2222-4222-8222-222222222222';
const _localAccount = 'local-account';
const _localDevice = 'local-device';
const _remoteAccount = 'remote-account';
const _remoteDevice = 'remote-device';

Future<void> _settle() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Harness {
  _Harness({
    required MicPermissionStatus permission,
    void Function()? beforeMicPermissionResult,
    CallAudioRoutePort? audioRoutePort,
  }) {
    engine = FlutterWebRtcCallEngine(
      adapter: native,
      audioRoutePort: audioRoutePort,
    );
    audio = CallAudioController(
      engine: engine,
      microphonePermission: _Permission(
        permission,
        beforeResult: beforeMicPermissionResult,
      ),
      mediaConflicts: _Conflicts(),
      audioSession: _AudioSession(),
    );
    // Mirrors the production bundle factory in
    // production_call_signaling_graph.dart (CallAudioNegotiationPreparer).
    final preparer = CallAudioNegotiationPreparer(
      startAudio: audio.start,
      isCurrentCall: (id) =>
          id == _callId &&
          !engine.isClosed &&
          coordinator.activeSession?.callId == _callId &&
          coordinator.activeSession?.isTerminal == false,
      readInitialIceServers: (_) async => const <CallIceServer>[],
      clock: () => _now,
      onStartResult: startResults.add,
    );
    executor = CallNegotiationEffectExecutor(
      onFailureObservation: (_, reason, disposition) =>
          failureObservations.add('${reason.name}:${disposition.name}'),
      engine: engine,
      materialStore: CallNegotiationMaterialStore(),
      mediaPreparer: preparer,
      signaling: _NegotiationSignaling(),
      configuration: const CallConnectionConfiguration(
        transportPolicy: CallTransportPolicy.all,
        receiveAudio: true,
        receiveVideo: false,
        captureAudio: true,
        captureVideo: false,
      ),
      dispatchEvent: (event) async {
        negotiationEvents.add('${event.type.name}:${event.endReason?.name}');
        await coordinator.dispatch(event);
      },
      readActiveSnapshot: () => coordinator.activeSession,
      readStagedIceServers: (_) async => const <CallIceServer>[],
      clock: () => _now,
      mediaReadinessTimerScheduler: _Timers(),
    );
    final mediaOwner = CallScopedMediaBundleOwner(
      createBundle: (callId) => CallScopedMediaBundle(
        callId: callId,
        engine: engine,
        audioController: audio,
        negotiationExecutor: executor,
        close: () async {
          await audio.close();
          await executor.close();
        },
      ),
    );
    final controlExecutor = CallControlEffectExecutor(
      contextStore: contextStore,
      signalingPort: _ControlPort(sentSignals),
      clock: () => _now,
      idSource: _nextMessageId,
    );
    coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep(
          'call_media',
          (snapshot) => mediaOwner.closeCall(snapshot.callId!),
          requiredForTerminalAck: true,
        ),
        CallCleanupStep('call_signaling_context', (snapshot) async {
          await controlExecutor.retireOutgoingPreconnectInvite(snapshot);
          contextStore.purge(snapshot.callId!);
        }, requiredForTerminalAck: true),
      ]),
      historyProjector: CallHistoryProjector(_History(), clock: () => _now),
      effectExecutor: CompositeCallEffectExecutor(
        controlExecutor: controlExecutor,
        negotiationExecutor: mediaOwner,
      ),
      clock: () => _now,
      idSource: () => _callId,
      timerScheduler: _Timers(),
    );
  }

  final native = _Native();
  final contextStore = CallSignalingContextStore();
  final startResults = <CallAudioStartStatus>[];
  final failureObservations = <String>[];
  final negotiationEvents = <String>[];
  final sentSignals = <CallSignal>[];
  late final FlutterWebRtcCallEngine engine;
  late final CallAudioController audio;
  late final CallNegotiationEffectExecutor executor;
  late final CallCoordinator coordinator;
  int _sequence = 0;

  CallId _nextMessageId() => CallId.parse(
    '33333333-3333-4333-8333-${(++_sequence).toString().padLeft(12, '0')}',
  );

  CallEvent _event(CallEventType type) => CallEvent(
    type: type,
    eventId: 'local-${type.name}-${_sequence++}',
    occurredAt: _now,
    callId: _callId,
    contactPeerId: _remoteAccount,
  );

  Future<void> accept(CallDirection direction) => switch (direction) {
    CallDirection.incoming => answerIncomingCall(),
    CallDirection.outgoing => placeCallAndGetAccepted(),
  };

  Future<void> hangUp() async {
    await coordinator.dispatch(_event(CallEventType.end));
  }

  Future<void> answerIncomingCall() async {
    contextStore.captureAuthenticated(
      signal: CallSignal.create(
        callId: _callId,
        messageId: _nextMessageId().value,
        event: CallSignalType.invite,
        senderAccountPeerId: _remoteAccount,
        senderDevicePeerId: _remoteDevice,
        recipientAccountPeerId: _localAccount,
        recipientDevicePeerId: _localDevice,
        senderSequence: 1,
        iceGeneration: 0,
        createdAtMs: _now.millisecondsSinceEpoch,
        expiresAtMs: _now
            .add(const Duration(seconds: 40))
            .millisecondsSinceEpoch,
      ),
      callHandle: _callHandle,
    );
    await coordinator.dispatch(
      CallEvent(
        type: CallEventType.remoteInvite,
        eventId: 'remote-invite',
        occurredAt: _now,
        callId: _callId,
        contactPeerId: _remoteAccount,
        localAccountPeerId: _localAccount,
        localDeviceId: _localDevice,
        remoteAccountPeerId: _remoteAccount,
        remoteDeviceId: _remoteDevice,
        expiresAt: _now.add(const Duration(seconds: 45)),
        transportRoute: CallRouteClass.direct,
      ),
    );
    await coordinator.dispatch(_event(CallEventType.incomingValidated));
    await coordinator.dispatch(_event(CallEventType.systemUiPresented));
    expect(coordinator.activeSession?.state, CallState.ringing);
    await coordinator.dispatch(_event(CallEventType.answer));
  }

  Future<void> placeCallAndGetAccepted() async {
    await coordinator.placeCall(
      contactPeerId: _remoteAccount,
      localAccountPeerId: _localAccount,
      localDeviceId: _localDevice,
    );
    await _settle();
    expect(coordinator.activeSession?.state, CallState.inviting);
    await coordinator.dispatch(_event(CallEventType.remoteRinging));
    await coordinator.dispatch(_event(CallEventType.remoteAccept));
  }

  Future<void> close() async {
    await coordinator.dispose();
    await executor.close();
    await audio.close();
  }
}

final class _Native
    implements WebRtcPeerConnectionAdapter, WebRtcLocalCandidateSource {
  final eventsController =
      StreamController<WebRtcPeerConnectionEvent>.broadcast(sync: true);
  final candidates = StreamController<CallIceCandidate>.broadcast(sync: true);

  @override
  bool isClosed = false;
  // Runs inside the native create, before it completes.
  void Function()? onCreate;
  @override
  Stream<WebRtcPeerConnectionEvent> get events => eventsController.stream;
  @override
  Stream<CallIceCandidate> get localCandidates => candidates.stream;
  @override
  Future<void> create(WebRtcPeerConnectionConfiguration configuration) async {
    onCreate?.call();
  }

  void emitClosed() => eventsController.add(
    const WebRtcPeerConnectionEvent(
      kind: WebRtcPeerConnectionEventKind.closed,
      connectionState: WebRtcConnectionState.closed,
      transport: WebRtcTransportClass.relay,
      quality: WebRtcQualityBand.unknown,
      failureReason: WebRtcFailureReason.none,
    ),
  );

  @override
  Future<CallSessionDescription>
  createOffer() async => const CallSessionDescription(
    type: CallSessionDescriptionType.offer,
    value:
        'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:0\r\n'
        'a=fingerprint:sha-256 00:01:02:03:04:05:06:07:08:09:0A:0B:0C:0D:0E:0F:'
        '10:11:12:13:14:15:16:17:18:19:1A:1B:1C:1D:1E:1F\r\na=sendrecv',
  );
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
  Future<WebRtcPeerConnectionSnapshot> snapshot() => throw UnimplementedError();

  @override
  Future<void> close() async {
    isClosed = true;
    await eventsController.close();
    await candidates.close();
  }
}

final class _Permission implements CallMicrophonePermission {
  _Permission(this.status, {this.beforeResult});
  final MicPermissionStatus status;
  // Runs while the permission request is in flight, before it answers.
  final void Function()? beforeResult;
  @override
  Future<MicPermissionStatus> request() async {
    beforeResult?.call();
    return status;
  }
}

final class _Conflicts
    implements CallMediaConflictPort, CallMediaConflictLease {
  @override
  Future<CallMediaConflictLease> acquireForCall() async => this;
  @override
  Future<void> release() async {}
}

final class _AudioSession implements CallForegroundAudioSession {
  @override
  bool ownsSession = false;
  @override
  Stream<CallAudioSessionInterruption> get interruptions =>
      const Stream<CallAudioSessionInterruption>.empty();
  @override
  Future<void> activate() async => ownsSession = true;
  @override
  Future<void> deactivate() async => ownsSession = false;
}

final class _NegotiationSignaling implements CallNegotiationSignalingPort {
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

final class _ControlPort implements CallControlSignalingPort {
  _ControlPort(this.sent);
  final List<CallSignal> sent;

  @override
  Future<OutgoingCallSignalingPreparation> prepareOutgoingInvite(
    CallSessionSnapshot snapshot,
  ) async => const OutgoingCallSignalingPreparation(
    callHandle: _callHandle,
    remoteAccountPeerId: _remoteAccount,
    remoteDevicePeerId: _remoteDevice,
  );

  @override
  Future<CallControlSendResult> send({
    required CallSignal signal,
    required String callHandle,
  }) async {
    sent.add(signal);
    return CallControlSendResult(
      directAccepted: true,
      mailboxStored: false,
      mailboxStoreSettled: Future<void>.value(),
      directRoute: CallRouteClass.direct,
    );
  }
}

final class _Timer implements CallTimerHandle {
  @override
  bool isActive = true;
  @override
  void cancel() => isActive = false;
}

final class _Timers implements CallTimerScheduler {
  @override
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback) =>
      _Timer();
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
