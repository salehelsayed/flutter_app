import 'package:uuid/uuid.dart';

import '../domain/call_id.dart';
import '../domain/call_signal.dart';
import 'headless_call_decline_reply.dart';

/// Sends a caller's authenticated ringing signal after the exact native
/// descriptor has been presented. A later foreground ringing signal uses the
/// same first local sequence and is ignored as a duplicate by the caller;
/// its subsequent accept advances to sequence two as before.
final class HeadlessCallRingingReplyTransmitter {
  HeadlessCallRingingReplyTransmitter({
    required TransmitCallSignal transmit,
    required ResolveHeadlessCallEndpoint resolveEndpoint,
    required Future<bool> Function(String callHandle, int expiresAtMs)
    isNativeRinging,
    required String localAccountPeerId,
    required String localDevicePeerId,
    required Future<String> Function() loadSigningPrivateKey,
    required int Function() nowMs,
    String Function()? messageIdSource,
    this.signalLifetime = const Duration(seconds: 40),
  }) : _transmit = transmit,
       _resolveEndpoint = resolveEndpoint,
       _isNativeRinging = isNativeRinging,
       _localAccountPeerId = localAccountPeerId,
       _localDevicePeerId = localDevicePeerId,
       _loadSigningPrivateKey = loadSigningPrivateKey,
       _nowMs = nowMs,
       _messageIdSource = messageIdSource ?? (() => const Uuid().v4());

  final TransmitCallSignal _transmit;
  final ResolveHeadlessCallEndpoint _resolveEndpoint;
  final Future<bool> Function(String callHandle, int expiresAtMs)
  _isNativeRinging;
  final String _localAccountPeerId;
  final String _localDevicePeerId;
  final Future<String> Function() _loadSigningPrivateKey;
  final int Function() _nowMs;
  final String Function() _messageIdSource;
  final Duration signalLifetime;

  Future<bool> sendRingingFor(
    CallSignal invite, {
    required String callHandle,
  }) async {
    if (invite.event != CallSignalType.invite ||
        invite.recipientAccountPeerId != _localAccountPeerId ||
        invite.recipientDevicePeerId != _localDevicePeerId ||
        CallId.tryParse(callHandle) == null ||
        callHandle == invite.callId.value) {
      return false;
    }
    try {
      final now = _nowMs();
      if (now >= invite.expiresAtMs ||
          !await _isNativeRinging(callHandle, invite.expiresAtMs)) {
        return false;
      }
      final endpoint = await _resolveEndpoint(invite.senderAccountPeerId);
      if (endpoint.accountPeerId != invite.senderAccountPeerId ||
          endpoint.devicePeerId != invite.senderDevicePeerId ||
          !await _isNativeRinging(callHandle, invite.expiresAtMs)) {
        return false;
      }
      final createdAt = _nowMs();
      final ringing = CallSignal.create(
        callId: invite.callId,
        messageId: _messageIdSource(),
        event: CallSignalType.ringing,
        senderAccountPeerId: _localAccountPeerId,
        senderDevicePeerId: _localDevicePeerId,
        recipientAccountPeerId: invite.senderAccountPeerId,
        recipientDevicePeerId: invite.senderDevicePeerId,
        senderSequence: 1,
        iceGeneration: invite.iceGeneration,
        createdAtMs: createdAt,
        expiresAtMs: createdAt + signalLifetime.inMilliseconds,
        payload: const <String, Object?>{},
      );
      final result = await _transmit(
        signal: ringing,
        callHandle: callHandle,
        endpoint: endpoint,
        senderSigningPrivateKey: await _loadSigningPrivateKey(),
      );
      return result.delivered;
    } catch (_) {
      return false;
    }
  }
}
