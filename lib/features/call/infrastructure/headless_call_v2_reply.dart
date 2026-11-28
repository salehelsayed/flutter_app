import 'dart:math';

import 'package:uuid/uuid.dart';

import '../application/call_control_effect_executor.dart';
import '../application/call_signaling_context_store.dart';
import '../application/call_signaling_service.dart';
import '../application/headless_call_decline_reply.dart';
import '../application/incoming_call_pre_presentation_admission.dart';
import '../domain/call_end_reason.dart';
import '../domain/call_signal_v2.dart';
import 'production_call_v2_signaling_adapter.dart';

/// Sends one V2 control reply for an invite reauthenticated by the headless run.
final class HeadlessCallV2ReplyTransmitter {
  const HeadlessCallV2ReplyTransmitter({
    required CallSignalingService signalingService,
    required ResolveHeadlessCallEndpoint resolveEndpoint,
    required Future<bool> Function(String callHandle, int expiresAtMs)
    isNativeRinging,
    required String localAccountPeerId,
    required String localDevicePeerId,
    required Future<String> Function() loadSigningPrivateKey,
    required int Function() nowMs,
  }) : _signalingService = signalingService,
       _resolveEndpoint = resolveEndpoint,
       _isNativeRinging = isNativeRinging,
       _localAccountPeerId = localAccountPeerId,
       _localDevicePeerId = localDevicePeerId,
       _loadSigningPrivateKey = loadSigningPrivateKey,
       _nowMs = nowMs;

  final CallSignalingService _signalingService;
  final ResolveHeadlessCallEndpoint _resolveEndpoint;
  final Future<bool> Function(String callHandle, int expiresAtMs)
  _isNativeRinging;
  final String _localAccountPeerId;
  final String _localDevicePeerId;
  final Future<String> Function() _loadSigningPrivateKey;
  final int Function() _nowMs;

  Future<bool> sendRingingFor(AuthenticatedIncomingCallAdmissionV2 invite) =>
      _sendReply(
        invite,
        event: CallSignalV2Type.ringing,
        sequence: 1,
        payload: const {},
      );

  Future<bool> sendDeclineFor(AuthenticatedIncomingCallAdmissionV2 invite) =>
      _sendReply(
        invite,
        event: CallSignalV2Type.reject,
        sequence: 2,
        payload: {'reason': CallEndReason.declined.wireName},
      );

  Future<bool> _sendReply(
    AuthenticatedIncomingCallAdmissionV2 admission, {
    required CallSignalV2Type event,
    required int sequence,
    required Map<String, Object?> payload,
  }) async {
    final invite = admission.signal;
    final callHandle = admission.callHandle;
    final endpoint = admission.admittedEndpoint;
    if (invite.event != CallSignalV2Type.invite ||
        invite.recipientAccountPeerId != _localAccountPeerId ||
        invite.recipientDevicePeerId != _localDevicePeerId ||
        endpoint == null) {
      return false;
    }

    final now = _nowMs();
    final expiresAtMs = min(
      invite.expiresAtMs,
      now + CallControlEffectExecutor.defaultSignalLifetime.inMilliseconds,
    );
    if (expiresAtMs <= now) return false;

    final ringing = event == CallSignalV2Type.ringing;
    var closed = false;
    bool canApply() => !closed && _nowMs() < expiresAtMs;
    Future<bool> canReply() async {
      if (!canApply()) return false;
      return !ringing ||
          (await _isNativeRinging(callHandle, invite.expiresAtMs) &&
              canApply());
    }

    final contexts = CallSignalingContextStore(
      maxContexts: 1,
      videoEnabled: true,
    );
    final adapter = ProductionCallV2SignalingAdapter(
      signalingService: _signalingService,
      contextStore: contexts,
      resolveCurrentEndpoint: (accountPeerId) async {
        final current = await _resolveEndpoint(accountPeerId);
        // The adapter checks authority before sealing and again before either
        // transport leg. Recheck native ringing after each endpoint lookup.
        if (!await canReply()) {
          throw const CallSignalingException(
            CallSignalingErrorCode.endpointMismatch,
          );
        }
        return current;
      },
      loadSenderSigningPrivateKey: _loadSigningPrivateKey,
      nowMs: _nowMs,
      videoEnabled: true,
    );

    Future<bool> transmit() async {
      if (!await canReply()) return false;
      contexts.captureAuthenticatedV2(
        signal: invite,
        callHandle: callHandle,
        admissionAuthority: admission.admissionAuthority,
        admittedEndpoint: endpoint,
      );
      final signal = CallSignalV2.fromMap({
        'schema': CallSignalV2.schema,
        'call_id': invite.callId.value,
        'message_id': const Uuid().v4(),
        'event': event.wireName,
        'sender_account_peer_id': _localAccountPeerId,
        'sender_device_peer_id': _localDevicePeerId,
        'recipient_account_peer_id': invite.senderAccountPeerId,
        'recipient_device_peer_id': invite.senderDevicePeerId,
        'sender_sequence': sequence,
        'ice_generation': invite.iceGeneration,
        'created_at_ms': now,
        'expires_at_ms': expiresAtMs,
        'payload': payload,
      }, videoEnabled: true);
      final prepared = await adapter.prepare(
        signal: signal,
        callHandle: callHandle,
        admittedEndpoint: endpoint,
        canApply: canApply,
      );
      return (await prepared.transmit(canApply: canApply)).delivered;
    }

    try {
      return await transmit().timeout(
        Duration(milliseconds: expiresAtMs - now),
      );
    } catch (_) {
      return false;
    } finally {
      closed = true;
      adapter.close();
      contexts.purge(invite.callId);
    }
  }
}
