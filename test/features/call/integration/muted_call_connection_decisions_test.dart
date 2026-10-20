import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
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
import 'package:flutter_app/features/call/data/call_history_repository_impl.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/call_audio_route_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_app/features/call/infrastructure/production_call_signaling_adapters.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_app/features/call/infrastructure/webrtc_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Host decisions only. Native WebRTC, foreground audio, roster/endpoint authority,
// transport and Go crypto are boundary fakes. No RTP packets or OS/audio proof.
final _now = DateTime.utc(2026, 10, 20, 8);
final _callId = CallId.parse('11111111-1111-4111-8111-111111111111');
final _handle = CallId.parse('22222222-2222-4222-8222-222222222222');
const _configuration = CallConnectionConfiguration(
  transportPolicy: CallTransportPolicy.all,
  receiveAudio: true,
  receiveVideo: false,
  captureAudio: true,
  captureVideo: false,
);
const _sdp =
    'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:0\r\n'
    'a=fingerprint:sha-256 00:01:02:03:04:05:06:07:08:09:0A:0B:0C:0D:0E:0F:'
    '10:11:12:13:14:15:16:17:18:19:1A:1B:1C:1D:1E:1F\r\na=sendrecv';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final previous = flowEventLoggingEnabled;
    flowEventLoggingEnabled = false;
    addTearDown(() => flowEventLoggingEnabled = previous);
  });
  for (final muteBeforeReady in [false, true]) {
    test(
      'VC-012 host two-peer mute preserves connected receive ownership (mute before ready=$muteBeforeReady)',
      () async {
        final pair = await _Pair.open();
        addTearDown(pair.close);
        await pair.negotiate();
        if (muteBeforeReady) await pair.muteBoth(true);
        await pair.connect();
        await pair.muteBoth(true);
        for (final endpoint in [pair.a, pair.b]) {
          final snapshot = await endpoint.engine.snapshot();
          expect(snapshot.isMediaReady, isTrue);
          expect(snapshot.localAudioEnabled, isFalse);
          expect(snapshot.remoteAudioReceiverAttached, isTrue);
          expect(snapshot.remoteAudioTrackLive, isTrue);
          expect(snapshot.audioSessionActive, isTrue);
          // Typed native reports survive mute; these fixture booleans are not packet evidence.
          expect(snapshot.inboundAudioRtpObserved, isTrue);
          expect(snapshot.outboundAudioRtpObserved, isTrue);
          expect(
            endpoint.coordinator.activeSession?.state,
            CallState.connected,
          );
          expect(endpoint.coordinator.activeSession?.callId, _callId);
          expect(endpoint.audio.state.muted, isTrue);
          expect(endpoint.native.createCalls, 1);
          expect(endpoint.native.closeCalls, 0);
          expect(endpoint.native.localDescriptions, hasLength(1));
          expect(endpoint.native.remoteDescriptions, hasLength(1));
        }
        final sends = pair.deliveries;
        await pair.muteBoth(false);
        await pair.muteBoth(true);
        for (final endpoint in [pair.a, pair.b]) {
          expect((await endpoint.engine.snapshot()).isMediaReady, isTrue);
          expect(
            endpoint.coordinator.activeSession?.state,
            CallState.connected,
          );
          expect(endpoint.coordinator.activeSession?.callId, _callId);
          expect(endpoint.native.createCalls, 1);
          expect(endpoint.native.closeCalls, 0);
        }
        expect(
          pair.deliveries,
          sends,
          reason: 'mute must not renegotiate or send a terminal',
        );
        await pair.hangup();
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }

  for (final missing in ['dtls', 'receiver']) {
    test(
      'VC-012 host mute cannot mask missing structural $missing readiness; RTP is a separate boundary',
      () async {
        final pair = await _Pair.open();
        addTearDown(pair.close);
        await pair.negotiate();
        await pair.muteBoth(true);
        pair.a.native.connected = true;
        pair.b.native.connected = true;
        pair.a.native.dtls = missing != 'dtls';
        pair.a.native.receiverLive = missing != 'receiver';
        final rejectedSample = pair.a.mediaTimers.nextScheduled();
        pair.a.native.emitConnected();
        await rejectedSample;
        expect(pair.a.coordinator.activeSession?.state, CallState.negotiating);
        expect((await pair.a.engine.snapshot()).isMediaReady, isFalse);
        expect(
          pair.a.events.where((e) => e == CallEventType.mediaConnected),
          isEmpty,
        );
        pair.a.native.dtls = true;
        pair.a.native.receiverLive = true;
        await pair.a.mediaTimers.fireNext();
        await pair.b.connectFromNative();
        for (final endpoint in [pair.a, pair.b]) {
          final snapshot = await endpoint.engine.snapshot();
          expect(
            endpoint.coordinator.activeSession?.state,
            CallState.connected,
          );
          expect(snapshot.isMediaReady, isTrue);
          expect(snapshot.localAudioEnabled, isFalse);
          // The shipped structural predicate deliberately ignores RTP and energy.
          expect(snapshot.inboundAudioRtpObserved, isFalse);
          expect(snapshot.outboundAudioRtpObserved, isFalse);
        }
        await pair.hangup();
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}

class _Pair {
  final queue = Queue<({String sender, String recipient, String envelope})>();
  late final _Endpoint a;
  late final _Endpoint b;
  var sequence = 0;
  var deliveries = 0;
  Completer<void>? _frameAvailable;
  void enqueue(({String sender, String recipient, String envelope}) frame) {
    queue.add(frame);
    _frameAvailable?.complete();
    _frameAvailable = null;
  }

  CallId nextId() => CallId.parse(
    '33333333-3333-4333-8333-${(++sequence).toString().padLeft(12, '0')}',
  );

  static Future<_Pair> open() async {
    sqfliteFfiInit();
    final pair = _Pair();
    final first = await _database();
    Database? second;
    try {
      second = await _database();
      pair.a = _Endpoint(pair, 'A', 'B', first);
      pair.b = _Endpoint(pair, 'B', 'A', second);
      return pair;
    } catch (_) {
      await second?.close();
      await first.close();
      rethrow;
    }
  }

  Future<void> flush() async {
    var count = 0;
    while (true) {
      if (queue.isEmpty) {
        final preparing =
            a.coordinator.hasPendingMediaPreparation ||
            b.coordinator.hasPendingMediaPreparation;
        if (!preparing ||
            (a.native.remoteDescriptions.isNotEmpty &&
                b.native.remoteDescriptions.isNotEmpty)) {
          break;
        }
        await (_frameAvailable ??= Completer<void>()).future;
      }
      expect(
        count++,
        lessThan(32),
        reason: 'canonical signaling must converge',
      );
      final frame = queue.removeFirst();
      final target = frame.recipient == a.device ? a : b;
      expect(frame.recipient, target.device);
      final outcome = await target.handler.handle(
        IncomingCallSignalFrame(
          envelopeJson: frame.envelope,
          authenticatedTransportPeerId: frame.sender,
          route: CallRouteClass.direct,
        ),
      );
      expect(outcome, IncomingCallSignalOutcome.accepted);
      deliveries++;
    }
  }

  Future<void> negotiate() async {
    await a.coordinator.placeCall(
      contactPeerId: b.account,
      localAccountPeerId: a.account,
      localDeviceId: a.device,
    );
    await flush();
    expect(a.coordinator.activeSession?.state, CallState.ringing);
    expect(b.coordinator.activeSession?.state, CallState.ringing);
    expect(a.native.createCalls, 0);
    expect(b.native.createCalls, 0);
    await b.coordinator.dispatch(b.event(CallEventType.answer));
    await flush();
    await a.waitForState(CallState.negotiating);
    await b.waitForState(CallState.negotiating);
    expect(a.coordinator.activeSession?.state, CallState.negotiating);
    expect(b.coordinator.activeSession?.state, CallState.negotiating);
    expect(a.native.localDescriptions.single, CallSessionDescriptionType.offer);
    expect(
      b.native.localDescriptions.single,
      CallSessionDescriptionType.answer,
    );
  }

  Future<void> muteBoth(bool muted) async {
    for (final endpoint in [a, b]) {
      await endpoint.audio.setMuted(muted);
      expect(endpoint.audio.state.muted, muted);
    }
  }

  Future<void> connect() async {
    for (final endpoint in [a, b]) {
      await endpoint.connectFromNative(rtp: true);
      expect(endpoint.coordinator.activeSession?.state, CallState.connected);
      expect(
        endpoint.events.where((e) => e == CallEventType.mediaConnected),
        hasLength(1),
      );
    }
  }

  Future<void> hangup() async {
    await a.coordinator.dispatch(a.event(CallEventType.end));
    await flush();
    for (final endpoint in [a, b]) {
      expect(endpoint.coordinator.activeSession, isNull);
      expect(endpoint.native.closeCalls, 1);
      expect(endpoint.native.enabled, isFalse);
      expect(endpoint.session.ownsSession, isFalse);
      expect(endpoint.coordinator.terminalCleanupAckReady(_callId), isTrue);
    }
    expect(
      (await CallHistoryRepositoryImpl(
        a.db,
      ).getByCallId(_callId))?.terminalReason,
      CallEndReason.localHangup,
    );
    expect(
      (await CallHistoryRepositoryImpl(
        b.db,
      ).getByCallId(_callId))?.terminalReason,
      CallEndReason.remoteHangup,
    );
  }

  Future<void> close() async {
    await a.close();
    await b.close();
  }
}

class _Endpoint {
  _Endpoint(this.pair, this.name, this.peer, this.db) {
    codec = SecureCallEnvelopeCodec(
      crypto: _NativeCrypto(),
      nowMs: () => _now.millisecondsSinceEpoch,
    );
    service = CallSignalingService(
      codec: codec,
      directTransport: _Direct(this),
      mailboxClient: _Mailbox(),
      networkEffectsAllowed: () => true,
      nowMs: () => _now.millisecondsSinceEpoch,
    );
    final controlPort = ProductionCallControlSignalingAdapter(
      signalingService: service,
      contextStore: context,
      resolveCurrentEndpoint: resolvePeer,
      loadSenderSigningPrivateKey: () async => 'signing-$name',
      callHandleSource: () => _handle,
      clock: () => _now,
    );
    engine = FlutterWebRtcCallEngine(
      adapter: native,
      audioRoutePort: CallAudioRouteAdapter(
        enumerateOutputs: () async => [CallAudioOutputRoute.systemDefault],
        selectOutput: (_) async {},
        setSpeakerphone: null,
      ),
    );
    audio = CallAudioController(
      engine: engine,
      microphonePermission: _Permission(),
      mediaConflicts: _Conflicts(),
      audioSession: session,
    );
    executor = CallNegotiationEffectExecutor(
      engine: engine,
      materialStore: material,
      mediaPreparer: CallAudioNegotiationPreparer(
        startAudio: audio.start,
        isCurrentCall: (id) =>
            coordinator.activeSession?.callId == id &&
            coordinator.activeSession?.isTerminal == false,
        readInitialIceServers: (_) async => const [],
        clock: () => _now,
      ),
      signaling: ProductionCallNegotiationSignalingAdapter(
        signalingService: service,
        contextStore: context,
        resolveCurrentEndpoint: resolvePeer,
        loadSenderSigningPrivateKey: () async => 'signing-$name',
        clock: () => _now,
        messageIdSource: pair.nextId,
      ),
      configuration: _configuration,
      dispatchEvent: (event) async {
        events.add(event.type);
        await coordinator.dispatch(event);
      },
      readActiveSnapshot: () => coordinator.activeSession,
      readStagedIceServers: (_) async => const [],
      clock: () => _now,
      mediaReadinessTimerScheduler: mediaTimers,
    );
    final mediaOwner = CallScopedMediaBundleOwner(
      createBundle: (_) => CallScopedMediaBundle(
        callId: _callId,
        engine: engine,
        audioController: audio,
        negotiationExecutor: executor,
        close: () async {
          await audio.close();
          await executor.close();
        },
      ),
    );
    final controls = CallControlEffectExecutor(
      contextStore: context,
      signalingPort: controlPort,
      clock: () => _now,
      idSource: pair.nextId,
    );
    coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator([
        CallCleanupStep(
          'call_media',
          (s) => mediaOwner.closeCall(s.callId!),
          requiredForTerminalAck: true,
        ),
        CallCleanupStep('call_context', (s) async {
          await controls.retireOutgoingPreconnectInvite(s);
          context.purge(s.callId!);
        }, requiredForTerminalAck: true),
      ]),
      historyProjector: CallHistoryProjector(
        CallHistoryRepositoryImpl(db),
        clock: () => _now,
      ),
      effectExecutor: CompositeCallEffectExecutor(
        controlExecutor: controls,
        negotiationExecutor: mediaOwner,
      ),
      clock: () => _now,
      idSource: () => _callId,
      timerScheduler: phaseTimers,
    );
    handler = HandleIncomingCallSignal(
      codec: codec,
      coordinator: coordinator,
      trustedRosterProvider: _Roster(peer),
      localAuthorityProvider: () async => CallLocalDeviceAuthority(
        accountPeerId: account,
        devicePeerId: device,
        mlKemSecretKey: 'secret-$name',
      ),
      incomingCallPresenter: _Presenter(),
      networkEffectsAllowed: () => true,
      negotiationMaterialStore: material,
      signalingContextObserver: context,
    );
  }
  final _Pair pair;
  final String name;
  final String peer;
  final Database db;
  String get account => 'account-$name';
  String get device => 'device-$name';
  final context = CallSignalingContextStore();
  final material = CallNegotiationMaterialStore();
  final native = _Native();
  final session = _Session();
  final mediaTimers = _ManualTimers();
  final phaseTimers = _ManualTimers();
  final events = <CallEventType>[];
  late final SecureCallEnvelopeCodec codec;
  late final CallSignalingService service;
  late final FlutterWebRtcCallEngine engine;
  late final CallAudioController audio;
  late final CallNegotiationEffectExecutor executor;
  late final CallCoordinator coordinator;
  late final HandleIncomingCallSignal handler;

  Future<ResolvedCallEndpoint> resolvePeer(String account) async {
    expect(account, 'account-$peer');
    return ResolvedCallEndpoint(
      accountPeerId: account,
      devicePeerId: 'device-$peer',
      signingPublicKey: 'signing-$peer',
      mlKemPublicKey: 'mlkem-$peer',
      deviceKeyEpoch: 1,
      preferenceEpoch: 1,
      platform: CallEndpointPlatform.android,
      expiresAtMs: _now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      routingHandle: '00000000000000000000000000000001',
      wakeHandle: '00000000000000000000000000000002',
    );
  }

  CallEvent event(CallEventType type) => CallEvent(
    type: type,
    eventId: pair.nextId().value,
    occurredAt: _now,
    callId: _callId,
    contactPeerId: 'account-$peer',
  );
  Future<void> waitForState(CallState state) async {
    if (coordinator.activeSession?.state == state) return;
    await coordinator.snapshots.firstWhere((s) => s.state == state);
  }

  Future<void> connectFromNative({bool rtp = false}) async {
    final connected = waitForState(CallState.connected);
    native.connected = true;
    native.rtpReports = rtp;
    native.emitConnected();
    await connected;
  }

  Future<void> close() async {
    await coordinator.dispose();
    await executor.close();
    await audio.close();
    service.close();
    await session.events.close();
    await db.close();
  }
}

class _Direct implements CallDirectTransport {
  _Direct(this.endpoint);
  final _Endpoint endpoint;
  @override
  Future<CallDirectSendResult> send({
    required String recipientDevicePeerId,
    required String envelopeJson,
  }) async {
    endpoint.pair.enqueue((
      sender: endpoint.device,
      recipient: recipientDevicePeerId,
      envelope: envelopeJson,
    ));
    return const CallDirectSendResult(
      outcome: CallDirectTransportOutcome.acceptedBytes,
      transportAcknowledged: true,
      route: CallDirectRoute.direct,
    );
  }
}

class _Mailbox implements CallMailboxClient {
  @override
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest r) async =>
      CallMailboxStoreResult(
        status: CallMailboxStoreStatus.stored,
        receiptAtMs: _now.millisecondsSinceEpoch,
        expiresAtMs: r.expiresAtMs,
        eventCount: 1,
        totalBytes: r.envelopeJson.length,
        pendingHandles: 1,
      );
  @override
  Future<bool> cancel({
    required String recipientDevicePeerId,
    required String callHandle,
  }) async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected mailbox operation ${invocation.memberName}',
  );
}

// Go crypto is outside this decision test. The production codec still processes
// canonical envelopes, identity bindings, expiry, sequence and replay custody.
class _NativeCrypto implements CallEnvelopeCrypto {
  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async => CallCiphertext(
    kem: base64Encode(utf8.encode('kem')),
    ciphertext: base64Encode(utf8.encode(plaintext)),
    nonce: base64Encode(utf8.encode('nonce')),
  );
  @override
  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  }) async => utf8.decode(base64Decode(ciphertext.ciphertext));
  @override
  Future<String> sign({
    required String senderSigningPrivateKey,
    required String canonicalData,
  }) async =>
      base64Encode(utf8.encode('$senderSigningPrivateKey:$canonicalData'));
  @override
  Future<bool> verify({
    required String senderSigningPublicKey,
    required String canonicalData,
    required String signature,
  }) async =>
      signature ==
      base64Encode(utf8.encode('$senderSigningPublicKey:$canonicalData'));
}

class _Roster implements CallTrustedRosterProvider {
  _Roster(this.name);
  final String name;
  TrustedCallDeviceAuthority get device => TrustedCallDeviceAuthority(
    accountPeerId: 'account-$name',
    devicePeerId: 'device-$name',
    linked: true,
    deviceKeyEpoch: 1,
    signingPublicKey: 'signing-$name',
    mlKemPublicKey: 'mlkem-$name',
  );
  @override
  Future<CallTrustedRosterSnapshot> loadForContact(String account) async {
    expect(account, 'account-$name');
    return CallTrustedRosterSnapshot(
      contactAccountPeerId: account,
      contactAccepted: true,
      contactBlocked: false,
      devices: [device],
    );
  }

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String peer,
  ) async => peer == 'device-$name' ? device : null;
}

class _Presenter implements IncomingCallPresenter {
  @override
  Future<bool> present(IncomingCallPresentation presentation) async => true;
  @override
  Future<void> dismiss(IncomingCallPresentation presentation) async {}
}

class _Native
    implements WebRtcPeerConnectionAdapter, WebRtcLocalCandidateSource {
  final eventsController =
      StreamController<WebRtcPeerConnectionEvent>.broadcast(sync: true);
  final candidates = StreamController<CallIceCandidate>.broadcast(sync: true);
  @override
  Stream<WebRtcPeerConnectionEvent> get events => eventsController.stream;
  @override
  Stream<CallIceCandidate> get localCandidates => candidates.stream;
  @override
  bool isClosed = false;
  bool enabled = false;
  bool connected = false;
  bool dtls = true;
  bool receiverLive = true;
  bool rtpReports = false;
  int createCalls = 0;
  int closeCalls = 0;
  final localDescriptions = <CallSessionDescriptionType>[];
  final remoteDescriptions = <CallSessionDescriptionType>[];
  void emitConnected() => eventsController.add(
    const WebRtcPeerConnectionEvent(
      kind: WebRtcPeerConnectionEventKind.state,
      connectionState: WebRtcConnectionState.connected,
      transport: WebRtcTransportClass.direct,
      quality: WebRtcQualityBand.good,
      failureReason: WebRtcFailureReason.none,
    ),
  );
  @override
  Future<void> create(WebRtcPeerConnectionConfiguration configuration) async {
    createCalls++;
    enabled = configuration.captureAudio;
  }

  @override
  Future<CallSessionDescription> createOffer() async =>
      const CallSessionDescription(
        type: CallSessionDescriptionType.offer,
        value: _sdp,
      );
  @override
  Future<CallSessionDescription> createAnswer() async =>
      const CallSessionDescription(
        type: CallSessionDescriptionType.answer,
        value: _sdp,
      );
  @override
  Future<void> setLocalDescription(CallSessionDescription description) async {
    localDescriptions.add(description.type);
  }

  @override
  Future<void> setRemoteDescription(CallSessionDescription description) async {
    remoteDescriptions.add(description.type);
  }

  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) async {}
  @override
  Future<void> restartIce() async =>
      throw StateError('unexpected renegotiation');
  @override
  Future<void> setLocalAudioEnabled(bool value) async {
    enabled = value;
  }

  @override
  Future<WebRtcPeerConnectionSnapshot> snapshot() async =>
      WebRtcPeerConnectionSnapshot(
        isClosed: isClosed,
        iceTransportPolicy: WebRtcIceTransportPolicy.all,
        localAudioCaptureTrackCount: isClosed ? 0 : createCalls,
        localVideoCaptureTrackCount: 0,
        audioReceiveTransceiverCount: isClosed ? 0 : 1,
        videoTransceiverCount: 0,
        connectionState: isClosed
            ? WebRtcConnectionState.closed
            : connected
            ? WebRtcConnectionState.connected
            : WebRtcConnectionState.newConnection,
        transport: WebRtcTransportClass.direct,
        selectedPairSucceeded: connected,
        selectedPairNominated: connected,
        dtlsReady: connected && dtls,
        localAudioSenderAttached: !isClosed && createCalls == 1,
        localAudioTrackLive: !isClosed && createCalls == 1,
        remoteAudioReceiverAttached: connected && receiverLive,
        remoteAudioTrackLive: connected && receiverLive,
        localAudioEnabled: enabled,
        inboundAudioRtpObserved: rtpReports,
        outboundAudioRtpObserved: rtpReports,
      );
  @override
  Future<void> close() async {
    if (isClosed) return;
    closeCalls++;
    isClosed = true;
    enabled = false;
    await eventsController.close();
    await candidates.close();
  }
}

class _Permission implements CallMicrophonePermission {
  @override
  Future<MicPermissionStatus> request() async => MicPermissionStatus.granted;
}

class _Conflicts implements CallMediaConflictPort, CallMediaConflictLease {
  @override
  Future<CallMediaConflictLease> acquireForCall() async => this;
  @override
  Future<void> release() async {}
}

class _Session implements CallForegroundAudioSession {
  final events = StreamController<CallAudioSessionInterruption>.broadcast(
    sync: true,
  );
  @override
  bool ownsSession = false;
  @override
  Stream<CallAudioSessionInterruption> get interruptions => events.stream;
  @override
  Future<void> activate() async {
    ownsSession = true;
  }

  @override
  Future<void> deactivate() async {
    ownsSession = false;
  }
}

class _ManualTimer implements CallTimerHandle {
  _ManualTimer(this.callback);
  final Future<void> Function() callback;
  @override
  bool isActive = true;
  @override
  void cancel() {
    isActive = false;
  }
}

class _ManualTimers implements CallTimerScheduler {
  final queue = <_ManualTimer>[];
  Completer<void>? _scheduled;
  Future<void> nextScheduled() => queue.any((t) => t.isActive)
      ? Future<void>.value()
      : (_scheduled ??= Completer<void>()).future;
  @override
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback) {
    final timer = _ManualTimer(callback);
    queue.add(timer);
    _scheduled?.complete();
    _scheduled = null;
    return timer;
  }

  Future<void> fireNext() async {
    final pending = queue.where((t) => t.isActive).toList();
    expect(
      pending,
      isNotEmpty,
      reason: 'the real readiness watch must own a next probe',
    );
    final timer = pending.first;
    timer.isActive = false;
    await timer.callback();
  }
}

Future<Database> _database() => databaseFactoryFfiNoIsolate.openDatabase(
  inMemoryDatabasePath,
  options: OpenDatabaseOptions(
    version: currentIdentityDatabaseVersion,
    singleInstance: false,
    onCreate: runProductionOnCreate,
    onUpgrade: runProductionOnUpgrade,
  ),
);
