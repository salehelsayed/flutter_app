import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:flutter_app/app/bootstrap/production_call_signaling_graph.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_negotiation_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_negotiation_material_store.dart';
import 'package:flutter_app/features/call/application/call_scoped_media_bundle_owner.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/features/call/application/call_v2_negotiation_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_wake_authorization_coordinator.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal_v2.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/android_call_lifecycle_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/call_signaling_runtime.dart';
import 'package:flutter_app/features/call/infrastructure/issued_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/call/infrastructure/received_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import '../secure_storage/fake_secure_key_store.dart';

final _call = CallId.parse('11111111-1111-4111-8111-111111111111');
const _handle = '22222222-2222-4222-8222-222222222222';
const _authority = (fingerprint: 'friend-authority', relationshipRevision: 1);
const _configuration = CallConnectionConfiguration(
  transportPolicy: CallTransportPolicy.relayOnly,
  receiveAudio: true,
  receiveVideo: false,
  captureAudio: true,
  captureVideo: false,
);

void main() {
  for (final (permission, failure) in [
    (
      permissions.PermissionStatus.denied,
      ForegroundCallCameraFailure.permissionDenied,
    ),
    (
      permissions.PermissionStatus.permanentlyDenied,
      ForegroundCallCameraFailure.permissionDenied,
    ),
    (
      permissions.PermissionStatus.restricted,
      ForegroundCallCameraFailure.permissionRestricted,
    ),
  ]) {
    test(
      'VUI4 graph $permission returns typed refusal without capture',
      () async {
        final rig = await _CameraRig.create(permission: () async => permission);
        final result = await rig.turnOn();
        expect(result.status, ForegroundCallActionStatus.unavailable);
        expect(result.cameraFailure, failure);
        expect(rig.permissionCalls, 1);
        expect(rig.engine.video.cameraStarts, 0);
      },
    );
  }
  test(
    'VUI4 graph granted permission captures only on explicit Camera intent',
    () async {
      final rig = await _CameraRig.create();
      expect(rig.permissionCalls, 0);
      expect(rig.engine.video.cameraStarts, 0);
      final result = await rig.turnOn();
      expect(result.status, ForegroundCallActionStatus.applied);
      expect(result.cameraFailure, isNull);
      expect(rig.permissionCalls, 1);
      expect(rig.engine.video.cameraStarts, 1);
    },
  );
  test(
    'VUI4 graph actual capture refusal is unavailable, not permission denied',
    () async {
      final rig = await _CameraRig.create();
      rig.engine.video.cameraAccepted = false;
      final result = await rig.turnOn();
      expect(rig.engine.video.cameraStarts, 1);
      expect(result.cameraFailure, ForegroundCallCameraFailure.unavailable);
    },
  );
  test('VUI4 graph native lease refusal never starts capture', () async {
    final rig = await _CameraRig.create(nativeRefusal: true);
    final result = await rig.turnOn();
    expect(rig.permissionCalls, 1);
    expect(result.cameraFailure, ForegroundCallCameraFailure.unavailable);
    expect(rig.engine.video.cameraStarts, 0);
  });
  test(
    'VUI4 graph denied permission after End is stale, not camera feedback',
    () async {
      final entered = Completer<void>();
      final permission = Completer<permissions.PermissionStatus>();
      final rig = await _CameraRig.create(
        permission: () {
          entered.complete();
          return permission.future;
        },
      );
      final operation = rig.turnOn();
      await entered.future.timeout(const Duration(seconds: 5));
      await rig.end();
      permission.complete(permissions.PermissionStatus.denied);
      final result = await operation;
      expect(result.status, ForegroundCallActionStatus.unavailable);
      expect(result.cameraFailure, isNull);
      expect(rig.engine.video.cameraStarts, 0);
    },
  );
  for (final throws in [false, true]) {
    for (final endDuringRelease in [false, true]) {
      test(
        'VUI4 graph capture throws=$throws End=$endDuringRelease during native release',
        () async {
          final entered = Completer<void>();
          final release = Completer<bool>();
          addTearDown(() {
            if (!release.isCompleted) release.complete(true);
          });
          final rig = await _CameraRig.create(
            releaseCamera: () {
              if (!entered.isCompleted) entered.complete();
              return release.future;
            },
          );
          rig.engine.video.cameraResult = () async {
            if (throws) throw StateError('Fixture capture rejected');
            return false;
          };
          var settled = false;
          final operation = rig.turnOn().then((result) {
            settled = true;
            return result;
          });
          try {
            await entered.future.timeout(const Duration(seconds: 5));
            expect(rig.nativeCameraCommands, [true, false]);
            expect(rig.engine.video.cameraStarts, 1);
            expect(settled, isFalse);
            if (endDuringRelease) await rig.end();
            expect(settled, isFalse);
            release.complete(true);
            final result = await operation.timeout(const Duration(seconds: 5));
            expect(
              result.status,
              !endDuringRelease && throws
                  ? ForegroundCallActionStatus.failed
                  : ForegroundCallActionStatus.unavailable,
            );
            expect(
              result.cameraFailure,
              endDuringRelease ? null : ForegroundCallCameraFailure.unavailable,
            );
            expect(rig.permissionCalls, 1);
            expect(rig.engine.video.cameraStarts, 1);
          } finally {
            if (!release.isCompleted) release.complete(true);
            await operation;
          }
        },
      );
    }
  }
  test('VUI4 graph late capture refusal after End is stale', () async {
    final rig = await _CameraRig.create();
    final entered = Completer<void>();
    final capture = Completer<bool>();
    rig.engine.video.cameraResult = () {
      entered.complete();
      return capture.future;
    };
    final operation = rig.turnOn();
    await entered.future.timeout(const Duration(seconds: 5));
    expect(rig.engine.video.cameraStarts, 1);
    await rig.end();
    capture.complete(false);
    final result = await operation;
    expect(result.status, ForegroundCallActionStatus.unavailable);
    expect(result.cameraFailure, isNull);
  });

  test(
    'BL26 camera ON survives two ICE-only recoveries without another tap',
    () async {
      final rig = await _CameraRig.create(recovery: true).timeout(_redDeadline);
      expect(
        (await rig.turnOn().timeout(_redDeadline)).status,
        ForegroundCallActionStatus.applied,
      );
      expect(
        rig.graph.current!.video!.presentation.localCamera,
        CallCameraState.on,
      );
      expect(rig.nativeCameraCommands, [true]);

      for (var episode = 1; episode <= 2; episode++) {
        await rig.recover().timeout(_redDeadline);
        expect(rig.engine.iceGeneration, episode);
      }

      expect(
        rig.graph.current!.video!.presentation.localCamera,
        CallCameraState.on,
        reason: 'ICE replacement must preserve an already-authorized camera',
      );
      expect(rig.nativeCameraCommands, [
        true,
      ], reason: 'A network handover is not an explicit camera OFF action');
      expect(rig.engine.video.cameraStarts, 1);
      expect(rig.permissionCalls, 1);
    },
  );

  test('BL26 camera OFF stays OFF through two ICE-only recoveries', () async {
    final rig = await _CameraRig.create(recovery: true).timeout(_redDeadline);
    for (var episode = 1; episode <= 2; episode++) {
      await rig.recover().timeout(_redDeadline);
    }
    expect(
      rig.graph.current!.video!.presentation.localCamera,
      CallCameraState.off,
    );
    expect(rig.nativeCameraCommands.where((active) => active), isEmpty);
    expect(rig.engine.video.cameraStarts, 0);
    expect(rig.permissionCalls, 0);
  });

  for (final boundary in ['background', 'end']) {
    test('BL26 $boundary during recovery commit cannot resurrect camera', () async {
      final rig = await _CameraRig.create(recovery: true).timeout(_redDeadline);
      expect(
        (await rig.turnOn().timeout(_redDeadline)).status,
        ForegroundCallActionStatus.applied,
      );
      expect(rig.nativeCameraCommands, [true]);
      final entered = Completer<void>();
      final commit = Completer<void>();
      addTearDown(() {
        if (!commit.isCompleted) commit.complete();
      });
      rig.engine.video.beforeCommit = () {
        if (!entered.isCompleted) entered.complete();
        return commit.future.timeout(_redDeadline);
      };
      final recovery = rig
          .recover(mayEnd: boundary == 'end')
          .timeout(_redDeadline);
      // Observe errors immediately while the test exercises the held boundary.
      final completed = recovery.then<Object?>(
        (_) => null,
        onError: (Object error, StackTrace _) => error,
      );
      await entered.future.timeout(_redDeadline);
      final boundaryWork =
          (boundary == 'background' ? rig.graph.onBackgrounded() : rig.end())
              .timeout(_redDeadline);
      final boundaryCompleted = boundaryWork.then<Object?>(
        (_) => null,
        onError: (Object error, StackTrace _) => error,
      );
      await _redTurn().timeout(_redDeadline);
      commit.complete();
      expect(await boundaryCompleted.timeout(_redDeadline), isNull);
      final error = await completed.timeout(_redDeadline);
      expect(error, isNull);
      await _redTurn().timeout(_redDeadline);
      expect(rig.nativeCameraCommands.last, isFalse);
      expect(rig.engine.video.cameraStarts, 1);
      expect(rig.permissionCalls, 1);
      final projection = rig.graph.current?.video;
      if (boundary == 'end') {
        expect(rig.coordinator.activeSession, isNull);
      }
      if (projection != null) {
        expect(projection.presentation.localCamera, isNot(CallCameraState.on));
      }
    });
  }
}

const _redDeadline = Duration(seconds: 2);

Future<void> _redTurn() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _RecoveryEffects implements CallEffectExecutor {
  _RecoveryEffects(this.run);
  final Future<CallEvent?> Function(CallEffect, CallSessionSnapshot) run;
  @override
  Future<CallEvent?> execute(CallEffect effect, CallSessionSnapshot snapshot) =>
      run(effect, snapshot);
}

// The real reducer, negotiation owner and graph run without network/native I/O.
// This dedicated fixture does not edit or import the frozen U2 composition suite.
final class _CameraRig {
  final engine = _Engine();
  final contexts = CallSignalingContextStore(videoEnabled: true);
  late final CallCoordinator coordinator;
  late final CallNegotiationEffectExecutor legacy;
  late final CallV2NegotiationEffectExecutor owner;
  late final ProductionCallSignalingGraph graph;
  int permissionCalls = 0;
  int sequence = 0;
  final nativeCameraCommands = <bool>[];
  bool _driveRecoveryEffects = false;
  static final now = DateTime.fromMillisecondsSinceEpoch(10000, isUtc: true);

  static Future<_CameraRig> create({
    Future<permissions.PermissionStatus> Function()? permission,
    bool nativeRefusal = false,
    Future<bool> Function()? releaseCamera,
    bool recovery = false,
  }) async {
    final rig = _CameraRig();
    addTearDown(rig.engine.close);
    await rig._start(
      permission ?? () async => permissions.PermissionStatus.granted,
      nativeRefusal,
      releaseCamera,
      recovery,
    );
    return rig;
  }

  Future<void> _event(CallEventType type) async {
    await coordinator.dispatch(
      CallEvent(
        type: type,
        eventId: 'camera-fixture-${++sequence}',
        occurredAt: now,
        callId: _call,
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
        remoteAccountPeerId: 'remote-account',
        remoteDeviceId: 'remote-device',
      ),
    );
  }

  Future<void> _start(
    Future<permissions.PermissionStatus> Function() permission,
    bool nativeRefusal,
    Future<bool> Function()? releaseCamera,
    bool recovery,
  ) async {
    engine.mediaReady = true;
    coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(const []),
      historyProjector: CallHistoryProjector(_UnusedCallHistoryRepository()),
      clock: () => now,
      idSource: () => _call,
      effectExecutor: _RecoveryEffects((effect, snapshot) async {
        if (!_driveRecoveryEffects) return null;
        return owner.execute(effect, snapshot);
      }),
      onTimerScheduled: (callId, kind, _, __, effectiveDelay) {
        if (_driveRecoveryEffects && kind == CallTimeoutKind.reconnect) {
          owner.observeReconnectTimer(
            coordinator.activeSession!,
            effectiveDelay,
          );
        }
      },
    );
    addTearDown(coordinator.dispose);
    final endpoint = _endpoint();
    final invite = _remote('invite').toMap()
      ..addAll({
        'sender_account_peer_id': 'local-account',
        'sender_device_peer_id': 'local-device',
        'recipient_account_peer_id': 'remote-account',
        'recipient_device_peer_id': 'remote-device',
      });
    contexts.storeOutgoingV2(
      invite: CallSignalV2.fromMap(invite, videoEnabled: true),
      callHandle: _handle,
      admissionAuthority: _authority,
      admittedEndpoint: endpoint,
    );
    contexts.captureAuthenticatedV2(
      signal: _remote('accept'),
      callHandle: _handle,
      admissionAuthority: _authority,
    );
    await _event(CallEventType.place);
    await _event(CallEventType.outgoingInviteReady);
    await _event(CallEventType.remoteAccept);
    expect(coordinator.activeSession?.state, CallState.accepted);
    legacy = CallNegotiationEffectExecutor(
      engine: engine,
      materialStore: CallNegotiationMaterialStore(),
      mediaPreparer: _Preparer(),
      signaling: _LegacySignaling(),
      configuration: _configuration,
      readActiveSnapshot: () => coordinator.activeSession,
      readStagedIceServers: (_) async => recovery
          ? [
              CallIceServer(
                urls: ['turn:relay.invalid:3478'],
                username: 'fixture',
                credential: 'fixture',
                expiresAt: now.add(const Duration(minutes: 5)),
              ),
            ]
          : <CallIceServer>[],
      clock: () => now,
      dispatchEvent: (event) async {
        await coordinator.dispatch(event);
        if (!_driveRecoveryEffects &&
            event.type == CallEventType.remoteAnswer) {
          await owner.execute(
            const CallEffect(CallEffectType.deliverAnswer),
            coordinator.activeSession!,
          );
        }
      },
    );
    addTearDown(legacy.close);
    owner = CallV2NegotiationEffectExecutor(
      callId: _call,
      legacy: legacy,
      videoEngine: engine,
      contexts: contexts,
      resolveEndpoint: (_) async => endpoint,
      sendSignal:
          ({
            required signal,
            required callHandle,
            required admittedEndpoint,
            required canApply,
          }) async => canApply(),
      canApply: () =>
          coordinator.activeSession?.callId == _call &&
          coordinator.activeSession?.isTerminal == false,
      idSource: () =>
          'aaaaaaaa-aaaa-4aaa-8aaa-${(++sequence).toRadixString(16).padLeft(12, '0')}',
      videoEnabled: true,
    );
    addTearDown(owner.close);
    final ready = await owner.execute(
      const CallEffect(CallEffectType.startNegotiation),
      coordinator.activeSession!,
    );
    expect(ready?.type, CallEventType.negotiationReady);
    await coordinator.dispatch(ready!);
    expect(
      owner.handleAuthenticated(
        signal: _remote(
          'answer',
          negotiation: owner.negotiation!.negotiationId,
        ),
        callHandle: _handle,
        canApply: () => true,
      ),
      IncomingCallSignalOutcome.accepted,
    );
    await owner.workSettled;
    await _event(CallEventType.mediaConnected);
    expect(coordinator.activeSession?.state, CallState.connected);
    expect(owner.current, isTrue);
    final mediaOwner = CallScopedMediaBundleOwner(
      createBundle: (_) => throw StateError('Unexpected audio bundle'),
    );
    final mailbox = _UnusedCallMailboxClient();
    final secureStore = FakeSecureKeyStore();
    final issued = IssuedCallWakeHandleStoreImpl(secureKeyStore: secureStore);
    final received = ReceivedCallWakeHandleStoreImpl(
      secureKeyStore: secureStore,
    );
    final nativeEvents = StreamController<Object?>.broadcast();
    addTearDown(nativeEvents.close);
    final native = nativeRefusal || releaseCamera != null || recovery
        ? AndroidCallLifecycleAdapter(
            videoEnabled: true,
            invokeMethod: (method, arguments) async {
              if (method == 'attach') {
                return <String, Object?>{
                  'version': 1,
                  'descriptor': <String, Object?>{
                    'callHandle': _handle,
                    'expiresAtMs': 55000,
                    'presented': true,
                    'phase': 'preStart',
                    'direction': 'outgoing',
                  },
                  'events': [
                    <String, Object?>{
                      'callHandle': _handle,
                      'sequence': 1,
                      'eventId': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
                      'type': 'presented',
                      'occurredAtMs': 10000,
                    },
                  ],
                  'nativeCallId': _handle,
                  'highestSequence': 1,
                };
              }
              if (method == 'setLocalCameraActive') {
                final active = arguments['active']! as bool;
                nativeCameraCommands.add(active);
                if (!active && releaseCamera != null) return releaseCamera();
              }
              return true;
            },
            nativeEvents: nativeEvents.stream,
            coordinator: coordinator,
            resolveAuthenticatedHandle: (_) => _handle,
            clock: () => now,
          )
        : null;
    if (native != null) addTearDown(native.close);
    if (releaseCamera != null || recovery) {
      await native!.start();
      expect(
        await native.registerOutgoing(
          _call,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(55000, isUtc: true),
        ),
        isTrue,
      );
      expect(native.debugBoundNativeHandle(_call), _handle);
    }
    graph = ProductionCallSignalingGraph(
      runtime: CallSignalingRuntime(
        directCallSignalStream: const Stream<ChatMessage>.empty(),
        mailboxClient: mailbox,
        handleIncoming: (_) async => IncomingCallSignalOutcome.rejected,
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      ),
      coordinator: coordinator,
      signalingService: CallSignalingService(
        codec: SecureCallEnvelopeCodec(
          crypto: _UnusedCallEnvelopeCrypto(),
          nowMs: () => 10000,
        ),
        directTransport: _UnusedCallDirectTransport(),
        mailboxClient: mailbox,
        coordinator: coordinator,
        networkEffectsAllowed: () => true,
      ),
      endpointResolver: CallEndpointResolver(
        nowMs: () => 10000,
        verifyEndpointSignature: (_, _) async => true,
      ),
      trustedRosterProvider: _UnusedCallTrustedRosterProvider(),
      authorityClient: _UnusedCallAuthorityClient(),
      wakeAuthorizationCoordinator: CallWakeAuthorizationCoordinator(
        store: issued,
        setWakeHandle: (_) async => true,
        revokeWakeHandle: ({required authorizedSenderPeerId}) async => true,
        publishNativeContact: ({
          required wakeHandle,
          required displayName,
        }) async {},
        revokeNativeContact: (_) async {},
        generateHandle: () => '0123456789abcdef0123456789abcdef',
        nowMs: () => 10000,
      ),
      issuedCallWakeHandleStore: issued,
      receivedCallWakeHandleStore: received,
      loadWakeEligibleContacts: () async => const <CallWakeEligibleContact>[],
      localDeviceKeyEpoch: 1,
      localIdentity: IdentityModel(
        peerId: 'local-account',
        publicKey: 'fixture-public',
        privateKey: 'fixture-private',
        mnemonic12: 'fixture only',
        mlKemPublicKey: 'fixture-kem',
        mlKemSecretKey: 'fixture-secret',
        createdAt: '2026-11-14T00:00:00Z',
        updatedAt: '2026-11-14T00:00:00Z',
      ),
      platform: CallEndpointPlatform.android,
      mediaOwner: mediaOwner,
      androidCallLifecycleAdapter: native,
      videoEnabled: true,
      videoContexts: contexts,
      videoOwners: {_call: owner},
      networkEffectsAllowed: () => true,
      nowMs: () => 10000,
      requestCameraPermissionStatus: () {
        permissionCalls++;
        return permission();
      },
    );
    addTearDown(graph.shutdown);
    final video = graph.current?.video;
    expect(video, isNotNull);
    expect(
      video!.presentation.intentFor(CallVideoAction.turnCameraOn),
      isNotNull,
    );
    _driveRecoveryEffects = recovery;
  }

  Future<void> recover({bool mayEnd = false}) async {
    engine.mediaReady = false;
    engine.video.onCommit = () => engine.mediaReady = true;
    await _event(CallEventType.mediaLost).timeout(_redDeadline);
    await owner.workSettled.timeout(_redDeadline);
    expect(coordinator.activeSession?.state, CallState.reconnecting);
    final token = owner.negotiation!;
    expect(
      owner.handleAuthenticated(
        signal: _remote(
          'answer',
          negotiation: token.negotiationId,
          generation: engine.iceGeneration,
          purpose: 'ice_restart',
        ),
        callHandle: _handle,
        canApply: () => true,
      ),
      IncomingCallSignalOutcome.accepted,
    );
    await owner.workSettled.timeout(_redDeadline);
    await _redTurn().timeout(_redDeadline);
    final session = coordinator.activeSession;
    if (session == null || session.isTerminal) {
      expect(mayEnd, isTrue);
    } else {
      expect(session.state, CallState.connected);
    }
  }

  Future<ForegroundCallActionResult> turnOn() {
    final video = graph.current!.video!;
    final intent = video.presentation.intentFor(CallVideoAction.turnCameraOn);
    expect(intent, isNotNull);
    return graph.applyVideoIntent(
      _call,
      generation: video.generation,
      intent: intent!,
    );
  }

  Future<void> end() => _event(CallEventType.end);

  CallSignalV2 _remote(
    String event, {
    String? negotiation,
    int generation = 0,
    String purpose = 'initial',
  }) => CallSignalV2.fromMap({
    'schema': CallSignalV2.schema,
    'call_id': _call.value,
    'message_id':
        'bbbbbbbb-bbbb-4bbb-8bbb-${(++sequence).toRadixString(16).padLeft(12, '0')}',
    'event': event,
    'sender_account_peer_id': 'remote-account',
    'sender_device_peer_id': 'remote-device',
    'recipient_account_peer_id': 'local-account',
    'recipient_device_peer_id': 'local-device',
    'sender_sequence': sequence,
    'ice_generation': generation,
    'created_at_ms': 10000,
    'expires_at_ms': 41000,
    'payload': switch (event) {
      'invite' => {
        'media': 'video',
        'camera': 'off',
        'capabilities': ['audio', 'video'],
      },
      'accept' => {'media': 'video', 'camera': 'off'},
      'answer' => {
        'negotiation_id': negotiation,
        'purpose': purpose,
        'switch_id': null,
        'media_revision': 0,
        'media': 'video',
        'description': 'opaque-sdp',
        'fingerprint': 'opaque-fingerprint',
      },
      _ => <String, Object?>{},
    },
  }, videoEnabled: true);
}

ResolvedCallEndpoint _endpoint({String signing = 'signing'}) =>
    ResolvedCallEndpoint(
      accountPeerId: 'remote-account',
      devicePeerId: 'remote-device',
      signingPublicKey: signing,
      mlKemPublicKey: 'kem',
      admissionAuthority: _authority,
      deviceKeyEpoch: 1,
      preferenceEpoch: 1,
      platform: CallEndpointPlatform.android,
      expiresAtMs: 100000,
      routingHandle: 'routing',
      wakeHandle: 'wake',
      capabilities: const {'voice_call_v1', 'video_call_v2'},
    );

final class _Preparer implements CallNegotiationMediaPreparer {
  int calls = 0;
  Object? error;
  @override
  Future<void> prepareLocallyAcceptedMedia({
    required CallSessionSnapshot snapshot,
    required CallConnectionConfiguration configuration,
  }) async {
    calls++;
    if (error != null) throw error!;
  }
}

final class _LegacySignaling implements CallNegotiationSignalingPort {
  int descriptions = 0;
  int candidateSends = 0;
  @override
  Future<void> sendDescription({
    required CallId callId,
    required CallSessionDescription description,
    required int iceGeneration,
  }) async {
    descriptions++;
  }

  @override
  Future<void> sendCandidates({
    required CallId callId,
    required List<CallIceCandidate> candidates,
  }) async {
    candidateSends++;
  }

  @override
  Future<void> sendIceRestart({
    required CallId callId,
    required int iceGeneration,
  }) async {}
}

final class _Engine implements CallEngine, CallVideoEngine {
  final video = _Video();
  final _events = StreamController<CallEngineEvent>.broadcast(sync: true);
  final _candidates = StreamController<CallIceCandidate>.broadcast(sync: true);
  bool mediaReady = false;
  bool closed = false;
  int generation = 0;
  @override
  Stream<CallEngineEvent> get events => _events.stream;
  @override
  Stream<CallIceCandidate> get localCandidates => _candidates.stream;
  @override
  List<CallEngineEvent> get recentEvents => const [];
  @override
  bool get isClosed => closed;
  @override
  int get iceGeneration => generation;
  @override
  Future<int> restartIce({List<CallIceServer> iceServers = const []}) async =>
      ++generation;
  @override
  int get candidateBatchCapacity => 8;
  @override
  CallVideoSession bindV2Video({
    required CallId callId,
    required bool localIsCaller,
    required CallWireVersion wireVersion,
    required bool Function() canApply,
    bool videoEnabled = false,
  }) {
    expect(callId, _call);
    expect(videoEnabled, isTrue);
    expect(wireVersion, CallWireVersion.v2);
    return video;
  }

  @override
  Future<CallConnectionSnapshot> snapshot() async => CallConnectionSnapshot(
    state: CallConnectionState.connected,
    transportPolicy: CallTransportPolicy.relayOnly,
    transport: CallTransportClass.relay,
    quality: CallQualityBand.good,
    localAudioCaptureTrackCount: 1,
    localVideoCaptureTrackCount: 0,
    audioReceiveTransceiverCount: 1,
    videoTransceiverCount: 1,
    selectedPairSucceeded: mediaReady,
    selectedPairNominated: mediaReady,
    dtlsReady: mediaReady,
    audioSessionActive: mediaReady,
    localAudioSenderAttached: mediaReady,
    localAudioTrackLive: mediaReady,
    remoteAudioReceiverAttached: mediaReady,
    remoteAudioTrackLive: mediaReady,
  );
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _events.close();
    await _candidates.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected engine operation ${invocation.memberName}');
}

final class _Token implements CallVideoNegotiation {
  _Token(this.negotiationId, this.mediaRevision, this.media);
  @override
  CallId get callId => _call;
  @override
  final String negotiationId;
  @override
  final int mediaRevision;
  @override
  final CallMediaKind media;
}

final class _Video implements CallVideoSession, CallVideoSdpReconciler {
  int cameraStarts = 0;
  bool cameraAccepted = true;
  Future<bool> Function()? cameraResult;
  Future<void> Function()? beforeCommit;
  void Function()? onCommit;
  @override
  CallId get callId => _call;
  @override
  bool get hasPendingCleanup => false;
  @override
  CallVideoNegotiation beginNegotiation({
    required String negotiationId,
    required int mediaRevision,
    required CallMediaKind media,
    required bool Function() canApply,
  }) => _Token(negotiationId, mediaRevision, media);
  @override
  Future<CallSessionDescription> createOffer(
    CallVideoNegotiation token,
  ) async => const CallSessionDescription(
    type: CallSessionDescriptionType.offer,
    value: 'opaque-sdp',
    fingerprint: 'opaque-fingerprint',
  );
  @override
  Future<CallSessionDescription> createAnswer(
    CallVideoNegotiation token,
  ) async => const CallSessionDescription(
    type: CallSessionDescriptionType.answer,
    value: 'opaque-sdp',
    fingerprint: 'opaque-fingerprint',
  );
  @override
  Future<void> applyLocal(
    CallVideoNegotiation token,
    CallSessionDescription description,
  ) async {}
  @override
  Future<void> applyRemote(
    CallVideoNegotiation token,
    CallSessionDescription description,
  ) async {}
  @override
  Future<void> commit(CallVideoNegotiation token) async {
    await beforeCommit?.call();
    onCommit?.call();
  }

  @override
  Future<CallVideoSdpReconciliationOutcome> reconcilePending(
    CallVideoNegotiation token, {
    required bool Function() canApply,
  }) async => canApply()
      ? CallVideoSdpReconciliationOutcome.alreadyStable
      : CallVideoSdpReconciliationOutcome.unreconciled;
  @override
  Future<bool> setLocalCamera(
    CallVideoNegotiation token,
    CallLocalCameraGrant grant,
  ) async {
    cameraStarts++;
    expect(grant.foregroundConsent, isTrue);
    expect(grant.permissionGranted, isTrue);
    return cameraResult?.call() ?? cameraAccepted;
  }

  @override
  Future<bool> retireVideo() async => true;
  @override
  Future<bool> stopLocalCamera() async => true;
  @override
  Future<bool> close() async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected video operation ${invocation.memberName}');
}

final class _UnusedCallHistoryRepository implements CallHistoryRepository {
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(
    String contactAccountPeerId,
  ) async => const <CallHistoryEntry>[];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {}
}

final class _UnusedCallMailboxClient implements CallMailboxClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedCallDirectTransport implements CallDirectTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedCallEnvelopeCrypto implements CallEnvelopeCrypto {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedCallTrustedRosterProvider
    implements CallTrustedRosterProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedCallAuthorityClient implements CallAuthorityClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
