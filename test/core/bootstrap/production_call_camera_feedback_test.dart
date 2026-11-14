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
  static final now = DateTime.fromMillisecondsSinceEpoch(10000, isUtc: true);

  static Future<_CameraRig> create({
    Future<permissions.PermissionStatus> Function()? permission,
    bool nativeRefusal = false,
  }) async {
    final rig = _CameraRig();
    addTearDown(rig.engine.close);
    await rig._start(
      permission ?? () async => permissions.PermissionStatus.granted,
      nativeRefusal,
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
  ) async {
    engine.mediaReady = true;
    coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(const []),
      historyProjector: CallHistoryProjector(_UnusedCallHistoryRepository()),
      clock: () => now,
      idSource: () => _call,
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
      readStagedIceServers: (_) async => <CallIceServer>[],
      clock: () => now,
      dispatchEvent: (event) async {
        await coordinator.dispatch(event);
        if (event.type == CallEventType.remoteAnswer) {
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
    final native = nativeRefusal
        ? AndroidCallLifecycleAdapter(
            videoEnabled: true,
            invokeMethod: (method, arguments) async => true,
            nativeEvents: const Stream<Object?>.empty(),
            coordinator: coordinator,
            resolveAuthenticatedHandle: (_) => _handle,
            clock: () => now,
          )
        : null;
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
        publishNativeContact:
            ({required wakeHandle, required displayName}) async {},
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
    'ice_generation': 0,
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
        'purpose': 'initial',
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
  @override
  Stream<CallEngineEvent> get events => _events.stream;
  @override
  Stream<CallIceCandidate> get localCandidates => _candidates.stream;
  @override
  List<CallEngineEvent> get recentEvents => const [];
  @override
  bool get isClosed => closed;
  @override
  int get iceGeneration => 0;
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

final class _Video implements CallVideoSession {
  int cameraStarts = 0;
  bool cameraAccepted = true;
  Future<bool> Function()? cameraResult;
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
  Future<void> commit(CallVideoNegotiation token) async {}
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
