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
/// direct-plus-mailbox transport the foreground uses, under the invite's
/// mailbox handle.
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

  /// The mailbox handle grammar (canonical UUID v4), as the envelope codec
  /// enforces it.
  static final RegExp _callHandleGrammar = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  /// Resolves true once the reject reached custody (direct acceptance or
  /// mailbox store). Only an invite addressed to this exact device is
  /// answered, and only while the caller's current endpoint is still the
  /// inviting device. [callHandle] is the mailbox handle the invite row was
  /// retrieved under: the caller minted it apart from the call id and keys
  /// its context by it, so a reply under the call id is dropped unseen
  /// (device 2026-09-05 18:23Z). Never throws.
  Future<bool> sendDeclineFor(
    CallSignal invite, {
    required String callHandle,
  }) async {
    if (invite.event != CallSignalType.invite ||
        invite.recipientAccountPeerId != _localAccountPeerId ||
        invite.recipientDevicePeerId != _localDevicePeerId ||
        !_callHandleGrammar.hasMatch(callHandle) ||
        callHandle == invite.callId.value) {
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
