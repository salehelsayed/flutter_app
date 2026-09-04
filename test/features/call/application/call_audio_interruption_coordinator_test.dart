import 'dart:async';

import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_audio_interruption_coordinator.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 8, 30, 12);
final _callId = CallId.parse('88888888-8888-4888-8888-888888888888');

CallSessionSnapshot _session(CallState state) => CallSessionSnapshot.active(
  callId: _callId,
  contactPeerId: 'contact',
  direction: CallDirection.outgoing,
  state: state,
  callerAccountPeerId: 'local',
  callerDeviceId: 'local-device',
  startedAt: _now,
  observedAt: _now,
  acceptedAt: _now,
);

CallConnectionSnapshot _media({required bool ready}) => CallConnectionSnapshot(
  state: CallConnectionState.connected,
  transportPolicy: CallTransportPolicy.all,
  transport: CallTransportClass.direct,
  quality: CallQualityBand.good,
  localAudioCaptureTrackCount: 1,
  localVideoCaptureTrackCount: 0,
  audioReceiveTransceiverCount: 1,
  videoTransceiverCount: 0,
  selectedPairSucceeded: ready,
  selectedPairNominated: ready,
  dtlsReady: ready,
  audioSessionActive: ready,
  localAudioSenderAttached: ready,
  localAudioTrackLive: ready,
  remoteAudioReceiverAttached: ready,
  remoteAudioTrackLive: ready,
  localAudioEnabled: false,
);

Future<void> _flush() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'focus loss and ready recovery use canonical reconnect events',
    () async {
      final intents = StreamController<CallAudioInterruptionIntent>.broadcast(
        sync: true,
      );
      var session = _session(CallState.connected);
      final events = <CallEvent>[];
      final bridge = CallAudioInterruptionCoordinator(
        intents: intents.stream,
        readActiveSession: () => session,
        readMediaSnapshot: () async => _media(ready: true),
        dispatchEvent: (event) async {
          events.add(event);
        },
        clock: () => _now,
      );
      addTearDown(() async {
        await bridge.close();
        await intents.close();
      });

      intents.add(CallAudioInterruptionIntent.pausedReconnect);
      await _flush();
      session = _session(CallState.reconnecting);
      intents.add(CallAudioInterruptionIntent.recover);
      await _flush();

      expect(events.map((event) => event.type), <CallEventType>[
        CallEventType.mediaLost,
        CallEventType.mediaRecovered,
      ]);
    },
  );

  test(
    'recovery never connects from UI intent without media readiness',
    () async {
      final intents = StreamController<CallAudioInterruptionIntent>.broadcast(
        sync: true,
      );
      final events = <CallEvent>[];
      final bridge = CallAudioInterruptionCoordinator(
        intents: intents.stream,
        readActiveSession: () => _session(CallState.negotiating),
        readMediaSnapshot: () async => _media(ready: false),
        dispatchEvent: (event) async => events.add(event),
        clock: () => _now,
      );
      addTearDown(() async {
        await bridge.close();
        await intents.close();
      });

      intents.add(CallAudioInterruptionIntent.recover);
      await _flush();

      expect(events, isEmpty);
    },
  );

  test('close fences later interruption events', () async {
    final intents = StreamController<CallAudioInterruptionIntent>.broadcast(
      sync: true,
    );
    final events = <CallEvent>[];
    final bridge = CallAudioInterruptionCoordinator(
      intents: intents.stream,
      readActiveSession: () => _session(CallState.connected),
      readMediaSnapshot: () async => _media(ready: true),
      dispatchEvent: (event) async => events.add(event),
      clock: () => _now,
    );

    await bridge.close();
    intents.add(CallAudioInterruptionIntent.pausedReconnect);
    await _flush();
    await intents.close();

    expect(events, isEmpty);
  });

  test('close never waits on a reducer dispatch already in flight', () async {
    final intents = StreamController<CallAudioInterruptionIntent>.broadcast(
      sync: true,
    );
    final dispatchStarted = Completer<void>();
    final dispatchGate = Completer<void>();
    final bridge = CallAudioInterruptionCoordinator(
      intents: intents.stream,
      readActiveSession: () => _session(CallState.connected),
      readMediaSnapshot: () async => _media(ready: true),
      dispatchEvent: (event) async {
        dispatchStarted.complete();
        await dispatchGate.future;
      },
      clock: () => _now,
    );
    addTearDown(() async {
      if (!dispatchGate.isCompleted) dispatchGate.complete();
      await intents.close();
    });

    intents.add(CallAudioInterruptionIntent.pausedReconnect);
    await dispatchStarted.future;
    await bridge.close().timeout(const Duration(milliseconds: 100));
    dispatchGate.complete();
    await _flush();
  });
}
