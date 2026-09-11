import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/call/application/voice_call_feature_flags.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/webrtc_types.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWebRtcPeerConnectionAdapter implements WebRtcPeerConnectionAdapter {
  final StreamController<WebRtcPeerConnectionEvent> _events =
      StreamController<WebRtcPeerConnectionEvent>.broadcast(sync: true);

  int createCalls = 0;
  int closeCalls = 0;
  bool failCreate = false;
  bool _closed = false;
  WebRtcPeerConnectionConfiguration? createdWith;

  @override
  Stream<WebRtcPeerConnectionEvent> get events => _events.stream;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> create(WebRtcPeerConnectionConfiguration configuration) async {
    createCalls += 1;
    createdWith = configuration;
    if (failCreate) {
      throw const WebRtcAdapterException(
        WebRtcFailureReason.transportUnavailable,
      );
    }
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
  Future<void> restartIce() async {}

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {}

  void emit(WebRtcPeerConnectionEvent event) => _events.add(event);

  @override
  Future<WebRtcPeerConnectionSnapshot> snapshot() async =>
      WebRtcPeerConnectionSnapshot(
        isClosed: _closed,
        iceTransportPolicy: WebRtcIceTransportPolicy.relayOnly,
        localAudioCaptureTrackCount: 0,
        localVideoCaptureTrackCount: 0,
        audioReceiveTransceiverCount: 1,
        videoTransceiverCount: 0,
      );

  @override
  Future<void> close() async {
    closeCalls += 1;
    _closed = true;
  }

  Future<void> disposeController() => _events.close();
}

void main() {
  late _FakeWebRtcPeerConnectionAdapter adapter;
  late FlutterWebRtcCallEngine engine;

  setUp(() {
    adapter = _FakeWebRtcPeerConnectionAdapter();
    engine = FlutterWebRtcCallEngine(adapter: adapter, eventBufferCapacity: 8);
  });

  tearDown(() async {
    await engine.close();
    await adapter.disposeController();
  });

  test('VC2-01 creates receive-only audio without opening capture', () async {
    await engine.createConnection(
      const CallConnectionConfiguration(
        transportPolicy: CallTransportPolicy.relayOnly,
        receiveAudio: true,
        receiveVideo: false,
        captureAudio: false,
        captureVideo: false,
      ),
    );

    final configuration = adapter.createdWith!;
    expect(
      configuration.iceTransportPolicy,
      WebRtcIceTransportPolicy.relayOnly,
    );
    expect(configuration.receiveAudio, isTrue);
    expect(configuration.receiveVideo, isFalse);
    expect(configuration.captureAudio, isFalse);
    expect(configuration.captureVideo, isFalse);

    final snapshot = await adapter.snapshot();
    expect(snapshot.localAudioCaptureTrackCount, 0);
    expect(snapshot.localVideoCaptureTrackCount, 0);
    expect(snapshot.audioReceiveTransceiverCount, 1);
    expect(snapshot.videoTransceiverCount, 0);
  });

  test(
    'VC2-01 relay-only creation fails closed without a direct retry',
    () async {
      adapter.failCreate = true;

      await expectLater(
        engine.createConnection(
          const CallConnectionConfiguration(
            transportPolicy: CallTransportPolicy.relayOnly,
            receiveAudio: true,
            receiveVideo: false,
            captureAudio: false,
            captureVideo: false,
          ),
        ),
        throwsA(isA<WebRtcAdapterException>()),
      );

      expect(adapter.createCalls, 1);
      expect(
        adapter.createdWith!.iceTransportPolicy,
        WebRtcIceTransportPolicy.relayOnly,
      );
    },
  );

  test('VC2-01 close is idempotent across engine and plugin facade', () async {
    await engine.close();
    await engine.close();

    expect(adapter.closeCalls, 1);
    expect(adapter.isClosed, isTrue);
    expect(engine.isClosed, isTrue);
  });

  test(
    'VC2-03 adapter exposes partial capture ownership and stops mic before peer close',
    () {
      final source = File(
        'lib/features/call/infrastructure/flutter_webrtc_call_engine.dart',
      ).readAsStringSync();
      final createStart = source.indexOf('Future<void> _createOnce(');
      final createEnd = source.indexOf(
        '  void _validateConfiguration(',
        createStart,
      );
      final createBody = source.substring(createStart, createEnd);
      final mediaOpen = createBody.indexOf(
        'webrtc.navigator.mediaDevices.getUserMedia',
      );
      final trackAttach = createBody.indexOf(
        'await connection.addTrack(localTrack, localStream);',
      );
      final receiveOnlyTransceiver = createBody.indexOf(
        'await connection.addTransceiver(',
        trackAttach + 1,
      );

      expect(createStart, isNonNegative);
      expect(createEnd, greaterThan(createStart));
      expect(
        createBody.indexOf('_peerConnection = connection;'),
        inInclusiveRange(0, mediaOpen - 1),
      );
      expect(
        createBody.indexOf('_localStream = localStream;'),
        inInclusiveRange(mediaOpen + 1, trackAttach - 1),
      );
      expect(
        createBody.indexOf('_localAudioTrack = localTrack;'),
        inInclusiveRange(mediaOpen + 1, trackAttach - 1),
      );
      expect(trackAttach, greaterThan(mediaOpen));
      expect(receiveOnlyTransceiver, greaterThan(trackAttach));
      expect(
        createBody.substring(receiveOnlyTransceiver),
        contains('direction: webrtc.TransceiverDirection.RecvOnly'),
      );

      final closeStart = source.indexOf('Future<void> _closeOnce() async {');
      final closeEnd = source.indexOf(
        '  Future<bool> _releaseConnection(',
        closeStart,
      );
      final closeBody = source.substring(closeStart, closeEnd);
      final stopTrack = closeBody.indexOf('await _stopTrack(localTrack)');
      final disposeStream = closeBody.indexOf(
        'await _disposeStream(localStream)',
      );
      final closePeer = closeBody.indexOf(
        'await attempt(connection.close, () {',
      );
      final disposePeer = closeBody.indexOf(
        'await attempt(connection.dispose, () {',
      );

      expect(closeBody, isNot(contains('await _createFuture')));
      expect(stopTrack, isNonNegative);
      expect(disposeStream, greaterThan(stopTrack));
      expect(closePeer, greaterThan(disposeStream));
      expect(disposePeer, greaterThan(closePeer));
      expect(
        RegExp(
          r'if \(connection != null && !_peerConnectionCloseCompleted\) \{\s*'
          r'await attempt\(connection\.close, \(\) \{\s*'
          r'_peerConnectionCloseCompleted = true;\s*'
          r'\}\);\s*'
          r'\}\s*'
          r'if \(connection != null &&\s*'
          r'_peerConnectionCloseCompleted &&\s*'
          r'!_peerConnectionDisposeCompleted\) \{\s*'
          r'await attempt\(connection\.dispose, \(\) \{\s*'
          r'_peerConnectionDisposeCompleted = true;\s*'
          r'\}\);',
        ).hasMatch(closeBody),
        isTrue,
        reason:
            'peer close and dispose must remain independently retryable, and '
            'dispose must wait for close to complete',
      );
      expect(
        closeBody,
        isNot(contains('await _releaseConnection(connection)')),
      );
    },
  );

  test(
    'adapter snapshot has one aggregate deadline around bounded metadata reads',
    () {
      final source = File(
        'lib/features/call/infrastructure/flutter_webrtc_call_engine.dart',
      ).readAsStringSync();
      final adapterStart = source.indexOf(
        'final class FlutterWebRtcPeerConnectionAdapter',
      );
      final adapterEnd = source.indexOf(
        'final class FlutterWebRtcCallEngine',
        adapterStart,
      );
      final snapshotStart = source.indexOf(
        '  Future<WebRtcPeerConnectionSnapshot> snapshot() {',
        adapterStart,
      );
      final snapshotOnceStart = source.indexOf(
        '  Future<WebRtcPeerConnectionSnapshot> _snapshotOnce(',
        snapshotStart,
      );
      final conservativeStart = source.indexOf(
        '  WebRtcPeerConnectionSnapshot _conservativeSnapshot()',
        snapshotOnceStart,
      );
      final conservativeEnd = source.indexOf(
        '  webrtc.RTCPeerConnection _requireConnection()',
        conservativeStart,
      );

      expect(adapterStart, isNonNegative);
      expect(adapterEnd, greaterThan(adapterStart));
      expect(snapshotStart, inInclusiveRange(adapterStart, adapterEnd - 1));
      expect(
        snapshotOnceStart,
        inInclusiveRange(snapshotStart + 1, adapterEnd - 1),
      );
      expect(
        conservativeStart,
        inInclusiveRange(snapshotOnceStart + 1, adapterEnd - 1),
      );
      expect(
        conservativeEnd,
        inInclusiveRange(conservativeStart + 1, adapterEnd - 1),
      );

      final snapshotBody = source.substring(snapshotStart, snapshotOnceStart);
      final snapshotOnceBody = source.substring(
        snapshotOnceStart,
        conservativeStart,
      );
      final conservativeBody = source.substring(
        conservativeStart,
        conservativeEnd,
      );

      expect(
        source,
        contains(
          'Duration snapshotDeadlineTimeout = const Duration(seconds: 6),',
        ),
      );
      expect(
        RegExp(r'runWithDeadlineFallback').allMatches(snapshotBody),
        hasLength(1),
      );
      expect(
        RegExp(
          r'runWithDeadlineFallback\(\s*'
          r'FlutterWebRtcFailureStage\.snapshotDeadline,\s*'
          r'\(\)\s*=>\s*_snapshotOnce\(connection\),\s*'
          r'timeout:\s*_snapshotDeadlineTimeout,\s*'
          r'onTimeout:\s*_conservativeSnapshot,',
        ).hasMatch(snapshotBody),
        isTrue,
      );
      expect(snapshotBody, isNot(contains('runWithTimeoutFallback')));
      expect(
        RegExp(r'runWithTimeoutFallback').allMatches(snapshotOnceBody),
        hasLength(5),
        reason: 'all five plugin metadata read groups must be bounded',
      );
      expect(
        RegExp(r'timeout:\s*_snapshotReadTimeout').allMatches(snapshotOnceBody),
        hasLength(5),
      );
      expect(
        RegExp(
          r'runWithTimeoutFallback\(\s*'
          r'FlutterWebRtcFailureStage\.snapshotSenders,\s*'
          r'connection\.getSenders,\s*'
          r'timeout:\s*_snapshotReadTimeout,\s*'
          r'onTimeout:\s*\(\)\s*=>\s*incomplete\(<webrtc\.RTCRtpSender>\[\]\),',
        ).hasMatch(snapshotOnceBody),
        isTrue,
      );
      expect(
        RegExp(
          r'runWithTimeoutFallback\(\s*'
          r'FlutterWebRtcFailureStage\.snapshotTransceivers,\s*'
          r'connection\.getTransceivers,\s*'
          r'timeout:\s*_snapshotReadTimeout,\s*'
          r'onTimeout:\s*\(\)\s*=>\s*incomplete\(<webrtc\.RTCRtpTransceiver>\[\]\),',
        ).hasMatch(snapshotOnceBody),
        isTrue,
      );
      expect(
        snapshotOnceBody,
        contains('FlutterWebRtcFailureStage.snapshotTransceiverDirection'),
      );
      expect(
        snapshotOnceBody,
        contains(
          'transceivers.map((transceiver) => transceiver.getDirection())',
        ),
      );
      expect(
        snapshotOnceBody,
        contains('List<webrtc.TransceiverDirection?>.filled('),
      );
      expect(
        snapshotOnceBody,
        matches(RegExp(r'transceivers\.length,\s*null,')),
      );
      expect(
        RegExp(
          r'runWithTimeoutFallback\(\s*'
          r'FlutterWebRtcFailureStage\.snapshotReceivers,\s*'
          r'connection\.getReceivers,\s*'
          r'timeout:\s*_snapshotReadTimeout,\s*'
          r'onTimeout:\s*\(\)\s*=>\s*incomplete\(<webrtc\.RTCRtpReceiver>\[\]\),',
        ).hasMatch(snapshotOnceBody),
        isTrue,
      );
      expect(
        RegExp(
          r'runWithTimeoutFallback\(\s*'
          r'FlutterWebRtcFailureStage\.snapshotStats,\s*'
          r'connection\.getStats,\s*'
          r'timeout:\s*_snapshotReadTimeout,\s*'
          r'onTimeout:\s*\(\)\s*=>\s*incomplete\(<webrtc\.StatsReport>\[\]\),',
        ).hasMatch(snapshotOnceBody),
        isTrue,
      );
      expect(
        RegExp(
          r'_failureStageGuard\s*\.\s*run(?:<[^>]+>)?\s*\(',
        ).hasMatch(snapshotOnceBody),
        isFalse,
        reason: 'snapshot metadata reads must not use an unbounded guard',
      );
      expect(snapshotOnceBody, isNot(contains('runWithDeadlineFallback')));
      expect(
        snapshotOnceBody,
        contains('if (!observationComplete) return _conservativeSnapshot();'),
      );

      for (final zeroField in const <String>[
        'localAudioCaptureTrackCount',
        'localVideoCaptureTrackCount',
        'audioReceiveTransceiverCount',
        'videoTransceiverCount',
      ]) {
        expect(
          conservativeBody,
          contains('$zeroField: 0'),
          reason: '$zeroField must fall back to zero',
        );
      }
      for (final defaultedField in const <String>[
        'transport',
        'quality',
        'selectedPairSucceeded',
        'selectedPairNominated',
        'selectedRelayProtocol',
        'dtlsReady',
        'localAudioSenderAttached',
        'localAudioTrackLive',
        'remoteAudioReceiverAttached',
        'remoteAudioTrackLive',
        'localAudioEnabled',
      ]) {
        expect(
          conservativeBody,
          isNot(contains('$defaultedField:')),
          reason:
              '$defaultedField must keep its conservative constructor default',
        );
      }

      const conservativeDefaults = WebRtcPeerConnectionSnapshot(
        isClosed: false,
        iceTransportPolicy: WebRtcIceTransportPolicy.relayOnly,
        localAudioCaptureTrackCount: 0,
        localVideoCaptureTrackCount: 0,
        audioReceiveTransceiverCount: 0,
        videoTransceiverCount: 0,
      );
      expect(conservativeDefaults.transport, WebRtcTransportClass.unknown);
      expect(conservativeDefaults.quality, WebRtcQualityBand.unknown);
      expect(conservativeDefaults.selectedPairSucceeded, isFalse);
      expect(conservativeDefaults.selectedPairNominated, isFalse);
      expect(
        conservativeDefaults.selectedRelayProtocol,
        WebRtcRelayProtocol.unknown,
      );
      expect(conservativeDefaults.dtlsReady, isFalse);
      expect(conservativeDefaults.localAudioSenderAttached, isFalse);
      expect(conservativeDefaults.localAudioTrackLive, isFalse);
      expect(conservativeDefaults.remoteAudioReceiverAttached, isFalse);
      expect(conservativeDefaults.remoteAudioTrackLive, isFalse);
      expect(conservativeDefaults.localAudioEnabled, isFalse);
    },
  );

  test(
    'VC2-01 event stream is coarse and retained diagnostics are bounded',
    () async {
      final observed = <CallEngineEvent>[];
      final subscription = engine.events.listen(observed.add);

      for (var index = 0; index < 64; index += 1) {
        adapter.emit(
          const WebRtcPeerConnectionEvent(
            kind: WebRtcPeerConnectionEventKind.statistics,
            connectionState: WebRtcConnectionState.connecting,
            transport: WebRtcTransportClass.relay,
            quality: WebRtcQualityBand.good,
            failureReason: WebRtcFailureReason.none,
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);

      // Capacity bounds retained history, not callbacks already consumed by
      // this synchronous listener. The old lifetime cutoff fabricated overflow.
      expect(observed, hasLength(64));
      expect(
        observed.any((event) => event.type == CallEngineEventType.overflow),
        isFalse,
      );
      expect(engine.recentEvents, hasLength(lessThanOrEqualTo(8)));

      const allowedKeys = <String>{
        'eventType',
        'connectionState',
        'transport',
        'quality',
        'failureReason',
      };
      final forbidden = RegExp(
        r'sdp|candidate|address|credential|username|password|peer.?id|secret|token',
        caseSensitive: false,
      );
      for (final event in engine.recentEvents) {
        final diagnostic = event.toDiagnosticMap();
        expect(diagnostic.keys.toSet().difference(allowedKeys), isEmpty);
        expect(forbidden.hasMatch(jsonEncode(diagnostic)), isFalse);
      }

      await subscription.cancel();
    },
  );

  test('VC2-01 all seven voice-call rollout flags default false', () {
    expect(defaultVoiceCallFeatureFlags(), const <String, bool>{
      'voice_call_capability_v1': false,
      'voice_call_outgoing_enabled': false,
      'voice_call_incoming_enabled': false,
      'voice_call_turn_enabled': false,
      'voice_call_android_native_enabled': false,
      'voice_call_ios_native_enabled': false,
      'voice_call_always_relay_enabled': false,
      'voice_call_force_relay_enabled': false,
    });
  });
}
