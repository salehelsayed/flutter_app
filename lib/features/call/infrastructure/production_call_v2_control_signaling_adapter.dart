import '../application/call_control_effect_executor.dart';
import '../application/call_endpoint_resolver.dart';
import '../application/call_signaling_context_store.dart';
import '../application/call_signaling_service.dart';
import '../domain/call_id.dart';
import '../domain/call_media.dart';
import '../domain/call_session_snapshot.dart';
import '../domain/call_signal.dart';
import '../domain/call_signal_v2.dart';
import '../domain/call_state.dart';
import 'p2p_call_transport.dart';
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
       _contexts = contextStore,
       _signaling = signalingAdapter,
       _resolve = resolveCurrentEndpoint,
       _outgoingMediaFor = outgoingMediaFor,
       _preparationCurrent = isOutgoingPreparationCurrent,
       _canSend = canSend,
       _nowMs = nowMs,
       _idSource = idSource,
       _videoEnabled = videoEnabled;

  final CallControlSignalingPort _legacy;
  final CallSignalingContextStore _contexts;
  final ProductionCallV2SignalingAdapter _signaling;
  final Future<ResolvedCallEndpoint> Function(String) _resolve;
  final CallMediaKind? Function(CallSessionSnapshot) _outgoingMediaFor;
  final bool Function(CallId) _preparationCurrent;
  final bool Function(CallSignalV2) _canSend;
  final int Function() _nowMs;
  final CallId Function() _idSource;
  final bool _videoEnabled;

  static const _preparationUnavailable = CallControlSignalingPortException(
    CallControlSignalingPortErrorCode.preparationUnavailable,
  );
  static const _endpointMismatch = CallControlSignalingPortException(
    CallControlSignalingPortErrorCode.endpointMismatch,
  );
  static const _transportUnavailable = CallControlSignalingPortException(
    CallControlSignalingPortErrorCode.transportUnavailable,
  );

  @override
  Future<OutgoingCallSignalingPreparation> prepareOutgoingInvite(
    CallSessionSnapshot snapshot,
  ) async {
    try {
      final media = _outgoingMediaFor(snapshot);
      if (media == null) return await _legacy.prepareOutgoingInvite(snapshot);
      final callId = snapshot.callId;
      final account = snapshot.contactPeerId;
      if (!_videoEnabled ||
          callId == null ||
          !_validIdentity(account) ||
          !_validIdentity(snapshot.callerAccountPeerId) ||
          !_validIdentity(snapshot.callerDeviceId) ||
          snapshot.direction != CallDirection.outgoing ||
          snapshot.state != CallState.preparing ||
          !_preparationCurrent(callId)) {
        throw _preparationUnavailable;
      }
      final endpoint = ResolvedCallEndpoint.frozen(await _resolve(account!));
      final now = _nowMs();
      if (!_preparationCurrent(callId) ||
          _outgoingMediaFor(snapshot) != media) {
        throw _preparationUnavailable;
      }
      if (endpoint.accountPeerId != account ||
          !_validIdentity(endpoint.devicePeerId) ||
          endpoint.expiresAtMs <= now ||
          !endpoint.capabilities.contains(
            CallEndpointResolver.voiceCapability,
          ) ||
          !endpoint.capabilities.contains('video_call_v2')) {
        throw _endpointMismatch;
      }
      final handle = _idSource().value;
      final messageId = _idSource().value;
      if (handle == callId.value ||
          messageId == callId.value ||
          handle == messageId) {
        throw _preparationUnavailable;
      }
      final normalExpiry =
          now + CallControlEffectExecutor.defaultSignalLifetime.inMilliseconds;
      final invite = CallSignalV2.fromMap({
        'schema': CallSignalV2.schema,
        'call_id': callId.value,
        'message_id': messageId,
        'event': 'invite',
        'sender_account_peer_id': snapshot.callerAccountPeerId,
        'sender_device_peer_id': snapshot.callerDeviceId,
        'recipient_account_peer_id': endpoint.accountPeerId,
        'recipient_device_peer_id': endpoint.devicePeerId,
        'sender_sequence': 1,
        'ice_generation': 0,
        'created_at_ms': now,
        'expires_at_ms': endpoint.expiresAtMs < normalExpiry
            ? endpoint.expiresAtMs
            : normalExpiry,
        'payload': {
          'media': media.name,
          'camera': 'off',
          'capabilities': ['audio', 'video'],
        },
      }, videoEnabled: true);
      // No await between the final owner check and atomic context custody.
      // The effect executor's idempotent store preserves this first snapshot;
      // cancellation at its return/native boundary purges the entire context.
      if (!_preparationCurrent(callId) || invite.expiresAtMs <= _nowMs()) {
        throw _preparationUnavailable;
      }
      _contexts.storeOutgoingV2(
        invite: invite,
        callHandle: handle,
        admissionAuthority: endpoint.admissionAuthority,
        admittedEndpoint: endpoint,
      );
      return OutgoingCallSignalingPreparation.v2(
        callHandle: handle,
        invite: invite,
        admissionAuthority: endpoint.admissionAuthority,
      );
    } on CallControlSignalingPortException {
      rethrow;
    } catch (_) {
      throw _preparationUnavailable;
    }
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
  }) async {
    try {
      if (!_videoEnabled ||
          !_canSend(signal) ||
          !const {
            CallSignalV2Type.invite,
            CallSignalV2Type.ringing,
            CallSignalV2Type.accept,
            CallSignalV2Type.reject,
            CallSignalV2Type.terminate,
          }.contains(signal.event)) {
        throw _transportUnavailable;
      }
      // A later lookup, including a legacy fallback pin, cannot manufacture
      // the original admission authority of an existing call.
      final original = _contexts.admittedV2Endpoint(signal.callId);
      if (original == null) throw _endpointMismatch;
      bool canApply() => _canSend(signal);
      final prepared = await _signaling.prepare(
        signal: signal,
        callHandle: callHandle,
        admittedEndpoint: original,
        canApply: canApply,
      );
      final result = await prepared.transmit(canApply: canApply);
      return CallControlSendResult(
        directAccepted: result.directAccepted,
        mailboxStored: result.mailboxStored,
        wakeDispatched: result.wakeDispatched,
        directRoute: switch (result.directRoute) {
          CallDirectRoute.direct => CallRouteClass.direct,
          CallDirectRoute.circuitRelay => CallRouteClass.circuitRelay,
          CallDirectRoute.unknown => null,
        },
        mailboxStoreSettled: result.mailboxStoreSettled,
      );
    } on CallControlSignalingPortException {
      rethrow;
    } on CallSignalingException catch (error) {
      throw error.code == CallSignalingErrorCode.endpointMismatch
          ? _endpointMismatch
          : _transportUnavailable;
    } catch (_) {
      throw _transportUnavailable;
    }
  }

  static bool _validIdentity(String? value) =>
      value != null &&
      value.isNotEmpty &&
      value.trim() == value &&
      value.length <= 512;
}
