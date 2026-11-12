import '../domain/call_engine.dart';
import '../domain/call_event.dart';
import '../domain/call_id.dart';
import '../domain/call_media.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_signal_v2.dart';
import '../domain/call_state.dart';
import 'call_coordinator.dart';
import 'call_endpoint_resolver.dart';
import 'call_negotiation_effect_executor.dart';
import 'call_signaling_context_store.dart';
import 'handle_incoming_call_signal.dart';

/// The production binding uses ProductionCallV2SignalingAdapter.prepare and
/// the resulting immutable transmission. True means direct or mailbox custody;
/// a wake request alone is not delivery. No camera consent crosses this seam.
typedef SendCallV2MediaSignal =
    Future<bool> Function({
      required CallSignalV2 signal,
      required String callHandle,
      required ResolvedCallEndpoint admittedEndpoint,
      required bool Function() canApply,
    });

/// One call's initial v2 SDP/ICE owner. The legacy executor retains microphone,
/// engine-event and v1 ownership; its single candidate listener routes here.
final class CallV2NegotiationEffectExecutor implements CallEffectExecutor {
  CallV2NegotiationEffectExecutor({
    required this.callId,
    required this.legacy,
    required this.videoEngine,
    required this.contexts,
    required this.resolveEndpoint,
    required this.sendSignal,
    required this.canApply,
    required this.idSource,
    this.videoEnabled = false,
    this.maxPendingMedia = 64,
    this.monotonicNowMs,
    this.timerScheduler = const DartCallTimerScheduler(),
  });

  final CallId callId;
  final CallNegotiationEffectExecutor legacy;
  final CallVideoEngine videoEngine;
  final CallSignalingContextStore contexts;
  final Future<ResolvedCallEndpoint> Function(String) resolveEndpoint;
  final SendCallV2MediaSignal sendSignal;
  final bool Function() canApply;
  final String Function() idSource;
  final bool videoEnabled;
  final int maxPendingMedia;
  final int Function()? monotonicNowMs;
  final CallTimerScheduler timerScheduler;

  CallVideoSession? get videoSession => null;
  CallVideoNegotiation? get negotiation => null;

  /// Completes after the currently adopted work and canonical dispatch settle.
  Future<void> get workSettled async {}

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    if (contexts.read(callId)?.wireVersion == CallWireVersion.v1) {
      return await legacy.execute(effect, snapshot);
    }
    return null;
  }

  IncomingCallSignalOutcome handleAuthenticated({
    required CallSignalV2 signal,
    required String callHandle,
    required bool Function() canApply,
  }) => IncomingCallSignalOutcome.rejected;

  /// True takes custody (including a deliberate stale discard), preventing a
  /// v2 candidate from reaching the legacy sender.
  bool consumeLocalCandidate(
    CallSessionSnapshot snapshot,
    CallIceCandidate candidate,
  ) => false;

  Future<void> close() => legacy.close();
}
