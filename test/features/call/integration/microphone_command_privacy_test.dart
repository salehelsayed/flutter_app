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
import 'package:flutter_app/features/call/data/call_history_repository_impl.dart';
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

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _now = DateTime.utc(2026, 10, 15, 23, 6, 30);
final _callId = CallId.parse('11111111-1111-4111-8111-111111111111');
const _callHandle = '22222222-2222-4222-8222-222222222222';
const _localAccount = 'local-account';
const _localDevice = 'local-device';
const _remoteAccount = 'remote-account';
const _remoteDevice = 'remote-device';

final class _Harness {
  _Harness({
    required Database database,
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
      audioSession: session,
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
      signaling: negotiationSignaling,
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
          await session.events.close();
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
      historyProjector: CallHistoryProjector(
        CallHistoryRepositoryImpl(database),
        clock: () => _now,
      ),
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
  final session = _AudioSession();
  final negotiationSignaling = _NegotiationSignaling();
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

  Future<void> hangUp() async {
    await coordinator.dispatch(_event(CallEventType.end));
  }

  Future<void> ring(CallDirection direction) async {
    if (direction == CallDirection.outgoing) {
      await coordinator.placeCall(
        contactPeerId: _remoteAccount,
        localAccountPeerId: _localAccount,
        localDeviceId: _localDevice,
      );
      await coordinator.dispatch(_event(CallEventType.remoteRinging));
      return;
    }
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
  }

  Future<void> answer(CallDirection direction) async {
    await coordinator.dispatch(
      _event(
        direction == CallDirection.incoming
            ? CallEventType.answer
            : CallEventType.remoteAccept,
      ),
    );
  }

  Future<void> close() async {
    await coordinator.dispose();
    await executor.close();
    await audio.close();
    await session.events.close();
  }
}

final class _Native
    implements WebRtcPeerConnectionAdapter, WebRtcLocalCandidateSource {
  final eventsController =
      StreamController<WebRtcPeerConnectionEvent>.broadcast(sync: true);
  final candidates = StreamController<CallIceCandidate>.broadcast(sync: true);

  @override
  bool isClosed = false;
  int createCalls = 0;
  final enabledWrites = <bool>[];
  bool enabled = false;
  // Runs inside the native create, before it completes.
  void Function()? onCreate;
  @override
  Stream<WebRtcPeerConnectionEvent> get events => eventsController.stream;
  @override
  Stream<CallIceCandidate> get localCandidates => candidates.stream;
  @override
  Future<void> create(WebRtcPeerConnectionConfiguration configuration) async {
    createCalls++;
    enabled = configuration.captureAudio;
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
  Future<void> setLocalAudioEnabled(bool value) async {
    enabledWrites.add(value);
    enabled = value;
  }

  @override
  Future<WebRtcPeerConnectionSnapshot> snapshot() async =>
      WebRtcPeerConnectionSnapshot(
        isClosed: isClosed,
        iceTransportPolicy: WebRtcIceTransportPolicy.all,
        localAudioCaptureTrackCount: isClosed ? 0 : createCalls,
        localVideoCaptureTrackCount: 0,
        audioReceiveTransceiverCount: 1,
        videoTransceiverCount: 0,
        connectionState: WebRtcConnectionState.newConnection,
        transport: WebRtcTransportClass.unknown,
        localAudioEnabled: enabled,
      );

  @override
  Future<void> close() async {
    isClosed = true;
    enabled = false;
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
  final events = StreamController<CallAudioSessionInterruption>.broadcast(
    sync: true,
  );
  @override
  bool ownsSession = false;
  @override
  Stream<CallAudioSessionInterruption> get interruptions => events.stream;
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

Future<Database> _openDatabase() {
  sqfliteFfiInit();
  return databaseFactoryFfiNoIsolate.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: currentIdentityDatabaseVersion,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('VC-019 Dart microphone-command privacy; actual audio is device-only', () {
    for (final direction in CallDirection.values) {
      test(
        '${direction.name}: ringing issues no capture command; answer enables it; hangup fences later unmute',
        () async {
          final db = await _openDatabase();
          addTearDown(db.close);
          final h = _Harness(
            database: db,
            permission: MicPermissionStatus.granted,
            audioRoutePort: CallAudioRouteAdapter(
              enumerateOutputs: () async => [
                CallAudioOutputRoute.systemDefault,
              ],
              selectOutput: (_) async {},
              setSpeakerphone: null,
            ),
          );
          addTearDown(h.close);
          await h.ring(direction);
          await h.audio.setMuted(
            false,
          ); // A stale UI command cannot start audio.
          expect(h.native.createCalls, 0);
          expect(h.native.enabledWrites, isEmpty);
          expect(h.session.ownsSession, isFalse);
          final captureStates = <CallState?>[];
          h.native.onCreate = () =>
              captureStates.add(h.coordinator.activeSession?.state);
          await h.answer(direction);
          expect(captureStates, [CallState.accepted]);
          expect(h.native.createCalls, 1);
          expect(h.native.enabled, isTrue);
          await h
              .hangUp(); // Production terminal delivery + SQL + media cleanup.
          expect(h.native.isClosed, isTrue);
          expect(h.native.enabled, isFalse);
          expect(h.session.ownsSession, isFalse);
          await h.audio.setMuted(false);
          await h.audio.settle();
          expect(h.native.enabledWrites, isEmpty);
          expect(h.native.createCalls, 1);
          expect(
            (await CallHistoryRepositoryImpl(
              db,
            ).getByCallId(_callId))?.terminalReason,
            CallEndReason.localHangup,
          );
        },
      );

      test(
        '${direction.name}: mute remains applied through interruption and is restored after an unmute is reversed',
        () async {
          final db = await _openDatabase();
          addTearDown(db.close);
          final h = _Harness(
            database: db,
            permission: MicPermissionStatus.granted,
            audioRoutePort: CallAudioRouteAdapter(
              enumerateOutputs: () async => [
                CallAudioOutputRoute.systemDefault,
              ],
              selectOutput: (_) async {},
              setSpeakerphone: null,
            ),
          );
          addTearDown(h.close);
          await h.ring(direction);
          await h.answer(direction);
          await h.audio.setMuted(true);
          expect(h.native.enabledWrites, [false]);
          expect(h.audio.state.muted, isTrue);
          h.session.events.add(const CallAudioSessionInterruption.begin());
          await h.audio.settle();
          h.session.events.add(const CallAudioSessionInterruption.end());
          await h.audio.settle();
          expect(h.native.enabledWrites, [false]);
          expect(h.native.enabled, isFalse);
          expect(h.audio.state.muted, isTrue);
          final unmute = h.audio.setMuted(false);
          final remute = h.audio.setMuted(true);
          await Future.wait([unmute, remute]);
          await h.audio.settle();
          expect(h.native.enabledWrites, [false, true, false]);
          expect(h.native.enabled, isFalse);
          expect(h.audio.state.muted, isTrue);
          expect(h.native.createCalls, 1);
          await h.hangUp();
          expect(h.native.isClosed, isTrue);
          expect(h.coordinator.terminalCleanupAckReady(_callId), isTrue);
        },
      );
    }
  });
}
