import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_audio_interruption_coordinator.dart';
import 'package:flutter_app/features/call/application/call_audio_negotiation_preparer.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_control_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_negotiation_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_negotiation_material_store.dart';
import 'package:flutter_app/features/call/application/call_scoped_media_bundle_owner.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/call_audio_route_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_foreground_audio_session_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_media_conflict_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/call_microphone_permission_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/bridge_call_ice_server_provider.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_app/features/call/infrastructure/production_call_signaling_adapters.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:uuid/uuid.dart';

import 'android_foreground_webrtc_audio_probe.dart';
import 'android_foreground_webrtc_audio_evidence.dart';
import 'sims_runtime_protocol.dart';

/// Returns only a fixed enum-like reason and never exposes SDP, candidates,
/// addresses, device identifiers, or media counters.
String androidForegroundWebRtcMediaReadinessFailure(
  CallConnectionSnapshot? snapshot, {
  required bool permissionGranted,
}) {
  if (snapshot == null) return 'notCaptured';
  if (!permissionGranted) return 'permissionNotGranted';
  if (snapshot.localAudioCaptureTrackCount == 0) {
    return 'audioCaptureMissing';
  }
  if (snapshot.localAudioCaptureTrackCount > 1) {
    return 'audioCaptureMultiple';
  }
  if (snapshot.localVideoCaptureTrackCount != 0) return 'videoCapturePresent';
  if (snapshot.audioReceiveTransceiverCount == 0) {
    return 'audioReceiveMissing';
  }
  if (snapshot.audioReceiveTransceiverCount > 1) {
    return 'audioReceiveMultiple';
  }
  if (snapshot.videoTransceiverCount != 0) return 'videoTransceiverPresent';
  if (snapshot.state != CallConnectionState.connected) {
    return 'iceConnectionNotReady';
  }
  if (!snapshot.selectedPairSucceeded) return 'selectedPairNotSucceeded';
  if (!snapshot.selectedPairNominated) return 'selectedPairNotNominated';
  if (!snapshot.dtlsReady) return 'dtlsNotReady';
  if (!snapshot.audioSessionActive) return 'audioSessionInactive';
  if (!snapshot.localAudioSenderAttached) return 'localAudioSenderMissing';
  if (!snapshot.localAudioTrackLive) return 'localAudioTrackNotLive';
  if (!snapshot.remoteAudioReceiverAttached) {
    return 'remoteAudioReceiverMissing';
  }
  if (!snapshot.remoteAudioTrackLive) return 'remoteAudioTrackNotLive';
  return 'ready';
}

final class AndroidForegroundWebRtcTurnFixture {
  AndroidForegroundWebRtcTurnFixture({
    required this.mode,
    required List<String> urls,
    required this.username,
    required this.password,
    required this.expiresAtMs,
  }) : urls = List<String>.unmodifiable(urls);

  final AndroidForegroundWebRtcAudioRelayMode mode;
  final List<String> urls;
  final String username;
  final String password;
  final int expiresAtMs;

  @override
  String toString() => 'AndroidForegroundWebRtcTurnFixture(${mode.name})';
}

/// Test-only transport seam for the two-device canonical-call proof.
///
/// Implementations receive only the already encrypted secure envelope. They
/// must not be given SDP, ICE candidates, identities, or call state directly.
abstract interface class AndroidForegroundWebRtcCanonicalEnvelopeCarrier {
  Future<void> publishEnvelope(String envelopeJson);
}

/// A test-scoped endpoint composed from the same canonical call owners used by
/// production. The only proof-specific seams are transport, fixed identities,
/// an in-memory history repository, and authenticated in-memory crypto.
final class AndroidForegroundWebRtcCanonicalEndpoint {
  AndroidForegroundWebRtcCanonicalEndpoint._({
    required this.role,
    required this.coordinator,
    required CallScopedMediaBundleOwner mediaOwner,
    required HandleIncomingCallSignal incomingHandler,
    required CallSignalingContextStore signalingContextStore,
    required CallNegotiationMaterialStore negotiationMaterialStore,
    required _ProofCallHistoryRepository historyRepository,
    required _CanonicalProofTelemetry telemetry,
    required _TestScopedAuthenticatedCallEnvelopeCrypto crypto,
    required _ProofIdentity localIdentity,
    required _ProofIdentity remoteIdentity,
    required _BoundedProofClock clock,
  }) : _mediaOwner = mediaOwner,
       _incomingHandler = incomingHandler,
       _signalingContextStore = signalingContextStore,
       _negotiationMaterialStore = negotiationMaterialStore,
       _historyRepository = historyRepository,
       _telemetry = telemetry,
       _crypto = crypto,
       _localIdentity = localIdentity,
       _remoteIdentity = remoteIdentity,
       _clock = clock {
    _snapshotSubscription = coordinator.snapshots.listen(
      _telemetry.recordSnapshot,
    );
  }

  static Future<AndroidForegroundWebRtcCanonicalEndpoint> create({
    required String role,
    required AndroidForegroundWebRtcCanonicalEnvelopeCarrier carrier,
    AndroidForegroundWebRtcTurnFixture? turnFixture,
  }) async {
    final localIdentity = _identityForRole(role);
    final remoteIdentity = _identityForRole(_oppositeRole(role));
    final clock = _BoundedProofClock();
    final telemetry = _CanonicalProofTelemetry(role: role);
    final turnBridge = turnFixture == null
        ? null
        : _TestScopedTurnCredentialsBridge(turnFixture);
    telemetry.configureRelay(turnFixture: turnFixture, bridge: turnBridge);
    final crypto = _TestScopedAuthenticatedCallEnvelopeCrypto();
    final codec = SecureCallEnvelopeCodec(
      crypto: crypto,
      nowMs: () => clock.now().millisecondsSinceEpoch,
    );
    final signalingContextStore = CallSignalingContextStore();
    final negotiationMaterialStore = CallNegotiationMaterialStore();
    final historyRepository = _ProofCallHistoryRepository();
    final boundEffects = _ProofBoundCallEffectExecutor(telemetry);

    late final CallScopedMediaBundleOwner mediaOwner;
    final coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('call_media', (snapshot) async {
          await mediaOwner.closeCall(snapshot.callId!);
        }),
        CallCleanupStep('call_signaling_context', (snapshot) async {
          signalingContextStore.purge(snapshot.callId!);
        }),
        CallCleanupStep('call_negotiation_material', (snapshot) async {
          negotiationMaterialStore.purgeCall(snapshot.callId!);
        }),
        CallCleanupStep('proof_cleanup_counter', (snapshot) async {
          telemetry.recordCoordinatorCleanup(snapshot.callId!);
        }),
      ]),
      historyProjector: CallHistoryProjector(
        historyRepository,
        diagnosticsRouteAllowed: true,
        clock: clock.now,
      ),
      effectExecutor: boundEffects,
      clock: clock.now,
      idSource: _newProofCallId,
    );
    telemetry.bindCoordinator(coordinator);

    final directTransport = _ProofEnvelopeDirectTransport(
      carrier: carrier,
      expectedRecipientDevicePeerId: remoteIdentity.devicePeerId,
      telemetry: telemetry,
    );
    final signalingService = CallSignalingService(
      codec: codec,
      directTransport: directTransport,
      mailboxClient: const _AlwaysFailingProofCallMailbox(),
      coordinator: coordinator,
      networkEffectsAllowed: _allowProofNetworkEffects,
    );

    final endpointExpiresAtMs = clock
        .now()
        .add(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    Future<ResolvedCallEndpoint> resolveCurrentEndpoint(
      String remoteAccountPeerId,
    ) async {
      if (remoteAccountPeerId != remoteIdentity.accountPeerId) {
        throw const CallEndpointResolutionException(
          CallEndpointResolutionCode.mismatched,
        );
      }
      return ResolvedCallEndpoint(
        accountPeerId: remoteIdentity.accountPeerId,
        devicePeerId: remoteIdentity.devicePeerId,
        signingPublicKey: remoteIdentity.signingLabel,
        mlKemPublicKey: remoteIdentity.encryptionLabel,
        deviceKeyEpoch: 1,
        preferenceEpoch: 1,
        platform: CallEndpointPlatform.android,
        expiresAtMs: endpointExpiresAtMs,
        routingHandle: remoteIdentity.routingHandle,
        wakeHandle: remoteIdentity.wakeHandle,
      );
    }

    final productionControlAdapter = ProductionCallControlSignalingAdapter(
      signalingService: signalingService,
      contextStore: signalingContextStore,
      resolveCurrentEndpoint: resolveCurrentEndpoint,
      loadSenderSigningPrivateKey: () async => localIdentity.signingLabel,
      clock: clock.now,
    );
    final observingControlAdapter = _ObservingCallControlSignalingPort(
      delegate: productionControlAdapter,
      telemetry: telemetry,
    );
    final controlExecutor = CallControlEffectExecutor(
      contextStore: signalingContextStore,
      signalingPort: observingControlAdapter,
      clock: clock.now,
      idSource: _newProofCallId,
    );

    final productionNegotiationAdapter =
        ProductionCallNegotiationSignalingAdapter(
          signalingService: signalingService,
          contextStore: signalingContextStore,
          resolveCurrentEndpoint: resolveCurrentEndpoint,
          loadSenderSigningPrivateKey: () async => localIdentity.signingLabel,
          clock: clock.now,
          messageIdSource: _newProofCallId,
        );
    final observingNegotiationAdapter = _ObservingCallNegotiationSignalingPort(
      delegate: productionNegotiationAdapter,
      telemetry: telemetry,
    );

    mediaOwner = CallScopedMediaBundleOwner(
      createBundle: (callId) async {
        telemetry.assertReducerAccepted('media_bundle_create');
        telemetry.recordBundleCreation(callId);

        final turnProvider = turnBridge == null
            ? null
            : BridgeCallIceServerProvider(bridge: turnBridge);

        final routeAdapter = CallAudioRouteAdapter.flutterWebRtc();
        final probe = AndroidForegroundWebRtcAudioProbeAdapter();
        final nativeEngine = FlutterWebRtcCallEngine(
          adapter: probe,
          audioRoutePort: routeAdapter,
          eventBufferCapacity: 32,
        );
        final engine = _ProofDiagnosticCallEngine(
          delegate: nativeEngine,
          telemetry: telemetry,
        );
        final microphonePermission = _ObservingCallMicrophonePermission(
          delegate: const CallMicrophonePermissionAdapter(),
          telemetry: telemetry,
        );
        final audioSession = await CallForegroundAudioSessionAdapter.create();
        final audioController = CallAudioController(
          engine: engine,
          microphonePermission: microphonePermission,
          mediaConflicts: CallMediaConflictAdapter(
            isVoiceNoteRecording: _noVoiceNoteRecording,
          ),
          audioSession: audioSession,
        );
        final mediaPreparer = CallAudioNegotiationPreparer(
          isCurrentCall: (id) =>
              id == callId &&
              !engine.isClosed &&
              coordinator.activeSession?.callId == callId &&
              coordinator.activeSession?.isTerminal == false,
          startAudio:
              ({
                required bool locallyAccepted,
                required CallConnectionConfiguration configuration,
              }) {
                telemetry.assertReducerAccepted('media_start');
                telemetry.recordMediaStart(configuration);
                return audioController.start(
                  locallyAccepted: locallyAccepted,
                  configuration: configuration,
                );
              },
          clock: clock.now,
          readInitialIceServers: turnProvider?.read,
        );
        final negotiationExecutor = CallNegotiationEffectExecutor(
          engine: engine,
          materialStore: negotiationMaterialStore,
          mediaPreparer: mediaPreparer,
          signaling: observingNegotiationAdapter,
          configuration: CallConnectionConfiguration(
            transportPolicy: turnFixture == null
                ? CallTransportPolicy.all
                : CallTransportPolicy.relayOnly,
            receiveAudio: true,
            receiveVideo: false,
            captureAudio: true,
            captureVideo: false,
            iceServers: <CallIceServer>[],
          ),
          dispatchEvent: (event) async {
            final reduction = await coordinator.dispatch(event);
            telemetry.recordNegotiationDispatch(event, reduction);
          },
          readActiveSnapshot: () => coordinator.activeSession,
          readStagedIceServers:
              turnProvider?.read ?? (_) async => const <CallIceServer>[],
          clock: clock.now,
        );
        final interruptionCoordinator = CallAudioInterruptionCoordinator(
          intents: audioController.interruptionIntents,
          readActiveSession: () => coordinator.activeSession,
          readMediaSnapshot: engine.snapshot,
          dispatchEvent: (event) async {
            final reduction = await coordinator.dispatch(event);
            telemetry.recordInterruptionDispatch(event, reduction);
          },
          clock: clock.now,
        );

        telemetry.installMediaBundle(
          callId: callId,
          probe: probe,
          engine: nativeEngine,
          audioController: audioController,
          audioSession: audioSession,
        );
        return CallScopedMediaBundle(
          callId: callId,
          engine: engine,
          audioController: audioController,
          negotiationExecutor: negotiationExecutor,
          close: () {
            turnProvider?.close();
            return _closeProofMediaBundle(
              callId: callId,
              telemetry: telemetry,
              interruptionCoordinator: interruptionCoordinator,
              audioController: audioController,
              negotiationExecutor: negotiationExecutor,
            );
          },
        );
      },
    );
    boundEffects.bind(
      CompositeCallEffectExecutor(
        controlExecutor: controlExecutor,
        negotiationExecutor: mediaOwner,
      ),
    );

    final incomingHandler = HandleIncomingCallSignal(
      codec: codec,
      coordinator: coordinator,
      trustedRosterProvider: _ProofTrustedCallRosterProvider(remoteIdentity),
      localAuthorityProvider: () async => CallLocalDeviceAuthority(
        accountPeerId: localIdentity.accountPeerId,
        devicePeerId: localIdentity.devicePeerId,
        mlKemSecretKey: localIdentity.encryptionLabel,
      ),
      incomingCallPresenter: const _AcceptingProofIncomingCallPresenter(),
      networkEffectsAllowed: _allowProofNetworkEffects,
      negotiationMaterialStore: negotiationMaterialStore,
      signalingContextObserver: signalingContextStore,
    );

    return AndroidForegroundWebRtcCanonicalEndpoint._(
      role: role,
      coordinator: coordinator,
      mediaOwner: mediaOwner,
      incomingHandler: incomingHandler,
      signalingContextStore: signalingContextStore,
      negotiationMaterialStore: negotiationMaterialStore,
      historyRepository: historyRepository,
      telemetry: telemetry,
      crypto: crypto,
      localIdentity: localIdentity,
      remoteIdentity: remoteIdentity,
      clock: clock,
    );
  }

  final String role;

  final CallCoordinator coordinator;
  final CallScopedMediaBundleOwner _mediaOwner;
  final HandleIncomingCallSignal _incomingHandler;
  final CallSignalingContextStore _signalingContextStore;
  final CallNegotiationMaterialStore _negotiationMaterialStore;
  final _ProofCallHistoryRepository _historyRepository;
  final _CanonicalProofTelemetry _telemetry;
  final _TestScopedAuthenticatedCallEnvelopeCrypto _crypto;
  final _ProofIdentity _localIdentity;
  final _ProofIdentity _remoteIdentity;
  final _BoundedProofClock _clock;

  late final StreamSubscription<CallSessionSnapshot> _snapshotSubscription;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  CallId? get callId =>
      coordinator.activeSession?.callId ?? coordinator.lastSnapshot?.callId;

  CallState? get state =>
      coordinator.activeSession?.state ?? coordinator.lastSnapshot?.state;

  bool hasSeenState(CallState state) => _telemetry.hasSeenState(state);

  CallAudioController get audioController {
    _requireConnectedProjection();
    return _telemetry.audioController ??
        (throw StateError('canonical audio controller is unavailable'));
  }

  AndroidForegroundWebRtcAudioProbeAdapter get probe {
    _requireConnectedProjection();
    return _telemetry.probe ??
        (throw StateError('canonical WebRTC probe is unavailable'));
  }

  bool get permissionGranted => _telemetry.permissionGranted;
  bool get audioOnly => _telemetry.audioOnly;
  bool get mediaReady => _telemetry.mediaReady;
  bool get directSelected => _telemetry.directSelected;
  AndroidForegroundWebRtcAudioRelayMode? get relayMode => _telemetry.relayMode;
  String get selectedTransport => _telemetry.selectedTransport;
  String get selectedRelayProtocol => _telemetry.selectedRelayProtocol;
  bool get expectedRelayTransportSelected =>
      _telemetry.expectedRelayTransportSelected;

  int get acceptToAudioMs {
    final snapshot = coordinator.activeSession ?? coordinator.lastSnapshot;
    final acceptedAt = snapshot?.acceptedAt;
    final connectedAt = snapshot?.connectedAt;
    if (acceptedAt == null || connectedAt == null) {
      throw StateError('canonical accept-to-audio latency is unavailable');
    }
    return connectedAt.difference(acceptedAt).inMilliseconds;
  }

  Map<String, Object?> get bridgeCredentialPath => <String, Object?>{
    'commandExact': _telemetry.turnCommandExact,
    'providerReadExactlyOnce': _telemetry.turnProviderReadExactlyOnce,
    'preparerRequiredTurn': _telemetry.preparerRequiredTurn,
    'modeBoundTransportOptions': _telemetry.freshTurnServerApplied,
  };

  Map<String, Object?> get relayPrivacy => <String, Object?>{
    'transportPolicyRelayOnly': _telemetry.relayPolicyApplied,
    'relayCandidateSignaled': _telemetry.relayCandidateSignaled,
    'trickleNonRelayCountZero': _telemetry.nonRelayCandidateSignalCount == 0,
    'embeddedSdpNonRelayCountZero':
        _telemetry.embeddedSdpNonRelayCandidateCount == 0,
  };

  /// Fixed-shape, privacy-safe context for a failed device-proof transition.
  ///
  /// This deliberately exposes only app-owned enum names. It never includes
  /// signaling bytes, candidate data, identities, routes, or credentials.
  Map<String, String> get terminalFailureContext {
    final snapshot = coordinator.activeSession ?? coordinator.lastSnapshot;
    final media = _telemetry.diagnosticMediaSnapshot;
    return <String, String>{
      'state': snapshot?.state.name ?? 'none',
      'endReason': snapshot?.endReason?.name ?? 'none',
      'effect': _telemetry.lastEffectType?.name ?? 'none',
      'followUp': _telemetry.lastFollowUpType?.name ?? 'none',
      'probeStage': _telemetry.probe?.diagnosticStage.name ?? 'none',
      'turnConfigStage': _telemetry.turnConfigStage,
      'descriptionCandidates':
          _telemetry.probe?.descriptionCandidateProfile.name ?? 'notCreated',
      'descriptionSecurity':
          _telemetry.probe?.descriptionSecurityProfile.name ?? 'notCreated',
      'engineError': _telemetry.firstEngineErrorCode?.name ?? 'none',
      'readinessFailure': _telemetry.readinessFailure,
      'selectedTransport': media?.transport.name ?? 'none',
      'selectedRelayProtocol': media?.selectedRelayProtocol.name ?? 'none',
    };
  }

  String get terminalDiagnostic {
    final context = terminalFailureContext;
    return 'state=${context['state']},'
        'endReason=${context['endReason']},'
        'effect=${context['effect']},'
        'followUp=${context['followUp']},'
        'probeStage=${context['probeStage']},'
        'turnConfigStage=${context['turnConfigStage']},'
        'descriptionCandidates=${context['descriptionCandidates']},'
        'descriptionSecurity=${context['descriptionSecurity']},'
        'engineError=${context['engineError']},'
        'readinessFailure=${context['readinessFailure']},'
        'selectedTransport=${context['selectedTransport']},'
        'selectedRelayProtocol=${context['selectedRelayProtocol']}';
  }

  Map<String, Object?> get connectedReadiness {
    final snapshot = _telemetry.connectedMediaSnapshot;
    return <String, Object?>{
      'selectedPairSucceeded': snapshot?.selectedPairSucceeded == true,
      'selectedPairNominated': snapshot?.selectedPairNominated == true,
      'iceConnected': snapshot?.state == CallConnectionState.connected,
      'dtlsReady': snapshot?.dtlsReady == true,
      'audioSessionActive': snapshot?.audioSessionActive == true,
      'localAudioSenderAttached': snapshot?.localAudioSenderAttached == true,
      'localAudioTrackLive': snapshot?.localAudioTrackLive == true,
      'remoteAudioReceiverAttached':
          snapshot?.remoteAudioReceiverAttached == true,
      'remoteAudioTrackLive': snapshot?.remoteAudioTrackLive == true,
    };
  }

  Future<IncomingCallSignalOutcome> handleEnvelope(String envelopeJson) async {
    _ensureOpen();
    final outcome = await _incomingHandler.handle(
      IncomingCallSignalFrame(
        envelopeJson: envelopeJson,
        authenticatedTransportPeerId: _remoteIdentity.devicePeerId,
        route: CallRouteClass.direct,
      ),
    );
    if (outcome == IncomingCallSignalOutcome.accepted) {
      _telemetry.recordAcceptedInboundEnvelope(envelopeJson);
    }
    return outcome;
  }

  Future<void> place() async {
    _ensureOpen();
    if (role != simsForegroundWebRtcCallerRole) {
      throw StateError('only the canonical caller may place the proof call');
    }
    final reduction = await coordinator.placeCall(
      contactPeerId: _remoteIdentity.accountPeerId,
      localAccountPeerId: _localIdentity.accountPeerId,
      localDeviceId: _localIdentity.devicePeerId,
    );
    if (reduction.decision != CallEventDecision.applied) {
      throw StateError('canonical place event was not applied');
    }
    _telemetry.placeDispatched = true;
  }

  void capturePreAcceptBoundary() {
    _ensureOpen();
    final snapshot = coordinator.activeSession;
    if (snapshot == null ||
        snapshot.acceptedAt != null ||
        (snapshot.state != CallState.preparing &&
            snapshot.state != CallState.inviting &&
            snapshot.state != CallState.incomingValidating &&
            snapshot.state != CallState.ringing)) {
      throw StateError('canonical pre-accept boundary is unavailable');
    }
    _telemetry.capturePreAcceptBoundary();
  }

  Future<void> answer() async {
    _ensureOpen();
    if (role != simsForegroundWebRtcCalleeRole) {
      throw StateError('only the canonical callee may answer the proof call');
    }
    final snapshot = coordinator.activeSession;
    if (snapshot == null || snapshot.state != CallState.ringing) {
      throw StateError('canonical incoming call is not ringing');
    }
    final reduction = await coordinator.dispatch(
      CallEvent(
        type: CallEventType.answer,
        eventId: 'proof-answer-${const Uuid().v4()}',
        occurredAt: _clock.now(),
        callId: snapshot.callId,
        contactPeerId: snapshot.contactPeerId,
      ),
    );
    if (reduction.decision != CallEventDecision.applied ||
        reduction.snapshot.acceptedAt == null) {
      throw StateError('canonical answer event was not applied');
    }
    _telemetry.answerDispatched = true;
  }

  Future<void> end() async {
    _ensureOpen();
    if (role != simsForegroundWebRtcCallerRole) {
      throw StateError('only the canonical caller may end the proof call');
    }
    final snapshot = coordinator.activeSession;
    if (snapshot == null || snapshot.state != CallState.connected) {
      throw StateError('canonical call is not connected');
    }
    final reduction = await coordinator.dispatch(
      CallEvent(
        type: CallEventType.end,
        eventId: 'proof-end-${const Uuid().v4()}',
        occurredAt: _clock.now(),
        callId: snapshot.callId,
        contactPeerId: snapshot.contactPeerId,
      ),
    );
    if (reduction.decision != CallEventDecision.applied ||
        reduction.snapshot.state != CallState.ended) {
      throw StateError('canonical end event was not applied');
    }
    _telemetry.endDispatched = true;
  }

  Future<void> captureConnectedReadiness() async {
    _ensureOpen();
    final snapshot = coordinator.activeSession;
    final engine = _telemetry.engine;
    if (snapshot == null ||
        snapshot.state != CallState.connected ||
        snapshot.connectedAt == null ||
        engine == null) {
      throw StateError('canonical reducer has not connected the call');
    }
    final media = await engine.snapshot();
    _telemetry.captureConnectedReadiness(media);
    final transportProven = relayMode == null
        ? directSelected
        : _telemetry.expectedRelayTransportSelected;
    if (!permissionGranted || !audioOnly || !mediaReady || !transportProven) {
      _telemetry.probe?.recordConnectedReadinessFailure();
      throw StateError('canonical connected media readiness is incomplete');
    }
  }

  Map<String, Object?> get canonicalJourney => <String, Object?>{
    'coordinatorDriven': _telemetry.coordinatorDriven,
    'placeInvite': _telemetry.placeInvite,
    'ringing': _telemetry.hasSeenState(CallState.ringing),
    'acceptApplied': _telemetry.acceptApplied,
    'encryptedSignaling': _telemetry.encryptedSignaling(_crypto),
    'noPreAcceptMedia': _telemetry.noPreAcceptMedia,
    'connectedByReducer': _telemetry.connectedByReducer,
    'canonicalEnd':
        _telemetry.hasSeenState(CallState.ended) &&
        cleanup.values.every((value) => value == true),
  };

  Map<String, Object?> get signalingTrace => <String, Object?>{
    'reducerPathSha256': _telemetry.reducerPathSha256,
    'outboundEnvelopeCount': _telemetry.outboundEnvelopeDigests.length,
    'inboundEnvelopeCount': _telemetry.inboundEnvelopeDigests.length,
    'outboundEnvelopeChainSha256': _envelopeChainSha256(
      _telemetry.outboundEnvelopeDigests,
    ),
    'inboundEnvelopeChainSha256': _envelopeChainSha256(
      _telemetry.inboundEnvelopeDigests,
    ),
    'outboundSignalCounts': _telemetry.outboundSignalCounts,
  };

  Map<String, Object?> get cleanup {
    final id = callId;
    return <String, Object?>{
      'connectionClosed': _telemetry.engine?.isClosed == true,
      'audioSessionReleased':
          _telemetry.audioSession != null &&
          !_telemetry.audioSession!.ownsSession,
      'bundleClosedExactlyOnce': _telemetry.bundleCloseCount == 1,
      'coordinatorCleanupExactlyOnce':
          id != null && _telemetry.cleanupCountFor(id) == 1,
      'historyProjectedExactlyOnce':
          id != null && _historyRepository.upsertCountFor(id) == 1,
      'signalingContextPurged':
          id != null && _signalingContextStore.read(id) == null,
      'negotiationMaterialPurged':
          id != null &&
          _negotiationMaterialStore.entryCountFor(id) == 0 &&
          _negotiationMaterialStore.callCount == 0,
    };
  }

  String callBindingSha256(String runId) {
    final id = callId;
    if (id == null || runId.trim().isEmpty || runId.length > 512) {
      throw ArgumentError('canonical call binding is unavailable');
    }
    return sha256.convert(utf8.encode('$runId:${id.value}')).toString();
  }

  Future<void> dispose() => _disposeFuture ??= _disposeOnce();

  Future<void> _disposeOnce() async {
    if (_disposed) return;
    Object? firstError;
    StackTrace? firstStack;

    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }

    await attempt(coordinator.dispose);
    await attempt(_mediaOwner.close);
    await attempt(_snapshotSubscription.cancel);
    _disposed = true;
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
  }

  void _requireConnectedProjection() {
    _ensureOpen();
    if (!_telemetry.hasSeenState(CallState.connected)) {
      throw StateError('canonical call has not connected');
    }
  }

  void _ensureOpen() {
    if (_disposed || _disposeFuture != null) {
      throw StateError('canonical proof endpoint is disposed');
    }
  }
}

final class _ProofBoundCallEffectExecutor implements CallEffectExecutor {
  _ProofBoundCallEffectExecutor(this._telemetry);

  final _CanonicalProofTelemetry _telemetry;
  CallEffectExecutor? _delegate;

  void bind(CallEffectExecutor delegate) {
    if (_delegate != null) throw StateError('canonical effects already bound');
    _delegate = delegate;
  }

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    final delegate = _delegate;
    if (delegate == null) {
      throw StateError('canonical effects are unavailable');
    }
    _telemetry.lastEffectType = effect.type;
    final followUp = await delegate.execute(effect, snapshot);
    _telemetry.lastFollowUpType = followUp?.type;
    return followUp;
  }
}

final class _ObservingCallControlSignalingPort
    implements CallControlSignalingPort {
  const _ObservingCallControlSignalingPort({
    required ProductionCallControlSignalingAdapter delegate,
    required _CanonicalProofTelemetry telemetry,
  }) : _delegate = delegate,
       _telemetry = telemetry;

  final ProductionCallControlSignalingAdapter _delegate;
  final _CanonicalProofTelemetry _telemetry;

  @override
  Future<OutgoingCallSignalingPreparation> prepareOutgoingInvite(
    CallSessionSnapshot snapshot,
  ) => _delegate.prepareOutgoingInvite(snapshot);

  @override
  Future<CallControlSendResult> send({
    required CallSignal signal,
    required String callHandle,
  }) async {
    final result = await _delegate.send(signal: signal, callHandle: callHandle);
    if (result.delivered) _telemetry.recordOutboundSignal(signal.event);
    return result;
  }
}

final class _ObservingCallNegotiationSignalingPort
    implements CallNegotiationSignalingPort {
  const _ObservingCallNegotiationSignalingPort({
    required ProductionCallNegotiationSignalingAdapter delegate,
    required _CanonicalProofTelemetry telemetry,
  }) : _delegate = delegate,
       _telemetry = telemetry;

  final ProductionCallNegotiationSignalingAdapter _delegate;
  final _CanonicalProofTelemetry _telemetry;

  @override
  Future<void> sendDescription({
    required CallId callId,
    required CallSessionDescription description,
    required int iceGeneration,
  }) async {
    _telemetry.assertReducerAccepted('negotiation_description_send');
    _telemetry.recordOutboundDescription(description);
    await _delegate.sendDescription(
      callId: callId,
      description: description,
      iceGeneration: iceGeneration,
    );
    _telemetry.recordOutboundSignal(
      description.type == CallSessionDescriptionType.offer
          ? CallSignalType.offer
          : CallSignalType.answer,
    );
  }

  @override
  Future<void> sendCandidates({
    required CallId callId,
    required List<CallIceCandidate> candidates,
  }) async {
    _telemetry.assertReducerAccepted('negotiation_candidate_send');
    _telemetry.recordOutboundCandidates(candidates);
    await _delegate.sendCandidates(callId: callId, candidates: candidates);
    for (var index = 0; index < candidates.length; index++) {
      _telemetry.recordOutboundSignal(CallSignalType.ice);
    }
  }

  @override
  Future<void> sendIceRestart({
    required CallId callId,
    required int iceGeneration,
  }) async {
    _telemetry.assertReducerAccepted('negotiation_restart_send');
    await _delegate.sendIceRestart(
      callId: callId,
      iceGeneration: iceGeneration,
    );
    _telemetry.recordOutboundSignal(CallSignalType.iceRestart);
  }
}

final class _ObservingCallMicrophonePermission
    implements CallMicrophonePermission {
  const _ObservingCallMicrophonePermission({
    required CallMicrophonePermission delegate,
    required _CanonicalProofTelemetry telemetry,
  }) : _delegate = delegate,
       _telemetry = telemetry;

  final CallMicrophonePermission _delegate;
  final _CanonicalProofTelemetry _telemetry;

  @override
  Future<MicPermissionStatus> request() async {
    _telemetry.assertReducerAccepted('microphone_permission_request');
    _telemetry.permissionRequestCount++;
    final status = await _delegate.request();
    _telemetry.lastPermissionStatus = status;
    return status;
  }
}

final class _ProofEnvelopeDirectTransport implements CallDirectTransport {
  const _ProofEnvelopeDirectTransport({
    required AndroidForegroundWebRtcCanonicalEnvelopeCarrier carrier,
    required String expectedRecipientDevicePeerId,
    required _CanonicalProofTelemetry telemetry,
  }) : _carrier = carrier,
       _expectedRecipientDevicePeerId = expectedRecipientDevicePeerId,
       _telemetry = telemetry;

  final AndroidForegroundWebRtcCanonicalEnvelopeCarrier _carrier;
  final String _expectedRecipientDevicePeerId;
  final _CanonicalProofTelemetry _telemetry;

  @override
  Future<CallDirectSendResult> send({
    required String recipientDevicePeerId,
    required String envelopeJson,
  }) async {
    if (recipientDevicePeerId != _expectedRecipientDevicePeerId) {
      return const CallDirectSendResult(
        outcome: CallDirectTransportOutcome.failed,
        transportAcknowledged: false,
        route: CallDirectRoute.unknown,
      );
    }
    await _carrier.publishEnvelope(envelopeJson);
    _telemetry.recordPublishedOutboundEnvelope(envelopeJson);
    return const CallDirectSendResult(
      outcome: CallDirectTransportOutcome.acceptedBytes,
      transportAcknowledged: true,
      route: CallDirectRoute.direct,
    );
  }
}

/// Test-only observer retaining only the first app-owned engine error enum.
/// Opaque descriptions, candidates, ICE servers, and exception text are never
/// copied into telemetry.
final class _ProofDiagnosticCallEngine
    implements CallEngine, CallAudioOutputRouteChangeSource {
  _ProofDiagnosticCallEngine({
    required FlutterWebRtcCallEngine delegate,
    required _CanonicalProofTelemetry telemetry,
  }) : _delegate = delegate,
       _telemetry = telemetry;

  final FlutterWebRtcCallEngine _delegate;
  final _CanonicalProofTelemetry _telemetry;

  @override
  Stream<CallEngineEvent> get events => _delegate.events;

  @override
  Stream<CallIceCandidate> get localCandidates => _delegate.localCandidates;

  @override
  Stream<CallAudioOutputRoute> get outputRouteChanges =>
      _delegate.outputRouteChanges;

  @override
  List<CallEngineEvent> get recentEvents => _delegate.recentEvents;

  @override
  bool get isClosed => _delegate.isClosed;

  @override
  int get iceGeneration => _delegate.iceGeneration;

  @override
  int get candidateBatchCapacity => _delegate.candidateBatchCapacity;

  @override
  Future<void> createConnection(CallConnectionConfiguration configuration) =>
      _observe(() => _delegate.createConnection(configuration));

  @override
  Future<CallSessionDescription> createOffer() =>
      _observe(_delegate.createOffer);

  @override
  Future<CallSessionDescription> createAnswer() =>
      _observe(_delegate.createAnswer);

  @override
  Future<void> setLocalDescription(CallSessionDescription description) =>
      _observeArgument(_delegate.setLocalDescription, description);

  @override
  Future<void> setRemoteDescription(CallSessionDescription description) =>
      _observeArgument(_delegate.setRemoteDescription, description);

  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) =>
      _observeArgument(_delegate.addIceCandidates, candidates);

  @override
  Future<int> restartIce({List<CallIceServer> iceServers = const []}) =>
      _observe(() => _delegate.restartIce(iceServers: iceServers));

  @override
  Future<void> setLocalAudioEnabled(bool enabled) =>
      _observe(() => _delegate.setLocalAudioEnabled(enabled));

  @override
  Future<void> setAudioSessionActive(bool active) =>
      _observe(() => _delegate.setAudioSessionActive(active));

  @override
  Future<List<CallAudioOutputRoute>> supportedOutputRoutes() =>
      _observe(_delegate.supportedOutputRoutes);

  @override
  Future<void> selectOutputRoute(CallAudioOutputRoute route) =>
      _observe(() => _delegate.selectOutputRoute(route));

  @override
  Future<CallConnectionSnapshot> snapshot() async {
    final snapshot = await _observe(_delegate.snapshot);
    _telemetry.recordMediaSnapshot(snapshot);
    return snapshot;
  }

  @override
  Future<void> close() => _observe(_delegate.close);

  Future<T> _observe<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on CallEngineException catch (error) {
      _telemetry.firstEngineErrorCode ??= error.code;
      rethrow;
    }
  }

  Future<T> _observeArgument<T, A>(
    Future<T> Function(A) operation,
    A argument,
  ) => _observe(() => operation(argument));
}

final class _AlwaysFailingProofCallMailbox implements CallMailboxClient {
  const _AlwaysFailingProofCallMailbox();

  Never _fail() =>
      throw const CallMailboxException(CallMailboxErrorCode.bridgeFailure);

  @override
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest request) =>
      _fail();

  @override
  Future<CallMailboxRetrieveResult> retrieve({
    String? callHandle,
    int limit = 64,
  }) => _fail();

  @override
  Future<int> ack({
    required String callHandle,
    required List<String> messageIds,
  }) => _fail();

  @override
  Future<bool> cancel({
    required String recipientDevicePeerId,
    required String callHandle,
  }) => _fail();
}

/// Test-scoped credential bridge exercising the default action-only decoder.
/// Raw fixture values are returned only to the in-memory provider and are never
/// included in diagnostics, evidence, or [toString].
final class _TestScopedTurnCredentialsBridge implements Bridge {
  _TestScopedTurnCredentialsBridge(this._fixture);

  final AndroidForegroundWebRtcTurnFixture _fixture;
  int acceptedRequestCount = 0;
  bool commandExact = false;

  @override
  bool get isInitialized => true;

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message);
    commandExact =
        decoded is Map &&
        decoded.length == 1 &&
        decoded['cmd'] == turnCredentialsV1BridgeCommand;
    if (!commandExact) throw const BridgeOperationUnavailableException();
    acceptedRequestCount++;
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final ttlSeconds = (_fixture.expiresAtMs - nowMs) ~/ 1000;
    if (ttlSeconds < 1 || ttlSeconds > 3600) {
      throw const BridgeOperationUnavailableException();
    }
    final serverTimeMs = _fixture.expiresAtMs - (ttlSeconds * 1000);
    return jsonEncode(<String, Object?>{
      'ok': true,
      'schema': 'turn_credentials',
      'version': 1,
      'urls': _fixture.urls,
      'username': _fixture.username,
      'password': _fixture.password,
      'ttlSeconds': ttlSeconds,
      'expiresAtMs': _fixture.expiresAtMs,
      'serverTimeMs': serverTimeMs,
    });
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  String toString() => '_TestScopedTurnCredentialsBridge(redacted)';
}

final class _ProofTrustedCallRosterProvider
    implements CallTrustedRosterProvider {
  const _ProofTrustedCallRosterProvider(this._remoteIdentity);

  final _ProofIdentity _remoteIdentity;

  TrustedCallDeviceAuthority get _authority => TrustedCallDeviceAuthority(
    accountPeerId: _remoteIdentity.accountPeerId,
    devicePeerId: _remoteIdentity.devicePeerId,
    linked: true,
    deviceKeyEpoch: 1,
    signingPublicKey: _remoteIdentity.signingLabel,
    mlKemPublicKey: _remoteIdentity.encryptionLabel,
  );

  @override
  Future<CallTrustedRosterSnapshot> loadForContact(
    String contactAccountPeerId,
  ) async => CallTrustedRosterSnapshot(
    contactAccountPeerId: contactAccountPeerId,
    contactAccepted: contactAccountPeerId == _remoteIdentity.accountPeerId,
    contactBlocked: false,
    devices: contactAccountPeerId == _remoteIdentity.accountPeerId
        ? <TrustedCallDeviceAuthority>[_authority]
        : const <TrustedCallDeviceAuthority>[],
  );

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String authenticatedTransportPeerId,
  ) async => authenticatedTransportPeerId == _remoteIdentity.devicePeerId
      ? _authority
      : null;
}

final class _AcceptingProofIncomingCallPresenter
    implements IncomingCallPresenter {
  const _AcceptingProofIncomingCallPresenter();

  @override
  Future<bool> present(IncomingCallPresentation presentation) async => true;

  @override
  Future<void> dismiss(IncomingCallPresentation presentation) async {}
}

/// Test-scoped authenticated encryption. It intentionally does not model
/// production ML-KEM/AES-GCM, but it does keep the real secure-envelope codec
/// boundary opaque: a random nonce drives an HMAC-derived XOR stream and an
/// HMAC tag authenticates the ciphertext before decryption.
final class _TestScopedAuthenticatedCallEnvelopeCrypto
    implements CallEnvelopeCrypto {
  static final String _scheme = base64Encode(
    utf8.encode('canonical-proof-hmac-stream-v1'),
  );

  final Random _random = Random.secure();
  int encryptCount = 0;
  int decryptCount = 0;
  int signCount = 0;
  int verifyCount = 0;

  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async {
    final nonce = List<int>.generate(16, (_) => _random.nextInt(256));
    final key = sha256.convert(utf8.encode(recipientMlKemPublicKey)).bytes;
    final plaintextBytes = utf8.encode(plaintext);
    final ciphertext = _xorWithDerivedStream(plaintextBytes, key, nonce);
    final tag = Hmac(sha256, key).convert(<int>[...nonce, ...ciphertext]).bytes;
    encryptCount++;
    return CallCiphertext(
      kem: _scheme,
      ciphertext: base64Encode(<int>[...ciphertext, ...tag]),
      nonce: base64Encode(nonce),
    );
  }

  @override
  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  }) async {
    try {
      if (ciphertext.kem != _scheme) {
        throw const FormatException('unsupported proof cipher');
      }
      final nonce = base64Decode(ciphertext.nonce);
      final authenticatedCiphertext = base64Decode(ciphertext.ciphertext);
      if (nonce.length != 16 || authenticatedCiphertext.length <= 32) {
        throw const FormatException('invalid proof ciphertext');
      }
      final encrypted = authenticatedCiphertext.sublist(
        0,
        authenticatedCiphertext.length - 32,
      );
      final suppliedTag = authenticatedCiphertext.sublist(
        authenticatedCiphertext.length - 32,
      );
      final key = sha256.convert(utf8.encode(ownMlKemSecretKey)).bytes;
      final expectedTag = Hmac(
        sha256,
        key,
      ).convert(<int>[...nonce, ...encrypted]).bytes;
      if (!_constantTimeEquals(suppliedTag, expectedTag)) {
        throw const FormatException('invalid proof authentication tag');
      }
      final plaintext = _xorWithDerivedStream(encrypted, key, nonce);
      decryptCount++;
      return utf8.decode(plaintext);
    } catch (_) {
      throw const CallEnvelopeException(CallEnvelopeErrorCode.decryptionFailed);
    }
  }

  @override
  Future<String> sign({
    required String senderSigningPrivateKey,
    required String canonicalData,
  }) async {
    signCount++;
    return base64Encode(
      Hmac(
        sha256,
        utf8.encode(senderSigningPrivateKey),
      ).convert(utf8.encode(canonicalData)).bytes,
    );
  }

  @override
  Future<bool> verify({
    required String senderSigningPublicKey,
    required String canonicalData,
    required String signature,
  }) async {
    try {
      final expected = Hmac(
        sha256,
        utf8.encode(senderSigningPublicKey),
      ).convert(utf8.encode(canonicalData)).bytes;
      final supplied = base64Decode(signature);
      final verified = _constantTimeEquals(supplied, expected);
      if (verified) verifyCount++;
      return verified;
    } catch (_) {
      return false;
    }
  }

  static List<int> _xorWithDerivedStream(
    List<int> input,
    List<int> key,
    List<int> nonce,
  ) {
    final output = List<int>.filled(input.length, 0);
    var offset = 0;
    var counter = 0;
    while (offset < input.length) {
      final block = Hmac(sha256, key).convert(<int>[
        ...nonce,
        (counter >> 24) & 0xff,
        (counter >> 16) & 0xff,
        (counter >> 8) & 0xff,
        counter & 0xff,
      ]).bytes;
      for (
        var index = 0;
        index < block.length && offset < input.length;
        index++, offset++
      ) {
        output[offset] = input[offset] ^ block[index];
      }
      counter++;
    }
    return output;
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}

final class _CanonicalProofTelemetry {
  _CanonicalProofTelemetry({required this.role});

  final String role;
  final List<CallState> _statePath = <CallState>[];
  final List<String> outboundEnvelopeDigests = <String>[];
  final List<String> inboundEnvelopeDigests = <String>[];
  final Map<CallSignalType, int> _signalCounts = <CallSignalType, int>{
    for (final type in CallSignalType.values) type: 0,
  };
  final Map<CallId, int> _coordinatorCleanupCounts = <CallId, int>{};

  CallCoordinator? _coordinator;
  CallId? _mediaCallId;
  AndroidForegroundWebRtcAudioProbeAdapter? probe;
  FlutterWebRtcCallEngine? engine;
  CallAudioController? audioController;
  CallForegroundAudioSessionAdapter? audioSession;
  MicPermissionStatus? lastPermissionStatus;
  CallConnectionSnapshot? connectedMediaSnapshot;
  CallConnectionSnapshot? latestMediaSnapshot;
  AndroidForegroundWebRtcAudioRelayMode? relayMode;
  _TestScopedTurnCredentialsBridge? turnBridge;

  int bundleCreationCount = 0;
  int bundleCloseCount = 0;
  int mediaStartCount = 0;
  int permissionRequestCount = 0;
  int acceptedInboundEnvelopeCount = 0;
  int engineReadinessConnectionCount = 0;
  int interruptionConnectionCount = 0;
  int preAcceptViolationCount = 0;
  int relayCandidateSignalCount = 0;
  int nonRelayCandidateSignalCount = 0;
  int embeddedSdpNonRelayCandidateCount = 0;
  CallEffectType? lastEffectType;
  CallEventType? lastFollowUpType;
  bool preAcceptBoundaryCaptured = false;
  bool placeDispatched = false;
  bool answerDispatched = false;
  bool endDispatched = false;
  bool relayPolicyApplied = false;
  bool freshTurnServerApplied = false;
  CallEngineErrorCode? firstEngineErrorCode;

  CallConnectionSnapshot? get diagnosticMediaSnapshot =>
      connectedMediaSnapshot ?? latestMediaSnapshot;

  String get readinessFailure {
    final snapshot = diagnosticMediaSnapshot;
    if (snapshot == null) return 'notCaptured';
    final mediaFailure = androidForegroundWebRtcMediaReadinessFailure(
      snapshot,
      permissionGranted: permissionGranted,
    );
    if (mediaFailure != 'ready') return mediaFailure;
    final transport = snapshot.transport;
    if (relayMode == null) {
      if (transport == CallTransportClass.direct) return 'ready';
      return transport == CallTransportClass.unknown
          ? 'transportUnknown'
          : 'transportMismatch';
    }
    if (expectedRelayTransportSelected) return 'ready';
    if (transport == CallTransportClass.unknown) return 'transportUnknown';
    if (selectedRelayProtocol == CallRelayProtocol.unknown.name ||
        selectedRelayProtocol == CallRelayProtocol.notRelay.name) {
      return 'relayProtocolUnknown';
    }
    return 'transportMismatch';
  }

  String get turnConfigStage {
    if (relayMode == null) return 'notRequested';
    final bridge = turnBridge;
    if (bridge == null ||
        !bridge.commandExact ||
        bridge.acceptedRequestCount != 1) {
      return 'fixtureBound';
    }
    if (mediaStartCount == 0) return 'bridgeAccepted';
    if (!relayPolicyApplied) return 'providerAccepted';
    if (!freshTurnServerApplied) return 'relayPolicyApplied';
    final stage = probe?.diagnosticStage;
    return switch (stage) {
      AndroidForegroundWebRtcAudioProbeStage.connectionReady ||
      AndroidForegroundWebRtcAudioProbeStage.samplingSnapshot ||
      AndroidForegroundWebRtcAudioProbeStage.snapshotSampled ||
      AndroidForegroundWebRtcAudioProbeStage.creatingOffer ||
      AndroidForegroundWebRtcAudioProbeStage.offerCreated ||
      AndroidForegroundWebRtcAudioProbeStage.creatingAnswer ||
      AndroidForegroundWebRtcAudioProbeStage.answerCreated ||
      AndroidForegroundWebRtcAudioProbeStage.applyingLocalDescription ||
      AndroidForegroundWebRtcAudioProbeStage.localDescriptionApplied ||
      AndroidForegroundWebRtcAudioProbeStage.applyingRemoteDescription ||
      AndroidForegroundWebRtcAudioProbeStage.remoteDescriptionApplied ||
      AndroidForegroundWebRtcAudioProbeStage.addingCandidates ||
      AndroidForegroundWebRtcAudioProbeStage.candidatesApplied =>
        'peerConnectionCreated',
      _ => 'turnServerApplied',
    };
  }

  void configureRelay({
    required AndroidForegroundWebRtcTurnFixture? turnFixture,
    required _TestScopedTurnCredentialsBridge? bridge,
  }) {
    relayMode = turnFixture?.mode;
    turnBridge = bridge;
  }

  void bindCoordinator(CallCoordinator coordinator) {
    if (_coordinator != null) throw StateError('coordinator already bound');
    _coordinator = coordinator;
  }

  void recordSnapshot(CallSessionSnapshot snapshot) {
    if (!_statePath.contains(snapshot.state)) _statePath.add(snapshot.state);
  }

  bool hasSeenState(CallState state) => _statePath.contains(state);

  void assertReducerAccepted(String operation) {
    final snapshot = _coordinator?.activeSession;
    final accepted =
        snapshot?.acceptedAt != null &&
        switch (snapshot!.state) {
          CallState.accepted ||
          CallState.negotiating ||
          CallState.connected ||
          CallState.reconnecting => true,
          _ => false,
        };
    if (!accepted) {
      preAcceptViolationCount++;
      throw StateError('$operation is outside reducer acceptance');
    }
  }

  void recordBundleCreation(CallId callId) {
    bundleCreationCount++;
    if (bundleCreationCount != 1 ||
        (_mediaCallId != null && _mediaCallId != callId)) {
      preAcceptViolationCount++;
      throw StateError('canonical media bundle cardinality was violated');
    }
    _mediaCallId = callId;
  }

  void installMediaBundle({
    required CallId callId,
    required AndroidForegroundWebRtcAudioProbeAdapter probe,
    required FlutterWebRtcCallEngine engine,
    required CallAudioController audioController,
    required CallForegroundAudioSessionAdapter audioSession,
  }) {
    if (_mediaCallId != callId || this.engine != null) {
      throw StateError('canonical media bundle installation was invalid');
    }
    this.probe = probe;
    this.engine = engine;
    this.audioController = audioController;
    this.audioSession = audioSession;
  }

  void recordMediaStart(CallConnectionConfiguration configuration) {
    mediaStartCount++;
    final mode = relayMode;
    if (mode == null) return;
    relayPolicyApplied =
        configuration.transportPolicy == CallTransportPolicy.relayOnly;
    final servers = configuration.iceServers;
    freshTurnServerApplied =
        servers.length == 1 &&
        servers.single.expiresAt.isAfter(DateTime.now().toUtc()) &&
        _turnUrlsMatchMode(servers.single.urls, mode);
  }

  void recordOutboundCandidates(List<CallIceCandidate> candidates) {
    for (final candidate in candidates) {
      if (_candidateIsRelay(candidate.value)) {
        relayCandidateSignalCount++;
      } else {
        nonRelayCandidateSignalCount++;
      }
    }
  }

  void recordOutboundDescription(CallSessionDescription description) {
    for (final rawLine in description.value.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.startsWith('a=candidate:') && !_candidateIsRelay(line)) {
        embeddedSdpNonRelayCandidateCount++;
      }
    }
  }

  void recordPublishedOutboundEnvelope(String envelopeJson) {
    outboundEnvelopeDigests.add(_sha256String(envelopeJson));
  }

  void recordAcceptedInboundEnvelope(String envelopeJson) {
    inboundEnvelopeDigests.add(_sha256String(envelopeJson));
    acceptedInboundEnvelopeCount++;
  }

  void recordOutboundSignal(CallSignalType type) {
    _signalCounts[type] = _signalCounts[type]! + 1;
  }

  void recordCoordinatorCleanup(CallId callId) {
    _coordinatorCleanupCounts[callId] = cleanupCountFor(callId) + 1;
  }

  int cleanupCountFor(CallId callId) => _coordinatorCleanupCounts[callId] ?? 0;

  void recordNegotiationDispatch(CallEvent event, CallReduction reduction) {
    if (_isAppliedConnectionEvent(event, reduction)) {
      engineReadinessConnectionCount++;
    }
  }

  void recordInterruptionDispatch(CallEvent event, CallReduction reduction) {
    if (_isAppliedConnectionEvent(event, reduction)) {
      interruptionConnectionCount++;
    }
  }

  void capturePreAcceptBoundary() {
    final noNegotiationSignals =
        _signalCounts[CallSignalType.offer] == 0 &&
        _signalCounts[CallSignalType.answer] == 0 &&
        _signalCounts[CallSignalType.ice] == 0 &&
        _signalCounts[CallSignalType.iceRestart] == 0;
    final clean =
        bundleCreationCount == 0 &&
        mediaStartCount == 0 &&
        permissionRequestCount == 0 &&
        noNegotiationSignals &&
        preAcceptViolationCount == 0;
    if (!clean) {
      preAcceptViolationCount++;
      throw StateError('pre-accept media boundary was violated');
    }
    preAcceptBoundaryCaptured = true;
  }

  void captureConnectedReadiness(CallConnectionSnapshot snapshot) {
    connectedMediaSnapshot = snapshot;
  }

  void recordMediaSnapshot(CallConnectionSnapshot snapshot) {
    latestMediaSnapshot = snapshot;
  }

  bool get permissionGranted =>
      permissionRequestCount == 1 &&
      lastPermissionStatus == MicPermissionStatus.granted;

  bool get audioOnly {
    return audioShapeFailure == 'ready';
  }

  String get audioShapeFailure {
    final snapshot = connectedMediaSnapshot;
    if (snapshot == null) return 'notCaptured';
    if (snapshot.localAudioCaptureTrackCount == 0) return 'audioCaptureMissing';
    if (snapshot.localAudioCaptureTrackCount > 1) {
      return 'audioCaptureMultiple';
    }
    if (snapshot.localVideoCaptureTrackCount != 0) {
      return 'videoCapturePresent';
    }
    if (snapshot.audioReceiveTransceiverCount == 0) {
      return 'audioReceiveMissing';
    }
    if (snapshot.audioReceiveTransceiverCount > 1) {
      return 'audioReceiveMultiple';
    }
    if (snapshot.videoTransceiverCount != 0) {
      return 'videoTransceiverPresent';
    }
    return 'ready';
  }

  bool get mediaReady => connectedMediaSnapshot?.isMediaReady == true;

  bool get directSelected =>
      connectedMediaSnapshot?.transport == CallTransportClass.direct;

  String get selectedTransport {
    final snapshot = connectedMediaSnapshot;
    if (snapshot == null) return 'unknown';
    return switch ((relayMode, snapshot.selectedRelayProtocol)) {
      (AndroidForegroundWebRtcAudioRelayMode.turnUdp, CallRelayProtocol.udp) =>
        CallTransportClass.turnUdp.name,
      (AndroidForegroundWebRtcAudioRelayMode.turnTcp, CallRelayProtocol.tcp) =>
        CallTransportClass.turnTcpTls.name,
      _ => snapshot.transport.name,
    };
  }

  String get selectedRelayProtocol =>
      connectedMediaSnapshot?.selectedRelayProtocol.name ?? 'unknown';

  bool get expectedRelayTransportSelected => switch (relayMode) {
    AndroidForegroundWebRtcAudioRelayMode.turnUdp =>
      connectedMediaSnapshot?.selectedRelayProtocol == CallRelayProtocol.udp,
    AndroidForegroundWebRtcAudioRelayMode.turnTcp =>
      connectedMediaSnapshot?.selectedRelayProtocol == CallRelayProtocol.tcp,
    null => false,
  };

  bool get turnCommandExact => turnBridge?.commandExact == true;

  bool get turnProviderReadExactlyOnce =>
      turnBridge?.acceptedRequestCount == 1 && freshTurnServerApplied;

  bool get preparerRequiredTurn => relayMode != null && freshTurnServerApplied;

  bool get relayCandidateSignaled => relayCandidateSignalCount > 0;

  bool get coordinatorDriven => role == simsForegroundWebRtcCallerRole
      ? placeDispatched
      : acceptedInboundEnvelopeCount > 0;

  bool get placeInvite => switch (role) {
    simsForegroundWebRtcCallerRole =>
      placeDispatched &&
          hasSeenState(CallState.preparing) &&
          hasSeenState(CallState.inviting),
    simsForegroundWebRtcCalleeRole =>
      acceptedInboundEnvelopeCount > 0 &&
          hasSeenState(CallState.incomingValidating),
    _ => false,
  };

  bool get acceptApplied =>
      hasSeenState(CallState.accepted) &&
      (_coordinator?.activeSession?.acceptedAt != null ||
          _coordinator?.lastSnapshot?.acceptedAt != null) &&
      (role == simsForegroundWebRtcCallerRole || answerDispatched);

  bool encryptedSignaling(_TestScopedAuthenticatedCallEnvelopeCrypto crypto) =>
      outboundEnvelopeDigests.isNotEmpty &&
      inboundEnvelopeDigests.isNotEmpty &&
      crypto.encryptCount > 0 &&
      crypto.decryptCount > 0 &&
      crypto.signCount > 0 &&
      crypto.verifyCount > 0;

  bool get noPreAcceptMedia =>
      preAcceptBoundaryCaptured && preAcceptViolationCount == 0;

  bool get connectedByReducer =>
      hasSeenState(CallState.connected) &&
      engineReadinessConnectionCount == 1 &&
      interruptionConnectionCount == 0 &&
      connectedMediaSnapshot?.isMediaReady == true;

  String get reducerPathSha256 => sha256
      .convert(
        utf8.encode(jsonEncode(_statePath.map((state) => state.name).toList())),
      )
      .toString();

  Map<String, Object?> get outboundSignalCounts => <String, Object?>{
    for (final type in CallSignalType.values)
      type.wireName: _signalCounts[type]!,
  };

  static bool _isAppliedConnectionEvent(
    CallEvent event,
    CallReduction reduction,
  ) =>
      (event.type == CallEventType.mediaConnected ||
          event.type == CallEventType.mediaRecovered) &&
      reduction.decision == CallEventDecision.applied &&
      reduction.snapshot.state == CallState.connected;
}

final class _ProofCallHistoryRepository implements CallHistoryRepository {
  final Map<CallId, CallHistoryEntry> _entries = <CallId, CallHistoryEntry>{};
  final Map<CallId, int> _upsertCounts = <CallId, int>{};

  int upsertCountFor(CallId callId) => _upsertCounts[callId] ?? 0;

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    final existing = _entries[entry.callId];
    if (existing != null) {
      throw StateError('proof history is insert-only');
    }
    _entries[entry.callId] = entry;
    _upsertCounts[entry.callId] = upsertCountFor(entry.callId) + 1;
  }

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async =>
      _entries[callId];

  @override
  Future<List<CallHistoryEntry>> listForContact(
    String contactAccountPeerId,
  ) async => _entries.values
      .where((entry) => entry.contactAccountPeerId == contactAccountPeerId)
      .toList(growable: false);
}

final class _ProofIdentity {
  const _ProofIdentity({
    required this.accountPeerId,
    required this.devicePeerId,
    required this.signingLabel,
    required this.encryptionLabel,
    required this.routingHandle,
    required this.wakeHandle,
  });

  final String accountPeerId;
  final String devicePeerId;

  // Public/private labels are deliberately equal only inside this proof so
  // HMAC can provide an authenticated test boundary without production keys.
  final String signingLabel;
  final String encryptionLabel;
  final String routingHandle;
  final String wakeHandle;
}

const _ProofIdentity _callerIdentity = _ProofIdentity(
  accountPeerId: 'canonical-proof-caller-account',
  devicePeerId: 'canonical-proof-caller-device',
  signingLabel: 'canonical-proof-caller-signing-key',
  encryptionLabel: 'canonical-proof-caller-envelope-key',
  routingHandle: '11111111111111111111111111111111',
  wakeHandle: '33333333333333333333333333333333',
);

const _ProofIdentity _calleeIdentity = _ProofIdentity(
  accountPeerId: 'canonical-proof-callee-account',
  devicePeerId: 'canonical-proof-callee-device',
  signingLabel: 'canonical-proof-callee-signing-key',
  encryptionLabel: 'canonical-proof-callee-envelope-key',
  routingHandle: '22222222222222222222222222222222',
  wakeHandle: '44444444444444444444444444444444',
);

final class _BoundedProofClock {
  _BoundedProofClock()
    : _anchor = DateTime.now().toUtc(),
      _stopwatch = Stopwatch()..start();

  static const Duration _maximumElapsed = Duration(minutes: 10);

  final DateTime _anchor;
  final Stopwatch _stopwatch;

  DateTime now() {
    final elapsed = _stopwatch.elapsed;
    return _anchor.add(elapsed > _maximumElapsed ? _maximumElapsed : elapsed);
  }
}

Future<void> _closeProofMediaBundle({
  required CallId callId,
  required _CanonicalProofTelemetry telemetry,
  required CallAudioInterruptionCoordinator interruptionCoordinator,
  required CallAudioController audioController,
  required CallNegotiationEffectExecutor negotiationExecutor,
}) async {
  if (telemetry._mediaCallId != callId) {
    throw StateError('canonical media cleanup call mismatch');
  }
  telemetry.bundleCloseCount++;
  Object? firstError;
  StackTrace? firstStack;

  Future<void> attempt(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStack ??= stackTrace;
    }
  }

  await attempt(interruptionCoordinator.close);
  await attempt(audioController.close);
  await attempt(negotiationExecutor.close);
  if (firstError != null) {
    Error.throwWithStackTrace(firstError!, firstStack!);
  }
}

_ProofIdentity _identityForRole(String role) => switch (role) {
  simsForegroundWebRtcCallerRole => _callerIdentity,
  simsForegroundWebRtcCalleeRole => _calleeIdentity,
  _ => throw ArgumentError.value(role, 'role', 'unsupported proof role'),
};

String _oppositeRole(String role) => switch (role) {
  simsForegroundWebRtcCallerRole => simsForegroundWebRtcCalleeRole,
  simsForegroundWebRtcCalleeRole => simsForegroundWebRtcCallerRole,
  _ => throw ArgumentError.value(role, 'role', 'unsupported proof role'),
};

CallId _newProofCallId() => CallId.parse(const Uuid().v4());

Future<bool> _allowProofNetworkEffects() async => true;

bool _noVoiceNoteRecording() => false;

bool _turnUrlMatchesMode(
  String value,
  AndroidForegroundWebRtcAudioRelayMode mode,
) {
  if (value.isEmpty ||
      value.length > 2048 ||
      value.trim() != value ||
      value.contains('@') ||
      RegExp(r'\s').hasMatch(value) ||
      !value.toLowerCase().startsWith('turn:')) {
    return false;
  }
  final expectedTransport = switch (mode) {
    AndroidForegroundWebRtcAudioRelayMode.turnUdp => 'transport=udp',
    AndroidForegroundWebRtcAudioRelayMode.turnTcp => 'transport=tcp',
  };
  return value.toLowerCase().endsWith('?$expectedTransport') &&
      value.substring('turn:'.length).split('?').first.isNotEmpty;
}

bool _turnUrlsMatchMode(
  List<String> values,
  AndroidForegroundWebRtcAudioRelayMode mode,
) {
  final expectedModes = switch (mode) {
    AndroidForegroundWebRtcAudioRelayMode.turnUdp =>
      const <AndroidForegroundWebRtcAudioRelayMode>[
        AndroidForegroundWebRtcAudioRelayMode.turnUdp,
      ],
    AndroidForegroundWebRtcAudioRelayMode.turnTcp =>
      const <AndroidForegroundWebRtcAudioRelayMode>[
        AndroidForegroundWebRtcAudioRelayMode.turnUdp,
        AndroidForegroundWebRtcAudioRelayMode.turnTcp,
      ],
  };
  if (values.length != expectedModes.length) return false;
  String? authority;
  for (var index = 0; index < values.length; index++) {
    final value = values[index];
    if (!_turnUrlMatchesMode(value, expectedModes[index])) return false;
    final currentAuthority = value.substring('turn:'.length).split('?').first;
    authority ??= currentAuthority;
    if (authority != currentAuthority) return false;
  }
  return true;
}

bool _candidateIsRelay(String candidate) {
  if (candidate.contains('\r') || candidate.contains('\n')) return false;
  var normalized = candidate.trim();
  if (normalized.length >= 2 &&
      normalized.substring(0, 2).toLowerCase() == 'a=') {
    normalized = normalized.substring(2);
  }
  final tokens = normalized.split(RegExp(r'\s+'));
  return tokens.length >= 8 &&
      tokens.first.toLowerCase().startsWith('candidate:') &&
      tokens[6].toLowerCase() == 'typ' &&
      tokens[7].toLowerCase() == 'relay';
}

String _sha256String(String value) =>
    sha256.convert(utf8.encode(value)).toString();

String _envelopeChainSha256(List<String> envelopeDigests) =>
    sha256.convert(utf8.encode(envelopeDigests.join(':'))).toString();
