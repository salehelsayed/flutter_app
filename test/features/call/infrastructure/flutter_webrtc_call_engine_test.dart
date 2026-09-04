import 'dart:async';

import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/call_audio_route_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/webrtc_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

const String _validFingerprint =
    'sha-256 '
    '00:01:02:03:04:05:06:07:08:09:0A:0B:0C:0D:0E:0F:'
    '10:11:12:13:14:15:16:17:18:19:1A:1B:1C:1D:1E:1F';
const String _differentFingerprint =
    'sha-256 '
    '00:01:02:03:04:05:06:07:08:09:0A:0B:0C:0D:0E:0F:'
    '10:11:12:13:14:15:16:17:18:19:1A:1B:1C:1D:1E:FF';

String _audioSdp(String fingerprint) => <String>[
  'v=0',
  'o=- 0 0 IN IP4 127.0.0.1',
  's=-',
  't=0 0',
  'm=audio 9 UDP/TLS/RTP/SAVPF 111',
  'a=mid:0',
  'a=fingerprint:$fingerprint',
  'a=sendrecv',
].join('\r\n');

String _audioVideoSdp(String fingerprint) => <String>[
  _audioSdp(fingerprint),
  'm=video 9 UDP/TLS/RTP/SAVPF 96',
  'a=mid:1',
  'a=sendrecv',
].join('\r\n');

CallSessionDescription _offer({
  String? fingerprint = _validFingerprint,
  String? sdpFingerprint,
}) => CallSessionDescription(
  type: CallSessionDescriptionType.offer,
  value: _audioSdp(sdpFingerprint ?? fingerprint ?? _validFingerprint),
  fingerprint: fingerprint,
);

CallSessionDescription _answer({
  String? fingerprint = _validFingerprint,
  String? sdpFingerprint,
}) => CallSessionDescription(
  type: CallSessionDescriptionType.answer,
  value: _audioSdp(sdpFingerprint ?? fingerprint ?? _validFingerprint),
  fingerprint: fingerprint,
);

CallIceCandidate _candidate(int index, {int iceGeneration = 0}) =>
    CallIceCandidate(
      value: 'candidate:$index 1 UDP 1 192.0.2.$index 9 typ host',
      mediaId: '0',
      mediaLineIndex: 0,
      iceGeneration: iceGeneration,
    );

Matcher _throwsCallEngineCode(CallEngineErrorCode code) => throwsA(
  isA<CallEngineException>().having(
    (CallEngineException error) => error.code,
    'code',
    code,
  ),
);

final class _RecordingWebRtcAdapter
    implements WebRtcPeerConnectionAdapter, WebRtcLocalCandidateSource {
  final StreamController<WebRtcPeerConnectionEvent> _events =
      StreamController<WebRtcPeerConnectionEvent>.broadcast(sync: true);
  final StreamController<CallIceCandidate> _localCandidates =
      StreamController<CallIceCandidate>.broadcast(sync: true);

  int createCalls = 0;
  int createOfferCalls = 0;
  int createAnswerCalls = 0;
  int restartIceCalls = 0;
  int snapshotCalls = 0;
  int closeCalls = 0;
  bool _closed = false;
  bool failClose = false;
  Completer<void>? closeGate;

  WebRtcPeerConnectionConfiguration? createdWith;
  CallSessionDescription offer = _offer();
  CallSessionDescription answer = _answer();
  final List<CallSessionDescription> localDescriptions =
      <CallSessionDescription>[];
  final List<CallSessionDescription> remoteDescriptions =
      <CallSessionDescription>[];
  final List<List<CallIceCandidate>> addedCandidateBatches =
      <List<CallIceCandidate>>[];
  final List<bool> localAudioEnabledCalls = <bool>[];

  WebRtcConnectionState connectionState = WebRtcConnectionState.connected;
  WebRtcTransportClass transport = WebRtcTransportClass.relay;
  WebRtcRelayProtocol selectedRelayProtocol = WebRtcRelayProtocol.unknown;
  bool selectedPairSucceeded = false;
  bool selectedPairNominated = false;
  bool dtlsReady = false;
  bool localAudioSenderAttached = false;
  bool localAudioTrackLive = false;
  bool remoteAudioReceiverAttached = false;
  bool remoteAudioTrackLive = false;
  bool localAudioEnabled = true;
  bool inboundAudioRtpObserved = false;
  bool outboundAudioRtpObserved = false;

  @override
  Stream<WebRtcPeerConnectionEvent> get events => _events.stream;

  @override
  Stream<CallIceCandidate> get localCandidates => _localCandidates.stream;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> create(WebRtcPeerConnectionConfiguration configuration) async {
    createCalls += 1;
    createdWith = configuration;
  }

  @override
  Future<CallSessionDescription> createOffer() async {
    createOfferCalls += 1;
    return offer;
  }

  @override
  Future<CallSessionDescription> createAnswer() async {
    createAnswerCalls += 1;
    return answer;
  }

  @override
  Future<void> setLocalDescription(CallSessionDescription description) async {
    localDescriptions.add(description);
  }

  @override
  Future<void> setRemoteDescription(CallSessionDescription description) async {
    remoteDescriptions.add(description);
  }

  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) async {
    addedCandidateBatches.add(List<CallIceCandidate>.unmodifiable(candidates));
  }

  @override
  Future<void> restartIce() async {
    restartIceCalls += 1;
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {
    localAudioEnabledCalls.add(enabled);
    localAudioEnabled = enabled;
  }

  @override
  Future<WebRtcPeerConnectionSnapshot> snapshot() async {
    snapshotCalls += 1;
    return WebRtcPeerConnectionSnapshot(
      isClosed: _closed,
      iceTransportPolicy:
          createdWith?.iceTransportPolicy ?? WebRtcIceTransportPolicy.all,
      localAudioCaptureTrackCount: 1,
      localVideoCaptureTrackCount: 0,
      audioReceiveTransceiverCount: 1,
      videoTransceiverCount: 0,
      connectionState: connectionState,
      transport: transport,
      selectedRelayProtocol: selectedRelayProtocol,
      selectedPairSucceeded: selectedPairSucceeded,
      selectedPairNominated: selectedPairNominated,
      dtlsReady: dtlsReady,
      localAudioSenderAttached: localAudioSenderAttached,
      localAudioTrackLive: localAudioTrackLive,
      remoteAudioReceiverAttached: remoteAudioReceiverAttached,
      remoteAudioTrackLive: remoteAudioTrackLive,
      localAudioEnabled: localAudioEnabled,
      inboundAudioRtpObserved: inboundAudioRtpObserved,
      outboundAudioRtpObserved: outboundAudioRtpObserved,
    );
  }

  void markMediaTransportReady({
    WebRtcTransportClass selectedTransport = WebRtcTransportClass.relay,
    WebRtcRelayProtocol relayProtocol = WebRtcRelayProtocol.unknown,
  }) {
    connectionState = WebRtcConnectionState.connected;
    transport = selectedTransport;
    selectedRelayProtocol = relayProtocol;
    selectedPairSucceeded = true;
    selectedPairNominated = true;
    dtlsReady = true;
    localAudioSenderAttached = true;
    localAudioTrackLive = true;
    remoteAudioReceiverAttached = true;
    remoteAudioTrackLive = true;
    localAudioEnabled = false;
  }

  void emitLocalCandidate(CallIceCandidate candidate) {
    _localCandidates.add(candidate);
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    _closed = true;
    final gate = closeGate;
    if (gate != null) await gate.future;
    if (failClose) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  Future<void> dispose() async {
    if (!_localCandidates.isClosed) await _localCandidates.close();
    if (!_events.isClosed) await _events.close();
  }
}

final class _RecordingAudioRoutePort
    implements
        CallAudioRoutePort,
        CallAudioOutputRouteChangeSource,
        CallAudioRouteObserverLifecycle {
  final StreamController<CallAudioOutputRoute> _outputRouteChanges =
      StreamController<CallAudioOutputRoute>.broadcast(sync: true);
  int closeCalls = 0;

  @override
  CallAudioOutputRoute selectedRoute = CallAudioOutputRoute.systemDefault;

  @override
  Stream<CallAudioOutputRoute> get outputRouteChanges =>
      _outputRouteChanges.stream;

  @override
  Future<void> selectOutputRoute(CallAudioOutputRoute route) async {
    selectedRoute = route;
  }

  @override
  Future<List<CallAudioOutputRoute>> supportedOutputRoutes() async =>
      const <CallAudioOutputRoute>[
        CallAudioOutputRoute.systemDefault,
        CallAudioOutputRoute.speaker,
      ];

  void emitDeviceChange() {
    selectedRoute = CallAudioOutputRoute.systemDefault;
    _outputRouteChanges.add(CallAudioOutputRoute.systemDefault);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    await _outputRouteChanges.close();
  }
}

final class _FakeRtpTransceiver implements webrtc.RTCRtpTransceiver {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RetryablePeerConnection implements webrtc.RTCPeerConnection {
  int closeCalls = 0;
  int disposeCalls = 0;
  bool failDispose = false;
  Completer<void>? disposeGate;

  @override
  Future<void> close() async {
    closeCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    final gate = disposeGate;
    if (gate != null) await gate.future;
    if (failDispose) throw StateError('transient peer dispose failure');
  }

  @override
  Future<webrtc.RTCRtpTransceiver> addTransceiver({
    webrtc.MediaStreamTrack? track,
    webrtc.RTCRtpMediaType? kind,
    webrtc.RTCRtpTransceiverInit? init,
  }) async => _FakeRtpTransceiver();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

final class _StatsPeerConnection implements webrtc.RTCPeerConnection {
  _StatsPeerConnection(this._statsSamples);

  final List<List<webrtc.StatsReport>> _statsSamples;
  var _statsSampleIndex = 0;

  @override
  webrtc.RTCPeerConnectionState? get connectionState =>
      webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  @override
  Future<webrtc.RTCRtpTransceiver> addTransceiver({
    webrtc.MediaStreamTrack? track,
    webrtc.RTCRtpMediaType? kind,
    webrtc.RTCRtpTransceiverInit? init,
  }) async => _FakeRtpTransceiver();

  @override
  Future<List<webrtc.RTCRtpSender>> getSenders() async =>
      <webrtc.RTCRtpSender>[];

  @override
  Future<List<webrtc.RTCRtpTransceiver>> getTransceivers() async =>
      <webrtc.RTCRtpTransceiver>[];

  @override
  Future<List<webrtc.RTCRtpReceiver>> getReceivers() async =>
      <webrtc.RTCRtpReceiver>[];

  @override
  Future<List<webrtc.StatsReport>> getStats([
    webrtc.MediaStreamTrack? track,
  ]) async {
    final index = _statsSampleIndex.clamp(0, _statsSamples.length - 1);
    _statsSampleIndex += 1;
    return _statsSamples[index];
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

Future<void> _createAudioConnection(
  FlutterWebRtcCallEngine engine, {
  CallTransportPolicy policy = CallTransportPolicy.all,
  List<CallIceServer> iceServers = const <CallIceServer>[],
}) => engine.createConnection(
  CallConnectionConfiguration(
    transportPolicy: policy,
    receiveAudio: true,
    receiveVideo: false,
    captureAudio: true,
    captureVideo: false,
    iceServers: iceServers,
  ),
);

void main() {
  late _RecordingWebRtcAdapter adapter;
  late FlutterWebRtcCallEngine engine;

  setUp(() {
    adapter = _RecordingWebRtcAdapter();
    engine = FlutterWebRtcCallEngine(
      adapter: adapter,
      eventBufferCapacity: 8,
      candidateBatchCapacity: 2,
      deferredCandidateCapacity: 2,
    );
  });

  tearDown(() async {
    await engine.close();
    await adapter.dispose();
  });

  test('audio-only SDP constraints request no video media section', () {
    expect(webRtcAudioOnlySdpConstraints, const <String, dynamic>{
      'mandatory': <String, bool>{
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': false,
      },
      'optional': <Map<String, dynamic>>[],
    });
  });

  test(
    'adapter retries only a failed peer release without reopening authority',
    () async {
      final peer = _RetryablePeerConnection();
      final adapterUnderTest = FlutterWebRtcPeerConnectionAdapter(
        configureAndroidAudioFocus: () async {},
        peerConnectionFactory: (_) async => peer,
      );
      const configuration = WebRtcPeerConnectionConfiguration(
        iceTransportPolicy: WebRtcIceTransportPolicy.all,
        receiveAudio: true,
        receiveVideo: false,
        captureAudio: false,
        captureVideo: false,
        iceServers: <CallIceServer>[],
      );
      await adapterUnderTest.create(configuration);
      final observed = <WebRtcPeerConnectionEvent>[];
      var doneCalls = 0;
      final subscription = adapterUnderTest.events.listen(
        observed.add,
        onDone: () => doneCalls++,
      );
      peer.failDispose = true;

      await expectLater(
        adapterUnderTest.close(),
        throwsA(isA<WebRtcAdapterException>()),
      );

      expect(adapterUnderTest.isClosed, isTrue);
      expect(peer.closeCalls, 1);
      expect(peer.disposeCalls, 1);
      expect(
        () => adapterUnderTest.create(configuration),
        throwsA(
          isA<WebRtcAdapterException>().having(
            (error) => error.reason,
            'reason',
            WebRtcFailureReason.closed,
          ),
        ),
      );

      peer.failDispose = false;
      final retryGate = Completer<void>();
      peer.disposeGate = retryGate;
      final retryA = adapterUnderTest.close();
      final retryB = adapterUnderTest.close();
      final retryResult = Future.wait(<Future<void>>[
        retryA,
        retryB,
      ]).then<Object?>((_) => null, onError: (Object error, _) => error);

      expect(identical(retryA, retryB), isTrue);
      await Future<void>.delayed(Duration.zero);
      final closeCallsWhileRetryPending = peer.closeCalls;
      final disposeCallsWhileRetryPending = peer.disposeCalls;
      retryGate.complete();
      final retryError = await retryResult;
      await Future<void>.delayed(Duration.zero);

      expect(closeCallsWhileRetryPending, 1);
      expect(disposeCallsWhileRetryPending, 2);
      expect(retryError, isNull);
      await adapterUnderTest.close();
      expect(peer.closeCalls, 1);
      expect(peer.disposeCalls, 2);
      expect(doneCalls, 1);
      expect(
        observed.where(
          (event) => event.kind == WebRtcPeerConnectionEventKind.closed,
        ),
        hasLength(1),
      );
      await subscription.cancel();
    },
  );

  test(
    'adapter yields Android audio focus before creating the WebRTC peer',
    () async {
      final calls = <String>[];
      final peer = _RetryablePeerConnection();
      final adapterUnderTest = FlutterWebRtcPeerConnectionAdapter(
        configureAndroidAudioFocus: () async {
          calls.add('focus.external-owner');
        },
        peerConnectionFactory: (_) async {
          calls.add('peer.create');
          return peer;
        },
      );
      addTearDown(adapterUnderTest.close);

      await adapterUnderTest.create(
        const WebRtcPeerConnectionConfiguration(
          iceTransportPolicy: WebRtcIceTransportPolicy.all,
          receiveAudio: true,
          receiveVideo: false,
          captureAudio: false,
          captureVideo: false,
          iceServers: <CallIceServer>[],
        ),
      );

      expect(calls, <String>['focus.external-owner', 'peer.create']);
    },
  );

  test('adapter retains only ever-observed audio RTP booleans', () async {
    final peer = _StatsPeerConnection(<List<webrtc.StatsReport>>[
      <webrtc.StatsReport>[
        webrtc.StatsReport(
          'inbound-private-id',
          'inbound-rtp',
          1,
          <dynamic, dynamic>{
            'kind': 'audio',
            'packetsReceived': 2,
            'bytesReceived': 20,
            'ssrc': 123456,
          },
        ),
        webrtc.StatsReport(
          'outbound-private-id',
          'outbound-rtp',
          1,
          <dynamic, dynamic>{
            'kind': 'audio',
            'packetsSent': 3,
            'bytesSent': 30,
            'ssrc': 654321,
          },
        ),
      ],
      <webrtc.StatsReport>[],
    ]);
    final adapterUnderTest = FlutterWebRtcPeerConnectionAdapter(
      configureAndroidAudioFocus: () async {},
      peerConnectionFactory: (_) async => peer,
    );
    addTearDown(adapterUnderTest.close);
    await adapterUnderTest.create(
      const WebRtcPeerConnectionConfiguration(
        iceTransportPolicy: WebRtcIceTransportPolicy.all,
        receiveAudio: true,
        receiveVideo: false,
        captureAudio: false,
        captureVideo: false,
      ),
    );

    final observed = await adapterUnderTest.snapshot();
    final laterEmptySample = await adapterUnderTest.snapshot();

    expect(observed.inboundAudioRtpObserved, isTrue);
    expect(observed.outboundAudioRtpObserved, isTrue);
    expect(laterEmptySample.inboundAudioRtpObserved, isTrue);
    expect(laterEmptySample.outboundAudioRtpObserved, isTrue);
    expect(laterEmptySample.toString(), isNot(contains('private-id')));
    expect(laterEmptySample.toString(), isNot(contains('123456')));
    expect(laterEmptySample.toString(), isNot(contains('654321')));
  });

  group('privacy-safe WebRTC failure stage guard', () {
    test(
      'forwards every fixed failure stage without runtime details',
      () async {
        final observed = <FlutterWebRtcFailureStage>[];
        final guard = FlutterWebRtcFailureStageGuard(observed.add);
        final originalFailure = StateError('private plugin failure');

        expect(
          FlutterWebRtcFailureStage.values.map((stage) => stage.name),
          <String>[
            'androidAudioFocus',
            'peerCreate',
            'userMedia',
            'trackInvariant',
            'addTrack',
            'snapshotSenders',
            'snapshotTransceivers',
            'snapshotTransceiverDirection',
            'snapshotReceivers',
            'snapshotStats',
            'snapshotDeadline',
          ],
        );

        for (final stage in FlutterWebRtcFailureStage.values) {
          await expectLater(
            guard.run<void>(stage, () => Future<void>.error(originalFailure)),
            throwsA(same(originalFailure)),
          );
        }

        expect(observed, FlutterWebRtcFailureStage.values);
      },
    );

    test('observer failure preserves operation success and failure', () async {
      var observerCalls = 0;
      final guard = FlutterWebRtcFailureStageGuard((_) {
        observerCalls += 1;
        throw StateError('private observer failure');
      });
      final originalFailure = ArgumentError('private plugin failure');

      await expectLater(
        guard.run<void>(
          FlutterWebRtcFailureStage.userMedia,
          () => Future<void>.error(originalFailure),
        ),
        throwsA(same(originalFailure)),
      );
      expect(observerCalls, 1);

      expect(
        await guard.run<int>(FlutterWebRtcFailureStage.snapshotStats, () => 42),
        42,
      );
      expect(observerCalls, 1);
    });

    test(
      'every snapshot timeout falls back once and later retries normally',
      () async {
        const snapshotStages = <FlutterWebRtcFailureStage>[
          FlutterWebRtcFailureStage.snapshotSenders,
          FlutterWebRtcFailureStage.snapshotTransceivers,
          FlutterWebRtcFailureStage.snapshotTransceiverDirection,
          FlutterWebRtcFailureStage.snapshotReceivers,
          FlutterWebRtcFailureStage.snapshotStats,
        ];
        final observed = <FlutterWebRtcFailureStage>[];
        final guard = FlutterWebRtcFailureStageGuard(observed.add);

        for (final stage in snapshotStages) {
          final pending = Completer<Object>();
          final fallbackValue = Object();
          final fallback = await guard
              .runWithTimeoutFallback<Object>(
                stage,
                () => pending.future,
                timeout: const Duration(milliseconds: 1),
                onTimeout: () => fallbackValue,
              )
              .timeout(const Duration(seconds: 1));

          expect(fallback, same(fallbackValue), reason: stage.name);
          pending.completeError(StateError('late private plugin failure'));
          await Future<void>.delayed(Duration.zero);
          expect(
            observed.where((observedStage) => observedStage == stage),
            hasLength(1),
            reason: '${stage.name} must report only its deadline',
          );

          final actual = Object();
          final retried = await guard.runWithTimeoutFallback<Object>(
            stage,
            () => actual,
            timeout: const Duration(milliseconds: 1),
            onTimeout: Object.new,
          );

          expect(retried, same(actual), reason: stage.name);
        }

        expect(observed, snapshotStages);
      },
    );

    test(
      'aggregate deadline falls back once and a later retry starts fresh',
      () async {
        final observed = <FlutterWebRtcFailureStage>[];
        final guard = FlutterWebRtcFailureStageGuard(observed.add);
        final pending = Completer<Object>();
        final fallbackValue = Object();

        final fallback = await guard
            .runWithDeadlineFallback<Object>(
              FlutterWebRtcFailureStage.snapshotDeadline,
              () => pending.future,
              timeout: const Duration(milliseconds: 1),
              onTimeout: () => fallbackValue,
            )
            .timeout(const Duration(seconds: 1));

        expect(fallback, same(fallbackValue));
        expect(observed, <FlutterWebRtcFailureStage>[
          FlutterWebRtcFailureStage.snapshotDeadline,
        ]);

        final actual = Object();
        final retried = await guard.runWithDeadlineFallback<Object>(
          FlutterWebRtcFailureStage.snapshotDeadline,
          () => actual,
          timeout: const Duration(milliseconds: 1),
          onTimeout: Object.new,
        );

        expect(retried, same(actual));
        expect(observed, <FlutterWebRtcFailureStage>[
          FlutterWebRtcFailureStage.snapshotDeadline,
        ]);
      },
    );

    test(
      'aggregate deadline preserves an exact inner failure without reporting twice',
      () async {
        final observed = <FlutterWebRtcFailureStage>[];
        final guard = FlutterWebRtcFailureStageGuard(observed.add);
        final originalFailure = StateError('private plugin failure');

        await expectLater(
          guard.runWithDeadlineFallback<Object>(
            FlutterWebRtcFailureStage.snapshotDeadline,
            () => guard.run<Object>(
              FlutterWebRtcFailureStage.snapshotSenders,
              () => Future<Object>.error(originalFailure),
            ),
            timeout: const Duration(seconds: 1),
            onTimeout: Object.new,
          ),
          throwsA(same(originalFailure)),
        );

        expect(observed, <FlutterWebRtcFailureStage>[
          FlutterWebRtcFailureStage.snapshotSenders,
        ]);
      },
    );

    test('late source error cannot change an aggregate fallback', () async {
      final observed = <FlutterWebRtcFailureStage>[];
      final guard = FlutterWebRtcFailureStageGuard(observed.add);
      final pending = Completer<Object>();
      final fallbackValue = Object();

      final result = await guard
          .runWithDeadlineFallback<Object>(
            FlutterWebRtcFailureStage.snapshotDeadline,
            () => pending.future,
            timeout: const Duration(milliseconds: 1),
            onTimeout: () => fallbackValue,
          )
          .timeout(const Duration(seconds: 1));
      expect(result, same(fallbackValue));
      expect(observed, <FlutterWebRtcFailureStage>[
        FlutterWebRtcFailureStage.snapshotDeadline,
      ]);

      pending.completeError(StateError('late private plugin failure'));
      await Future<void>.delayed(Duration.zero);

      expect(result, same(fallbackValue));
      expect(observed, <FlutterWebRtcFailureStage>[
        FlutterWebRtcFailureStage.snapshotDeadline,
      ]);
    });
  });

  group('VC2-03 audio-only peer-connection policy', () {
    test(
      'normal mode forwards all policy, ICE servers, and capture audio',
      () async {
        final expiresAt = DateTime.utc(2030, 1, 1);
        final servers = <CallIceServer>[
          CallIceServer(
            urls: const <String>['stun:stun.example.test:3478'],
            expiresAt: expiresAt,
          ),
          CallIceServer(
            urls: const <String>[
              'turn:turn.example.test:3478?transport=udp',
              'turns:turn.example.test:5349?transport=tcp',
            ],
            username: 'ephemeral-user',
            credential: 'ephemeral-credential',
            expiresAt: expiresAt,
          ),
        ];

        await _createAudioConnection(engine, iceServers: servers);

        final configuration = adapter.createdWith!;
        expect(adapter.createCalls, 1);
        expect(configuration.iceTransportPolicy, WebRtcIceTransportPolicy.all);
        expect(configuration.receiveAudio, isTrue);
        expect(configuration.receiveVideo, isFalse);
        expect(configuration.captureAudio, isTrue);
        expect(configuration.captureVideo, isFalse);
        expect(configuration.iceServers, hasLength(2));
        expect(configuration.iceServers.first.urls, const <String>[
          'stun:stun.example.test:3478',
        ]);
        expect(configuration.iceServers.last.username, 'ephemeral-user');
        expect(
          configuration.iceServers.last.credential,
          'ephemeral-credential',
        );
        expect(configuration.iceServers.last.expiresAt, expiresAt);
      },
    );

    test(
      'always-relay mode forwards relay-only policy without fallback',
      () async {
        final expiresAt = DateTime.utc(2030, 1, 1);
        await _createAudioConnection(
          engine,
          policy: CallTransportPolicy.relayOnly,
          iceServers: <CallIceServer>[
            CallIceServer(
              urls: const <String>['turns:turn.example.test:5349'],
              username: 'ephemeral-user',
              credential: 'ephemeral-credential',
              expiresAt: expiresAt,
            ),
          ],
        );

        final configuration = adapter.createdWith!;
        expect(adapter.createCalls, 1);
        expect(
          configuration.iceTransportPolicy,
          WebRtcIceTransportPolicy.relayOnly,
        );
        expect(configuration.captureAudio, isTrue);
        expect(configuration.iceServers, hasLength(1));
      },
    );

    test('accepts the authority-wide sixteen-URL TURN bound', () async {
      final expiresAt = DateTime.utc(2030, 1, 1);
      final urls = List<String>.generate(
        16,
        (index) => 'turn:turn-$index.example.test:3478?transport=udp',
      );

      await _createAudioConnection(
        engine,
        iceServers: <CallIceServer>[
          CallIceServer(
            urls: urls,
            username: 'ephemeral-user',
            credential: 'ephemeral-credential',
            expiresAt: expiresAt,
          ),
        ],
      );

      expect(adapter.createdWith?.iceServers.single.urls, urls);
    });

    test(
      'rejects a duplicate connection without touching the adapter',
      () async {
        await _createAudioConnection(engine);

        await expectLater(
          () => _createAudioConnection(engine),
          _throwsCallEngineCode(CallEngineErrorCode.configurationRejected),
        );

        expect(adapter.createCalls, 1);
      },
    );
  });

  group('VC2-03 authenticated descriptions and ICE generations', () {
    test(
      'caller applies offer then answer in order and exact duplicates are idempotent',
      () async {
        await _createAudioConnection(engine);

        await expectLater(
          () => engine.createAnswer(),
          _throwsCallEngineCode(CallEngineErrorCode.configurationRejected),
        );
        await expectLater(
          () => engine.setRemoteDescription(_answer()),
          _throwsCallEngineCode(CallEngineErrorCode.configurationRejected),
        );

        final offer = await engine.createOffer();
        final duplicateOffer = await engine.createOffer();
        expect(offer.type, CallSessionDescriptionType.offer);
        expect(offer.fingerprint, _validFingerprint);
        expect(duplicateOffer.value, offer.value);
        expect(adapter.createOfferCalls, 1);

        await expectLater(
          () => engine.setLocalDescription(_answer()),
          _throwsCallEngineCode(CallEngineErrorCode.configurationRejected),
        );
        await engine.setLocalDescription(offer);
        await engine.setLocalDescription(offer);
        expect(adapter.localDescriptions, hasLength(1));

        final answer = _answer();
        await engine.setRemoteDescription(answer);
        await engine.setRemoteDescription(answer);
        expect(adapter.remoteDescriptions, hasLength(1));
      },
    );

    test(
      'callee applies offer then creates answer and exact duplicates are idempotent',
      () async {
        await _createAudioConnection(engine);
        final offer = _offer();

        await engine.setRemoteDescription(offer);
        await engine.setRemoteDescription(offer);
        expect(adapter.remoteDescriptions, hasLength(1));

        final answer = await engine.createAnswer();
        final duplicateAnswer = await engine.createAnswer();
        expect(answer.type, CallSessionDescriptionType.answer);
        expect(answer.fingerprint, _validFingerprint);
        expect(duplicateAnswer.value, answer.value);
        expect(adapter.createAnswerCalls, 1);

        await expectLater(
          () => engine.setLocalDescription(offer),
          _throwsCallEngineCode(CallEngineErrorCode.configurationRejected),
        );
        await engine.setLocalDescription(answer);
        await engine.setLocalDescription(answer);
        expect(adapter.localDescriptions, hasLength(1));
      },
    );

    test(
      'extracts local fingerprints and rejects malformed local SDP',
      () async {
        await _createAudioConnection(engine);
        adapter.offer = _offer(fingerprint: null);

        final offer = await engine.createOffer();

        expect(offer.fingerprint, _validFingerprint);
        expect(adapter.createOfferCalls, 1);

        await engine.close();
        await adapter.dispose();
        adapter = _RecordingWebRtcAdapter()
          ..offer = CallSessionDescription(
            type: CallSessionDescriptionType.offer,
            value: _audioSdp(
              _validFingerprint,
            ).replaceFirst('a=fingerprint:$_validFingerprint', ''),
          );
        engine = FlutterWebRtcCallEngine(
          adapter: adapter,
          candidateBatchCapacity: 2,
          deferredCandidateCapacity: 2,
        );
        await _createAudioConnection(engine);

        await expectLater(
          () => engine.createOffer(),
          _throwsCallEngineCode(CallEngineErrorCode.malformedFingerprint),
        );
        expect(adapter.localDescriptions, isEmpty);
      },
    );

    test('accepts only the exact authenticated SDP fingerprint', () async {
      await _createAudioConnection(engine);
      final description = _offer();

      await engine.setRemoteDescription(description);

      expect(adapter.remoteDescriptions, hasLength(1));
      expect(adapter.remoteDescriptions.single.value, description.value);
      expect(adapter.remoteDescriptions.single.fingerprint, _validFingerprint);
    });

    test(
      'missing, malformed, and mismatched fingerprints fail before adapter',
      () async {
        await _createAudioConnection(engine);

        await expectLater(
          () => engine.setRemoteDescription(_offer(fingerprint: null)),
          _throwsCallEngineCode(CallEngineErrorCode.malformedFingerprint),
        );
        await expectLater(
          () =>
              engine.setRemoteDescription(_offer(fingerprint: 'sha-256 AA:BB')),
          _throwsCallEngineCode(CallEngineErrorCode.malformedFingerprint),
        );
        await expectLater(
          () => engine.setRemoteDescription(
            _offer(
              fingerprint: _differentFingerprint,
              sdpFingerprint: _validFingerprint,
            ),
          ),
          _throwsCallEngineCode(CallEngineErrorCode.fingerprintMismatch),
        );

        expect(adapter.remoteDescriptions, isEmpty);
      },
    );

    test(
      'rejects a remote video SDP section before adapter mutation',
      () async {
        await _createAudioConnection(engine);

        await expectLater(
          () => engine.setRemoteDescription(
            CallSessionDescription(
              type: CallSessionDescriptionType.offer,
              value: _audioVideoSdp(_validFingerprint),
              fingerprint: _validFingerprint,
            ),
          ),
          _throwsCallEngineCode(CallEngineErrorCode.configurationRejected),
        );

        expect(adapter.remoteDescriptions, isEmpty);
      },
    );

    test(
      'defers a bounded candidate set and drains it after description',
      () async {
        await _createAudioConnection(engine);
        final first = _candidate(1);
        final second = _candidate(2);

        await engine.addIceCandidates(<CallIceCandidate>[first]);
        await engine.addIceCandidates(<CallIceCandidate>[second]);
        expect(adapter.addedCandidateBatches, isEmpty);

        await engine.setRemoteDescription(_offer());

        expect(adapter.remoteDescriptions, hasLength(1));
        expect(adapter.addedCandidateBatches, hasLength(1));
        expect(
          adapter.addedCandidateBatches.single.map(
            (candidate) => candidate.value,
          ),
          <String>[first.value, second.value],
        );
      },
    );

    test(
      'rejects deferred candidate overflow before adapter mutation',
      () async {
        await _createAudioConnection(engine);
        await engine.addIceCandidates(<CallIceCandidate>[_candidate(1)]);
        await engine.addIceCandidates(<CallIceCandidate>[_candidate(2)]);

        await expectLater(
          () => engine.addIceCandidates(<CallIceCandidate>[_candidate(3)]),
          _throwsCallEngineCode(CallEngineErrorCode.candidateOverflow),
        );

        expect(adapter.addedCandidateBatches, isEmpty);
        expect(adapter.remoteDescriptions, isEmpty);
      },
    );

    test(
      'rejects an oversized candidate batch after remote description',
      () async {
        await _createAudioConnection(engine);
        await engine.setRemoteDescription(_offer());

        await expectLater(
          () => engine.addIceCandidates(<CallIceCandidate>[
            _candidate(1),
            _candidate(2),
            _candidate(3),
          ]),
          _throwsCallEngineCode(CallEngineErrorCode.candidateOverflow),
        );

        expect(adapter.addedCandidateBatches, isEmpty);
        await engine.addIceCandidates(<CallIceCandidate>[
          _candidate(1),
          _candidate(2),
        ]);
        expect(adapter.addedCandidateBatches.single, hasLength(2));
      },
    );

    test(
      'relay-only filters adversarial outbound, inbound, and embedded candidates',
      () async {
        await _createAudioConnection(
          engine,
          policy: CallTransportPolicy.relayOnly,
        );
        final observed = <CallIceCandidate>[];
        final subscription = engine.localCandidates.listen(observed.add);
        const disguisedHost = CallIceCandidate(
          value:
              'candidate:1 1 UDP 1 192.0.2.1 9 typ host generation 0 typ relay',
          mediaId: '0',
          mediaLineIndex: 0,
        );
        const relay = CallIceCandidate(
          value: 'candidate:2 1 UDP 1 192.0.2.2 9 typ relay',
          mediaId: '0',
          mediaLineIndex: 0,
        );

        adapter.emitLocalCandidate(disguisedHost);
        adapter.emitLocalCandidate(relay);
        expect(observed, <CallIceCandidate>[relay]);

        await engine.setRemoteDescription(_offer());
        await expectLater(
          () =>
              engine.addIceCandidates(const <CallIceCandidate>[disguisedHost]),
          _throwsCallEngineCode(CallEngineErrorCode.relayPolicyViolation),
        );
        await engine.addIceCandidates(const <CallIceCandidate>[relay]);
        expect(adapter.addedCandidateBatches.single, <CallIceCandidate>[relay]);

        await subscription.cancel();
        await engine.close();
        await adapter.dispose();
        adapter = _RecordingWebRtcAdapter();
        engine = FlutterWebRtcCallEngine(
          adapter: adapter,
          candidateBatchCapacity: 2,
          deferredCandidateCapacity: 2,
        );
        await _createAudioConnection(
          engine,
          policy: CallTransportPolicy.relayOnly,
        );
        final embeddedHost = CallSessionDescription(
          type: CallSessionDescriptionType.offer,
          value: <String>[
            _audioSdp(_validFingerprint),
            'a=candidate:3 1 UDP 1 192.0.2.3 9 typ host generation 0 typ relay',
          ].join('\r\n'),
          fingerprint: _validFingerprint,
        );

        await expectLater(
          () => engine.setRemoteDescription(embeddedHost),
          _throwsCallEngineCode(CallEngineErrorCode.relayPolicyViolation),
        );
        expect(adapter.remoteDescriptions, isEmpty);
      },
    );

    test(
      'allows bounded ICE restarts, drops stale and rejects future generations',
      () async {
        await _createAudioConnection(engine);
        expect(engine.iceGeneration, 0);

        expect(await engine.restartIce(), 1);
        expect(engine.iceGeneration, 1);
        expect(adapter.restartIceCalls, 1);

        // A late candidate of the superseded generation is dropped, not fatal.
        await engine.addIceCandidates(<CallIceCandidate>[
          _candidate(1, iceGeneration: 0),
        ]);
        await expectLater(
          () => engine.addIceCandidates(<CallIceCandidate>[
            _candidate(2, iceGeneration: 2),
          ]),
          _throwsCallEngineCode(CallEngineErrorCode.futureIceGeneration),
        );

        for (
          var restart = 2;
          restart <= FlutterWebRtcCallEngine.maxIceRestarts;
          restart++
        ) {
          expect(await engine.restartIce(), restart);
        }
        await expectLater(
          () => engine.restartIce(),
          _throwsCallEngineCode(CallEngineErrorCode.restartLimitReached),
        );

        expect(adapter.restartIceCalls, FlutterWebRtcCallEngine.maxIceRestarts);
        expect(adapter.addedCandidateBatches, isEmpty);
      },
    );
  });

  group('VC2-03 media readiness and cleanup', () {
    test('audio session may activate before connection creation', () async {
      await engine.setAudioSessionActive(true);
      await _createAudioConnection(engine);

      expect((await engine.snapshot()).audioSessionActive, isTrue);
    });

    test('supported route selection reflects the actual route port', () async {
      final routePort = _RecordingAudioRoutePort();
      await engine.close();
      engine = FlutterWebRtcCallEngine(
        adapter: adapter,
        audioRoutePort: routePort,
        eventBufferCapacity: 8,
        deferredCandidateCapacity: 2,
      );
      await _createAudioConnection(engine);

      expect(
        await engine.supportedOutputRoutes(),
        contains(CallAudioOutputRoute.speaker),
      );
      await engine.selectOutputRoute(CallAudioOutputRoute.speaker);

      expect(
        (await engine.snapshot()).outputRoute,
        CallAudioOutputRoute.speaker,
      );
    });

    test(
      'forwards coarse route changes and closes the route observer',
      () async {
        final routePort = _RecordingAudioRoutePort();
        await engine.close();
        engine = FlutterWebRtcCallEngine(
          adapter: adapter,
          audioRoutePort: routePort,
          eventBufferCapacity: 8,
          deferredCandidateCapacity: 2,
        );
        await _createAudioConnection(engine);
        await engine.selectOutputRoute(CallAudioOutputRoute.speaker);
        final changes = <CallAudioOutputRoute>[];
        var changesClosed = false;
        final subscription = engine.outputRouteChanges.listen(
          changes.add,
          onDone: () => changesClosed = true,
        );

        routePort.emitDeviceChange();

        expect(changes, <CallAudioOutputRoute>[
          CallAudioOutputRoute.systemDefault,
        ]);
        expect(
          (await engine.snapshot()).outputRoute,
          CallAudioOutputRoute.systemDefault,
        );

        await engine.close();
        expect(routePort.closeCalls, 1);
        expect(changesClosed, isTrue);
        await subscription.cancel();
      },
    );

    test(
      'repeated mute state converges without duplicate adapter writes',
      () async {
        await _createAudioConnection(engine);

        await engine.setLocalAudioEnabled(false);
        await engine.setLocalAudioEnabled(false);
        await engine.setLocalAudioEnabled(true);
        await engine.setLocalAudioEnabled(true);

        expect(adapter.localAudioEnabledCalls, <bool>[false, true]);
        expect((await engine.snapshot()).localAudioEnabled, isTrue);
      },
    );

    test(
      'silent muted media is ready only when every structural gate is ready',
      () async {
        await _createAudioConnection(engine);
        adapter.markMediaTransportReady();
        await engine.setAudioSessionActive(true);

        final ready = await engine.snapshot();
        expect(ready.selectedPairSucceeded, isTrue);
        expect(ready.selectedPairNominated, isTrue);
        expect(ready.dtlsReady, isTrue);
        expect(ready.audioSessionActive, isTrue);
        expect(ready.localAudioSenderAttached, isTrue);
        expect(ready.localAudioTrackLive, isTrue);
        expect(ready.remoteAudioReceiverAttached, isTrue);
        expect(ready.remoteAudioTrackLive, isTrue);
        expect(ready.localAudioEnabled, isFalse);
        expect(ready.inboundAudioRtpObserved, isFalse);
        expect(ready.outboundAudioRtpObserved, isFalse);
        expect(
          ready.isMediaReady,
          isTrue,
          reason:
              'mute, silence, zero RTP, and zero audio energy are not gates',
        );

        adapter.inboundAudioRtpObserved = true;
        adapter.outboundAudioRtpObserved = true;
        final withRtpEvidence = await engine.snapshot();
        expect(withRtpEvidence.inboundAudioRtpObserved, isTrue);
        expect(withRtpEvidence.outboundAudioRtpObserved, isTrue);
        expect(withRtpEvidence.isMediaReady, isTrue);

        await engine.setAudioSessionActive(false);
        expect((await engine.snapshot()).isMediaReady, isFalse);
        await engine.setAudioSessionActive(true);

        final missingRequirements = <String, void Function()>{
          'selected pair succeeded': () =>
              adapter.selectedPairSucceeded = false,
          'selected pair nominated': () =>
              adapter.selectedPairNominated = false,
          'DTLS ready': () => adapter.dtlsReady = false,
          'local sender attached': () =>
              adapter.localAudioSenderAttached = false,
          'local track live': () => adapter.localAudioTrackLive = false,
          'remote receiver attached': () =>
              adapter.remoteAudioReceiverAttached = false,
          'remote track live': () => adapter.remoteAudioTrackLive = false,
        };
        for (final requirement in missingRequirements.entries) {
          adapter.markMediaTransportReady();
          requirement.value();
          expect(
            (await engine.snapshot()).isMediaReady,
            isFalse,
            reason: '${requirement.key} must remain a setup gate',
          );
        }
      },
    );

    test('relay-only selected direct transport fails closed', () async {
      await _createAudioConnection(
        engine,
        policy: CallTransportPolicy.relayOnly,
      );
      adapter.markMediaTransportReady(
        selectedTransport: WebRtcTransportClass.direct,
      );
      await engine.setAudioSessionActive(true);

      await expectLater(
        () => engine.snapshot(),
        _throwsCallEngineCode(CallEngineErrorCode.relayPolicyViolation),
      );

      expect(adapter.snapshotCalls, 1);
      expect(adapter.createCalls, 1);
    });

    test('relay-only unknown selected transport fails closed', () async {
      await _createAudioConnection(
        engine,
        policy: CallTransportPolicy.relayOnly,
      );
      adapter.markMediaTransportReady(
        selectedTransport: WebRtcTransportClass.unknown,
      );
      await engine.setAudioSessionActive(true);

      await expectLater(
        () => engine.snapshot(),
        _throwsCallEngineCode(CallEngineErrorCode.relayPolicyViolation),
      );

      expect(adapter.snapshotCalls, 1);
      expect(adapter.createCalls, 1);
    });

    test('relay-only accepts proven TURN UDP and TCP TLS transports', () async {
      await _createAudioConnection(
        engine,
        policy: CallTransportPolicy.relayOnly,
      );
      await engine.setAudioSessionActive(true);

      for (final transport in <WebRtcTransportClass>[
        WebRtcTransportClass.turnUdp,
        WebRtcTransportClass.turnTcpTls,
      ]) {
        adapter.markMediaTransportReady(selectedTransport: transport);
        expect((await engine.snapshot()).isMediaReady, isTrue);
      }
    });

    test(
      'snapshot propagates only the fixed selected relay protocol enum',
      () async {
        await _createAudioConnection(
          engine,
          policy: CallTransportPolicy.relayOnly,
        );
        await engine.setAudioSessionActive(true);

        const mappings = <WebRtcRelayProtocol, CallRelayProtocol>{
          WebRtcRelayProtocol.notRelay: CallRelayProtocol.notRelay,
          WebRtcRelayProtocol.unknown: CallRelayProtocol.unknown,
          WebRtcRelayProtocol.udp: CallRelayProtocol.udp,
          WebRtcRelayProtocol.tcp: CallRelayProtocol.tcp,
          WebRtcRelayProtocol.tls: CallRelayProtocol.tls,
        };
        for (final entry in mappings.entries) {
          adapter.markMediaTransportReady(
            selectedTransport: WebRtcTransportClass.turnUdp,
            relayProtocol: entry.key,
          );

          expect((await engine.snapshot()).selectedRelayProtocol, entry.value);
        }
      },
    );

    test('close is idempotent and completes the event stream once', () async {
      final observed = <CallEngineEvent>[];
      var doneCalls = 0;
      final subscription = engine.events.listen(
        observed.add,
        onDone: () => doneCalls += 1,
      );

      await Future.wait(<Future<void>>[
        engine.close(),
        engine.close(),
        engine.close(),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(adapter.closeCalls, 1);
      expect(engine.isClosed, isTrue);
      expect(doneCalls, 1);
      expect(
        observed.where((event) => event.type == CallEngineEventType.closed),
        hasLength(1),
      );
      await subscription.cancel();
    });

    test(
      'failed close retries the same adapter and keeps later cleanup once',
      () async {
        final failingAdapter = _RecordingWebRtcAdapter()..failClose = true;
        final routePort = _RecordingAudioRoutePort();
        final failingEngine = FlutterWebRtcCallEngine(
          adapter: failingAdapter,
          audioRoutePort: routePort,
        );
        var eventsClosed = false;
        final subscription = failingEngine.events.listen(
          (_) {},
          onDone: () => eventsClosed = true,
        );

        await expectLater(
          failingEngine.close(),
          throwsA(isA<WebRtcAdapterException>()),
        );

        expect(failingAdapter.closeCalls, 1);
        expect(routePort.closeCalls, 1);
        expect(eventsClosed, isTrue);
        expect(failingEngine.isClosed, isTrue);
        expect(
          () => failingEngine.createConnection(
            const CallConnectionConfiguration(
              transportPolicy: CallTransportPolicy.all,
              receiveAudio: true,
              receiveVideo: false,
              captureAudio: true,
              captureVideo: false,
            ),
          ),
          _throwsCallEngineCode(CallEngineErrorCode.closed),
        );

        failingAdapter.failClose = false;
        final retryGate = Completer<void>();
        failingAdapter.closeGate = retryGate;
        final retryA = failingEngine.close();
        final retryB = failingEngine.close();
        final retryResult = Future.wait(<Future<void>>[
          retryA,
          retryB,
        ]).then<Object?>((_) => null, onError: (Object error, _) => error);

        expect(identical(retryA, retryB), isTrue);
        await Future<void>.delayed(Duration.zero);
        final callsWhileRetryPending = failingAdapter.closeCalls;
        retryGate.complete();
        final retryError = await retryResult;

        expect(callsWhileRetryPending, 2);
        expect(retryError, isNull);
        await failingEngine.close();
        expect(failingAdapter.closeCalls, 2);
        expect(routePort.closeCalls, 1);
        expect(eventsClosed, isTrue);
        await subscription.cancel();
        await failingAdapter.dispose();
      },
    );
  });
}
