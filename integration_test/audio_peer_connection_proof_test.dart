@Tags(<String>['device'])
library;

import 'dart:convert';

import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'VC2-01 real adapter creates and closes a bare audio-only connection',
    () async {
      final adapter = FlutterWebRtcPeerConnectionAdapter(
        eventBufferCapacity: 16,
      );
      final CallEngine engine = FlutterWebRtcCallEngine(
        adapter: adapter,
        eventBufferCapacity: 16,
      );
      addTearDown(engine.close);

      await engine.createConnection(
        const CallConnectionConfiguration(
          transportPolicy: CallTransportPolicy.relayOnly,
          receiveAudio: true,
          receiveVideo: false,
          captureAudio: false,
          captureVideo: false,
        ),
      );

      final snapshot = await engine.snapshot();
      expect(snapshot.transportPolicy, CallTransportPolicy.relayOnly);
      expect(snapshot.transport, isNot(CallTransportClass.direct));
      expect(snapshot.localAudioCaptureTrackCount, 0);
      expect(snapshot.localVideoCaptureTrackCount, 0);
      expect(snapshot.audioReceiveTransceiverCount, 1);
      expect(snapshot.videoTransceiverCount, 0);

      final diagnostics = engine.recentEvents;
      expect(diagnostics, isNotEmpty);
      expect(diagnostics.length, lessThanOrEqualTo(16));

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
      for (final event in diagnostics) {
        final diagnostic = event.toDiagnosticMap();
        expect(diagnostic.keys.toSet().difference(allowedKeys), isEmpty);
        expect(forbidden.hasMatch(jsonEncode(diagnostic)), isFalse);
      }

      await engine.close();
      await engine.close();
      expect(engine.isClosed, isTrue);
      expect(adapter.isClosed, isTrue);
    },
  );
}
