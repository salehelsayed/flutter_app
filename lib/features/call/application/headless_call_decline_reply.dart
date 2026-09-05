import 'package:uuid/uuid.dart';

import '../domain/call_end_reason.dart';
import '../domain/call_signal.dart';
import 'call_endpoint_resolver.dart';
import 'call_signaling_service.dart';

/// The transport write of [CallSignalingService.transmit].
typedef TransmitCallSignal =
    Future<CallSignalTransportResult> Function({
      required CallSignal signal,
      required String callHandle,
      required ResolvedCallEndpoint endpoint,
      required String senderSigningPrivateKey,
    });

typedef ResolveHeadlessCallEndpoint =
    Future<ResolvedCallEndpoint> Function(String contactAccountPeerId);

/// Plan 404: answers a natively declined call whose process had no Dart owner
/// (Android app killed, call presented and declined headlessly). Device
/// 2026-09-05 17:44Z: nothing reached the caller, whose ringback played until
/// its own cancel. From the authenticated invite this builds the callee's one
/// `reject` (reason `declined`, first sender sequence, the invite's ICE
/// generation, the standard 40 s lifetime) and writes it through the same
/// direct-plus-mailbox transport the foreground uses.
final class HeadlessCallDeclineReplyTransmitter {
  HeadlessCallDeclineReplyTransmitter({
    required TransmitCallSignal transmit,
    required ResolveHeadlessCallEndpoint resolveEndpoint,
    required String localAccountPeerId,
    required String localDevicePeerId,
    required Future<String> Function() loadSigningPrivateKey,
    required int Function() nowMs,
    String Function()? messageIdSource,
    this.signalLifetime = const Duration(seconds: 40),
  }) : _transmit = transmit,
       _resolveEndpoint = resolveEndpoint,
       _localAccountPeerId = localAccountPeerId,
       _localDevicePeerId = localDevicePeerId,
       _loadSigningPrivateKey = loadSigningPrivateKey,
       _nowMs = nowMs,
       _messageIdSource = messageIdSource ?? _newMessageId;

  final TransmitCallSignal _transmit;
  final ResolveHeadlessCallEndpoint _resolveEndpoint;
  final String _localAccountPeerId;
  final String _localDevicePeerId;
  final Future<String> Function() _loadSigningPrivateKey;
  final int Function() _nowMs;
  final String Function() _messageIdSource;
  final Duration signalLifetime;

  static String _newMessageId() => const Uuid().v4();

  /// Resolves true once the reject reached custody (direct acceptance or
  /// mailbox store). Only an invite addressed to this exact device is
  /// answered, and only while the caller's current endpoint is still the
  /// inviting device. Never throws.
  Future<bool> sendDeclineFor(CallSignal invite) async {
    if (invite.event != CallSignalType.invite ||
        invite.recipientAccountPeerId != _localAccountPeerId ||
        invite.recipientDevicePeerId != _localDevicePeerId) {
      return false;
    }
    try {
      final endpoint = await _resolveEndpoint(invite.senderAccountPeerId);
      if (endpoint.accountPeerId != invite.senderAccountPeerId ||
          endpoint.devicePeerId != invite.senderDevicePeerId) {
        return false;
      }
      final now = _nowMs();
      final reject = CallSignal.create(
        callId: invite.callId,
        messageId: _messageIdSource(),
        event: CallSignalType.reject,
        senderAccountPeerId: _localAccountPeerId,
        senderDevicePeerId: _localDevicePeerId,
        recipientAccountPeerId: invite.senderAccountPeerId,
        recipientDevicePeerId: invite.senderDevicePeerId,
        senderSequence: 1,
        iceGeneration: invite.iceGeneration,
        createdAtMs: now,
        expiresAtMs: now + signalLifetime.inMilliseconds,
        payload: <String, Object?>{'reason': CallEndReason.declined.wireName},
      );
      final result = await _transmit(
        signal: reject,
        callHandle: invite.callId.value,
        endpoint: endpoint,
        senderSigningPrivateKey: await _loadSigningPrivateKey(),
      );
      return result.delivered;
    } catch (_) {
      return false;
    }
  }
}
