import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/composite_call_effect_executor.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Recording implements CallEffectExecutor {
  final List<CallEffectType> effects = <CallEffectType>[];

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    effects.add(effect.type);
    return null;
  }
}

void main() {
  final snapshot = CallSessionSnapshot.active(
    callId: CallId.parse('55555555-5555-4555-8555-555555555555'),
    contactPeerId: 'contact-a',
    direction: CallDirection.outgoing,
    state: CallState.reconnecting,
    callerAccountPeerId: 'local-account',
    callerDeviceId: 'local-device',
    startedAt: DateTime.utc(2026, 10, 16, 12),
  );

  test('every negotiation effect, including the relay-ready resume, reaches '
      'the negotiation executor', () async {
    final control = _Recording();
    final negotiation = _Recording();
    final composite = CompositeCallEffectExecutor(
      controlExecutor: control,
      negotiationExecutor: negotiation,
    );
    const negotiationEffects = <CallEffectType>[
      CallEffectType.prepareAcceptedMedia,
      CallEffectType.startNegotiation,
      CallEffectType.deliverOffer,
      CallEffectType.deliverAnswer,
      CallEffectType.queueIceCandidate,
      CallEffectType.restartIce,
      CallEffectType.requestIceRestart,
      CallEffectType.resumeRecoverySignals,
    ];

    for (final type in negotiationEffects) {
      await composite.execute(CallEffect(type), snapshot);
    }

    expect(negotiation.effects, negotiationEffects);
    expect(control.effects, isEmpty);
  });

  test('control effects reach the control executor only', () async {
    final control = _Recording();
    final negotiation = _Recording();
    final composite = CompositeCallEffectExecutor(
      controlExecutor: control,
      negotiationExecutor: negotiation,
    );
    const controlEffects = <CallEffectType>[
      CallEffectType.prepareOutgoingInvite,
      CallEffectType.validateIncomingInvite,
      CallEffectType.presentIncomingCall,
      CallEffectType.sendInvite,
      CallEffectType.sendRinging,
      CallEffectType.sendAccept,
      CallEffectType.sendReject,
      CallEffectType.sendTerminate,
      CallEffectType.sendBusy,
    ];

    for (final type in controlEffects) {
      await composite.execute(CallEffect(type), snapshot);
    }

    expect(control.effects, controlEffects);
    expect(negotiation.effects, isEmpty);
  });

  test('coordinator-owned effects reach neither executor', () async {
    final control = _Recording();
    final negotiation = _Recording();
    final composite = CompositeCallEffectExecutor(
      controlExecutor: control,
      negotiationExecutor: negotiation,
    );

    for (final type in const <CallEffectType>[
      CallEffectType.scheduleNoAnswerTimeout,
      CallEffectType.scheduleInviteExpiry,
      CallEffectType.scheduleNegotiationTimeout,
      CallEffectType.scheduleReconnectTimeout,
      CallEffectType.cancelTimers,
      CallEffectType.cleanup,
      CallEffectType.projectHistory,
    ]) {
      expect(await composite.execute(CallEffect(type), snapshot), isNull);
    }

    expect(control.effects, isEmpty);
    expect(negotiation.effects, isEmpty);
  });
}
