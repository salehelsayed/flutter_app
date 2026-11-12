import '../application/call_control_effect_executor.dart';
import '../application/call_endpoint_resolver.dart';
import '../application/call_signaling_context_store.dart';
import '../domain/call_id.dart';
import '../domain/call_media.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_signal.dart';
import '../domain/call_signal_v2.dart';
import 'production_call_v2_signaling_adapter.dart';

/// Production control bridge for explicitly selected v2 calls.
/// A null media choice delegates ordinary audio preparation to the v1 port.
/// The canonical owner supplies both preparation and signal lifetime fences;
/// a terminal fence must retain only its original call's delivery authority.
final class ProductionCallV2ControlSignalingAdapter
    implements CallControlSignalingPortV2 {
  ProductionCallV2ControlSignalingAdapter({
    required CallControlSignalingPort legacyPort,
    required CallSignalingContextStore contextStore,
    required ProductionCallV2SignalingAdapter signalingAdapter,
    required Future<ResolvedCallEndpoint> Function(String accountPeerId)
    resolveCurrentEndpoint,
    required CallMediaKind? Function(CallSessionSnapshot snapshot)
    outgoingMediaFor,
    required bool Function(CallId callId) isOutgoingPreparationCurrent,
    required bool Function(CallSignalV2 signal) canSend,
    required int Function() nowMs,
    required CallId Function() idSource,
    bool videoEnabled = false,
  }) : _legacy = legacyPort,
       _outgoingMediaFor = outgoingMediaFor;

  final CallControlSignalingPort _legacy;
  final CallMediaKind? Function(CallSessionSnapshot) _outgoingMediaFor;

  @override
  Future<OutgoingCallSignalingPreparation> prepareOutgoingInvite(
    CallSessionSnapshot snapshot,
  ) async {
    if (_outgoingMediaFor(snapshot) == null) {
      return _legacy.prepareOutgoingInvite(snapshot);
    }
    throw const CallControlSignalingPortException(
      CallControlSignalingPortErrorCode.preparationUnavailable,
    );
  }

  @override
  Future<CallControlSendResult> send({
    required CallSignal signal,
    required String callHandle,
  }) => _legacy.send(signal: signal, callHandle: callHandle);

  @override
  Future<CallControlSendResult> sendV2({
    required CallSignalV2 signal,
    required String callHandle,
  }) async => throw const CallControlSignalingPortException(
    CallControlSignalingPortErrorCode.transportUnavailable,
  );
}
