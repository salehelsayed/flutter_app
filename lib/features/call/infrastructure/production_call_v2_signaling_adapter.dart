import '../application/call_endpoint_resolver.dart';
import '../application/call_signaling_context_store.dart';
import '../application/call_signaling_service.dart';
import '../domain/call_id.dart';
import '../domain/call_signal_v2.dart';
import 'production_call_signaling_adapters.dart';

/// Owns one immutable v2 message's preparation and bounded transport custody.
/// The canonical call/media owner supplies the admission and lifetime fence.
final class ProductionCallV2SignalingAdapter {
  ProductionCallV2SignalingAdapter({
    required CallSignalingService signalingService,
    required CallSignalingContextStore contextStore,
    required ResolveCurrentCallEndpoint resolveCurrentEndpoint,
    required LoadCallSenderSigningPrivateKey loadSenderSigningPrivateKey,
    required int Function() nowMs,
    bool videoEnabled = false,
  });

  Future<PreparedCallV2Signal> prepare({
    required CallSignalV2 signal,
    required String callHandle,
    required ResolvedCallEndpoint admittedEndpoint,
    required bool Function() canApply,
  }) => Future<PreparedCallV2Signal>.error(
    const CallSignalingException(CallSignalingErrorCode.migrationPaused),
  );

  /// Retires optional/control work while preserving an already-owned terminal.
  void retireCall(CallId callId) {}

  void close() {}
}

/// A prepared signal never dispatches delivery receipts into the call reducer.
final class PreparedCallV2Signal {
  bool get isAvailable => false;

  Future<CallSignalTransportResult> transmit({
    required bool Function() canApply,
  }) => Future<CallSignalTransportResult>.error(
    const CallSignalingException(CallSignalingErrorCode.transportUnavailable),
  );

  void close() {}
}
