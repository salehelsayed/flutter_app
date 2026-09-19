import 'dart:async';

import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_audio_interruption_coordinator.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 8, 30, 12);
final _callId = CallId.parse('88888888-8888-4888-8888-888888888888');

CallSessionSnapshot _session(CallState state, {CallId? callId}) =>
    CallSessionSnapshot.active(
      callId: callId ?? _callId,
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
        dispatchEvent: (event, {canApply}) async {
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
        dispatchEvent: (event, {canApply}) async => events.add(event),
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

  test('a newer focus loss invalidates an in-flight ready recovery', () async {
    final intents = StreamController<CallAudioInterruptionIntent>.broadcast(
      sync: true,
    );
    final readinessStarted = Completer<void>();
    final readiness = Completer<CallConnectionSnapshot>();
    final events = <CallEvent>[];
    var reads = 0;
    final bridge = CallAudioInterruptionCoordinator(
      intents: intents.stream,
      readActiveSession: () => _session(CallState.reconnecting),
      readMediaSnapshot: () {
        if (reads++ == 0) {
          readinessStarted.complete();
          return readiness.future;
        }
        return Future.value(_media(ready: true));
      },
      dispatchEvent: (event, {canApply}) async => events.add(event),
      clock: () => _now,
    );
    addTearDown(() async {
      await bridge.close();
      await intents.close();
    });

    intents.add(CallAudioInterruptionIntent.recover);
    await readinessStarted.future;
    intents.add(CallAudioInterruptionIntent.pausedReconnect);
    readiness.complete(_media(ready: true));
    await _flush();

    expect(events, isEmpty, reason: 'the ready result predates the new loss');

    intents.add(CallAudioInterruptionIntent.recover);
    await _flush();
    expect(events.map((event) => event.type), <CallEventType>[
      CallEventType.mediaRecovered,
    ]);
  });

  for (final replacement in <CallSessionSnapshot>[
    _session(CallState.connected),
    _session(CallState.reconnecting).copyWith(reconnectGeneration: 1),
    _session(CallState.reconnecting).copyWith(
      state: CallState.ended,
      endedAt: _now,
      endReason: CallEndReason.reconnectFailed,
    ),
    _session(
      CallState.reconnecting,
      callId: CallId.parse('99999999-9999-4999-8999-999999999999'),
    ),
  ]) {
    test('an async recovery cannot outlive its call or phase: '
        '${replacement.callId}/${replacement.state}/'
        '${replacement.reconnectGeneration}', () async {
      final intents = StreamController<CallAudioInterruptionIntent>.broadcast(
        sync: true,
      );
      final readinessStarted = Completer<void>();
      final readiness = Completer<CallConnectionSnapshot>();
      var session = _session(CallState.reconnecting);
      final events = <CallEvent>[];
      final bridge = CallAudioInterruptionCoordinator(
        intents: intents.stream,
        readActiveSession: () => session,
        readMediaSnapshot: () {
          readinessStarted.complete();
          return readiness.future;
        },
        dispatchEvent: (event, {canApply}) async => events.add(event),
        clock: () => _now,
      );
      addTearDown(() async {
        await bridge.close();
        await intents.close();
      });

      intents.add(CallAudioInterruptionIntent.recover);
      await readinessStarted.future;
      session = replacement;
      readiness.complete(_media(ready: true));
      await _flush();

      expect(events, isEmpty);
    });
  }

  test('a newer focus loss invalidates a queued recovery dispatch', () async {
    final intents = StreamController<CallAudioInterruptionIntent>.broadcast(
      sync: true,
    );
    final dispatchStarted = Completer<void>();
    final dispatchGate = Completer<void>();
    final events = <CallEvent>[];
    final bridge = CallAudioInterruptionCoordinator(
      intents: intents.stream,
      readActiveSession: () => _session(CallState.reconnecting),
      readMediaSnapshot: () async => _media(ready: true),
      dispatchEvent: (event, {bool Function()? canApply}) async {
        dispatchStarted.complete();
        await dispatchGate.future;
        if (canApply?.call() ?? true) events.add(event);
      },
      clock: () => _now,
    );
    addTearDown(() async {
      if (!dispatchGate.isCompleted) dispatchGate.complete();
      await bridge.close();
      await intents.close();
    });

    intents.add(CallAudioInterruptionIntent.recover);
    await dispatchStarted.future;
    intents.add(CallAudioInterruptionIntent.pausedReconnect);
    dispatchGate.complete();
    await _flush();

    expect(events, isEmpty);
  });

  test('close fences later interruption events', () async {
    final intents = StreamController<CallAudioInterruptionIntent>.broadcast(
      sync: true,
    );
    final events = <CallEvent>[];
    final bridge = CallAudioInterruptionCoordinator(
      intents: intents.stream,
      readActiveSession: () => _session(CallState.connected),
      readMediaSnapshot: () async => _media(ready: true),
      dispatchEvent: (event, {canApply}) async => events.add(event),
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
      dispatchEvent: (event, {canApply}) async {
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
