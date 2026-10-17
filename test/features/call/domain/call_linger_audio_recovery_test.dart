import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reducer = CallReducer();
  final id = CallId.parse('11111111-1111-4111-8111-111111111111');
  final now = DateTime.utc(2026, 10, 16);
  CallEvent event(CallEventType type, {int? epoch}) => CallEvent(
    type: type,
    eventId: 'linger-${type.name}',
    occurredAt: now,
    callId: id,
    pathEpoch: epoch,
  );
  for (final direction in CallDirection.values) {
    for (final signal in [
      CallEventType.mediaLost,
      CallEventType.networkPreviousPathLost,
    ]) {
      test('${direction.name} ${signal.name} upgrades an audio-only reconnect '
          'to transport recovery', () {
        var session = CallSessionSnapshot.active(
          callId: id,
          contactPeerId: 'contact',
          direction: direction,
          state: CallState.connected,
          callerAccountPeerId: 'caller',
          callerDeviceId: 'caller-device',
          startedAt: now,
          acceptedAt: now,
          connectedAt: now,
        );
        session = reducer
            .reduce(session, event(CallEventType.networkPathChanged, epoch: 7))
            .snapshot;
        session = reducer
            .reduce(session, event(CallEventType.networkPathReady, epoch: 7))
            .snapshot;
        session = reducer
            .reduce(session, event(CallEventType.mediaRecovered))
            .snapshot;
        expect(session.state, CallState.connected);
        expect(session.readyPathEpoch, 7);
        final audioOnly = reducer
            .reduce(session, event(CallEventType.audioInterrupted))
            .snapshot;
        expect(audioOnly.state, CallState.reconnecting);
        expect(audioOnly.transportRecoveryRequired, isFalse);

        final lost = reducer.reduce(audioOnly, event(signal, epoch: 7));

        expect(
          lost.snapshot.reconnectGeneration,
          audioOnly.reconnectGeneration,
        );
        expect(
          lost.effects.map((e) => e.type).toList(),
          [
            direction == CallDirection.incoming
                ? CallEffectType.requestIceRestart
                : CallEffectType.restartIce,
          ],
          reason:
              'network teardown must start transport recovery when none is '
              'in flight, keeping the existing timer',
        );
        expect(lost.snapshot.transportRecoveryRequired, isTrue);
      });
    }
  }
}
