import 'dart:async';
import 'dart:io';

import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCallEngine implements CallEngine {
  final StreamController<CallEngineEvent> _events =
      StreamController<CallEngineEvent>.broadcast();

  bool _closed = false;
  CallConnectionConfiguration? createdWith;

  @override
  Stream<CallEngineEvent> get events => _events.stream;

  @override
  Stream<CallIceCandidate> get localCandidates =>
      const Stream<CallIceCandidate>.empty();

  @override
  List<CallEngineEvent> get recentEvents => const <CallEngineEvent>[];

  @override
  bool get isClosed => _closed;

  @override
  int get candidateBatchCapacity => 8;

  @override
  int get iceGeneration => 0;

  @override
  Future<void> createConnection(
    CallConnectionConfiguration configuration,
  ) async {
    createdWith = configuration;
  }

  @override
  Future<CallSessionDescription> createOffer() async =>
      const CallSessionDescription(
        type: CallSessionDescriptionType.offer,
        value: 'opaque-offer-fixture',
      );

  @override
  Future<CallSessionDescription> createAnswer() async =>
      const CallSessionDescription(
        type: CallSessionDescriptionType.answer,
        value: 'opaque-answer-fixture',
      );

  @override
  Future<void> setLocalDescription(CallSessionDescription description) async {}

  @override
  Future<void> setRemoteDescription(CallSessionDescription description) async {}

  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) async {}

  @override
  Future<int> restartIce({
    List<CallIceServer> iceServers = const <CallIceServer>[],
  }) async => 1;

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {}

  @override
  Future<void> setAudioSessionActive(bool active) async {}

  @override
  Future<List<CallAudioOutputRoute>> supportedOutputRoutes() async =>
      const <CallAudioOutputRoute>[CallAudioOutputRoute.systemDefault];

  @override
  Future<void> selectOutputRoute(CallAudioOutputRoute route) async {}

  @override
  Future<CallConnectionSnapshot> snapshot() async =>
      const CallConnectionSnapshot(
        state: CallConnectionState.newConnection,
        transportPolicy: CallTransportPolicy.relayOnly,
        transport: CallTransportClass.unknown,
        quality: CallQualityBand.unknown,
        localAudioCaptureTrackCount: 0,
        localVideoCaptureTrackCount: 0,
        audioReceiveTransceiverCount: 1,
        videoTransceiverCount: 0,
      );

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _events.close();
  }
}

void main() {
  test(
    'VC2-01 CallEngine is an app-owned, replaceable audio-only boundary',
    () async {
      final CallEngine engine = _FakeCallEngine();
      const configuration = CallConnectionConfiguration(
        transportPolicy: CallTransportPolicy.relayOnly,
        receiveAudio: true,
        receiveVideo: false,
        captureAudio: false,
        captureVideo: false,
      );

      await engine.createConnection(configuration);
      await engine.createOffer();
      await engine.createAnswer();
      await engine.setLocalDescription(
        const CallSessionDescription(
          type: CallSessionDescriptionType.offer,
          value: 'opaque-local-description-fixture',
        ),
      );
      await engine.setRemoteDescription(
        const CallSessionDescription(
          type: CallSessionDescriptionType.answer,
          value: 'opaque-remote-description-fixture',
        ),
      );
      await engine.addIceCandidates(const <CallIceCandidate>[
        CallIceCandidate(
          value: 'opaque-ice-fixture',
          mediaId: 'audio',
          mediaLineIndex: 0,
        ),
      ]);
      await engine.restartIce();
      await engine.setLocalAudioEnabled(false);
      await engine.selectOutputRoute(CallAudioOutputRoute.systemDefault);

      expect((engine as _FakeCallEngine).createdWith, same(configuration));
      expect(await engine.supportedOutputRoutes(), isNotEmpty);
      final snapshot = await engine.snapshot();
      expect(snapshot.transportPolicy, CallTransportPolicy.relayOnly);
      expect(snapshot.localAudioCaptureTrackCount, 0);
      expect(snapshot.localVideoCaptureTrackCount, 0);
      expect(snapshot.selectedRelayProtocol, CallRelayProtocol.unknown);
      await engine.close();
      expect(engine.isClosed, isTrue);
    },
  );

  test('VC2-01 domain and application sources do not reference plugin types', () {
    final forbidden = RegExp(
      r'package:flutter_webrtc|\bRTCPeerConnection\b|\bRTCSessionDescription\b|'
      r'\bRTCIceCandidate\b|\bMediaStream(?:Track)?\b|'
      r'\bRTCRtpTransceiver\b',
    );
    final roots = <Directory>[
      Directory('lib/features/call/domain'),
      Directory('lib/features/call/application'),
    ];

    for (final root in roots.where((directory) => directory.existsSync())) {
      final sources = root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      for (final source in sources) {
        expect(
          forbidden.hasMatch(source.readAsStringSync()),
          isFalse,
          reason: '${source.path} crossed the VC2-01 plugin boundary',
        );
      }
    }
  });
}
