import '../domain/call_event.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_state.dart';
import 'call_coordinator.dart';

/// Routes one effect to exactly one side-effect executor. It owns no state,
/// dispatch loop, or reducer and therefore cannot create a second call lane.
final class CompositeCallEffectExecutor implements CallEffectExecutor {
  const CompositeCallEffectExecutor({
    required this.controlExecutor,
    required this.negotiationExecutor,
  });

  final CallEffectExecutor controlExecutor;
  final CallEffectExecutor negotiationExecutor;

  @override
  Future<CallEvent?> execute(CallEffect effect, CallSessionSnapshot snapshot) {
    if (_controlEffects.contains(effect.type)) {
      return controlExecutor.execute(effect, snapshot);
    }
    if (_negotiationEffects.contains(effect.type)) {
      return negotiationExecutor.execute(effect, snapshot);
    }
    return Future<CallEvent?>.value();
  }

  static const Set<CallEffectType> _controlEffects = <CallEffectType>{
    CallEffectType.prepareOutgoingInvite,
    CallEffectType.validateIncomingInvite,
    CallEffectType.presentIncomingCall,
    CallEffectType.sendInvite,
    CallEffectType.sendRinging,
    CallEffectType.sendAccept,
    CallEffectType.sendReject,
    CallEffectType.sendTerminate,
    CallEffectType.sendBusy,
  };

  static const Set<CallEffectType> _negotiationEffects = <CallEffectType>{
    CallEffectType.prepareAcceptedMedia,
    CallEffectType.deliverOffer,
    CallEffectType.deliverAnswer,
    CallEffectType.queueIceCandidate,
    CallEffectType.restartIce,
    CallEffectType.requestIceRestart,
    CallEffectType.startNegotiation,
  };
}
