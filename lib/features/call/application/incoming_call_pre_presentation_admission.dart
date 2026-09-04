import '../domain/call_id.dart';
import '../domain/call_signal.dart';
import '../infrastructure/call_mailbox_client.dart';
import '../infrastructure/call_trusted_roster_provider.dart';
import '../infrastructure/secure_call_envelope_codec.dart';
import 'call_endpoint_resolver.dart';

final class CallLocalDeviceAuthority {
  const CallLocalDeviceAuthority({
    required this.accountPeerId,
    required this.devicePeerId,
    required this.mlKemSecretKey,
  });

  final String accountPeerId;
  final String devicePeerId;
  final String mlKemSecretKey;

  @override
  String toString() => 'CallLocalDeviceAuthority(redacted)';
}

typedef CallLocalAuthorityProvider =
    Future<CallLocalDeviceAuthority> Function();

enum IncomingCallPrePresentationAdmissionFailureCode {
  duplicate,
  permanentReject,
  deferred,
}

/// A detail-free failure classification suitable for both foreground and
/// headless callers. Authenticated identities and wire values are never
/// copied into the exception.
final class IncomingCallPrePresentationAdmissionException implements Exception {
  const IncomingCallPrePresentationAdmissionException(this.code);

  final IncomingCallPrePresentationAdmissionFailureCode code;

  @override
  String toString() => 'Incoming call admission failed: ${code.name}';
}

/// The authenticated signal and its still-provisional replay reservation.
/// Callers must explicitly commit a terminal decision or roll back a
/// pre-presentation handoff that foreground canonical handling must replay.
final class AuthenticatedIncomingCallAdmission {
  AuthenticatedIncomingCallAdmission._(this._decoded)
    : signal = _decoded.signal,
      callHandle = _decoded.callHandle;

  final DecodedSecureCallEnvelope _decoded;
  final CallSignal signal;
  final String callHandle;

  void commitReplay() => _decoded.commitReplay();

  void rollbackReplay() => _decoded.rollbackReplay();

  @override
  String toString() => 'AuthenticatedIncomingCallAdmission(redacted)';
}

/// Pure authenticated admission before any coordinator dispatch or system UI.
/// It owns trusted-sender resolution, local decryption authority, secure
/// envelope verification, mailbox binding, and provisional replay custody.
final class IncomingCallPrePresentationAdmission {
  const IncomingCallPrePresentationAdmission({
    required SecureCallEnvelopeCodec codec,
    required CallTrustedRosterProvider trustedRosterProvider,
    required CallLocalAuthorityProvider localAuthorityProvider,
  }) : _codec = codec,
       _trustedRosterProvider = trustedRosterProvider,
       _localAuthorityProvider = localAuthorityProvider;

  final SecureCallEnvelopeCodec _codec;
  final CallTrustedRosterProvider _trustedRosterProvider;
  final CallLocalAuthorityProvider _localAuthorityProvider;

  /// Authenticates the exact mailbox row selected for one native wake. The
  /// native UUID is the canonical outer call handle; the encrypted domain
  /// [CallSignal.callId] remains a distinct coordinator identity.
  Future<AuthenticatedIncomingCallAdmission> authenticateMailboxInvite({
    required String nativeCallId,
    required int wakeExpiresAtMs,
    required CallMailboxEvent event,
  }) async {
    final admitted = await authenticateMailboxEvent(
      nativeCallId: nativeCallId,
      wakeExpiresAtMs: wakeExpiresAtMs,
      event: event,
    );
    if (admitted.signal.event != CallSignalType.invite) {
      admitted.commitReplay();
      throw const IncomingCallPrePresentationAdmissionException(
        IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
      );
    }
    return admitted;
  }

  /// Authenticates one exact-handle mailbox event without dispatching it. A
  /// headless caller can inspect invite/terminal dominance across the page,
  /// then roll back every reservation for foreground canonical replay. FCM
  /// wake `h` is independent deduplication material and is never used for
  /// mailbox retrieval or as the call-handle/native-UUID binding.
  Future<AuthenticatedIncomingCallAdmission> authenticateMailboxEvent({
    required String nativeCallId,
    required int wakeExpiresAtMs,
    required CallMailboxEvent event,
  }) async {
    if (CallId.tryParse(nativeCallId) == null ||
        nativeCallId != event.callHandle ||
        wakeExpiresAtMs <= 0 ||
        wakeExpiresAtMs != event.expiresAtMs) {
      throw const IncomingCallPrePresentationAdmissionException(
        IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
      );
    }
    final admitted = await authenticateSignal(
      envelopeJson: event.envelopeJson,
      authenticatedTransportPeerId: event.authenticatedSenderDevicePeerId,
      expectedCallHandle: event.callHandle,
      expectedMessageId: event.messageId,
      expectedExpiresAtMs: event.expiresAtMs,
      expectedRecipientDevicePeerId: event.recipientDevicePeerId,
    );
    if (const <CallSignalType>{
      CallSignalType.invite,
      CallSignalType.reject,
      CallSignalType.terminate,
    }.contains(admitted.signal.event)) {
      return admitted;
    }
    admitted.commitReplay();
    throw const IncomingCallPrePresentationAdmissionException(
      IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
    );
  }

  /// Shared foreground/direct authenticator. Optional expectations preserve
  /// the current direct-frame contract while mailbox callers bind every relay
  /// attribute exactly.
  Future<AuthenticatedIncomingCallAdmission> authenticateSignal({
    required String envelopeJson,
    required String authenticatedTransportPeerId,
    String? expectedCallHandle,
    String? expectedMessageId,
    int? expectedExpiresAtMs,
    String? expectedRecipientDevicePeerId,
  }) async {
    late final TrustedCallDeviceAuthority? sender;
    try {
      sender = await _trustedRosterProvider.resolveAuthenticatedTransport(
        authenticatedTransportPeerId,
      );
    } catch (_) {
      throw const IncomingCallPrePresentationAdmissionException(
        IncomingCallPrePresentationAdmissionFailureCode.deferred,
      );
    }
    if (sender == null || !sender.linked) {
      throw const IncomingCallPrePresentationAdmissionException(
        IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
      );
    }

    late final CallLocalDeviceAuthority local;
    try {
      local = await _localAuthorityProvider();
    } catch (_) {
      throw const IncomingCallPrePresentationAdmissionException(
        IncomingCallPrePresentationAdmissionFailureCode.deferred,
      );
    }
    if (local.accountPeerId.trim().isEmpty ||
        local.devicePeerId.trim().isEmpty ||
        local.mlKemSecretKey.trim().isEmpty) {
      throw const IncomingCallPrePresentationAdmissionException(
        IncomingCallPrePresentationAdmissionFailureCode.deferred,
      );
    }

    DecodedSecureCallEnvelope? decoded;
    try {
      decoded = await _codec.decode(
        envelopeJson: envelopeJson,
        authority: CallEnvelopeAuthority(
          authenticatedTransportPeerId: authenticatedTransportPeerId,
          expectedSenderAccountPeerId: sender.accountPeerId,
          expectedSenderDevicePeerId: sender.devicePeerId,
          expectedRecipientAccountPeerId: local.accountPeerId,
          expectedRecipientDevicePeerId: local.devicePeerId,
          senderSigningPublicKey: sender.signingPublicKey,
          ownMlKemSecretKey: local.mlKemSecretKey,
        ),
      );
      final signal = decoded.signal;
      if ((expectedCallHandle != null &&
              expectedCallHandle != decoded.callHandle) ||
          (expectedMessageId != null &&
              expectedMessageId != signal.messageId) ||
          (expectedExpiresAtMs != null &&
              expectedExpiresAtMs != signal.expiresAtMs) ||
          (expectedRecipientDevicePeerId != null &&
              expectedRecipientDevicePeerId != signal.recipientDevicePeerId)) {
        decoded.commitReplay();
        throw const IncomingCallPrePresentationAdmissionException(
          IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
        );
      }
      return AuthenticatedIncomingCallAdmission._(decoded);
    } on IncomingCallPrePresentationAdmissionException {
      rethrow;
    } on CallEnvelopeException catch (error) {
      throw IncomingCallPrePresentationAdmissionException(switch (error.code) {
        CallEnvelopeErrorCode.replay ||
        CallEnvelopeErrorCode.nonMonotonicSequence =>
          IncomingCallPrePresentationAdmissionFailureCode.duplicate,
        CallEnvelopeErrorCode.cryptoUnavailable =>
          IncomingCallPrePresentationAdmissionFailureCode.deferred,
        _ => IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
      });
    } catch (_) {
      decoded?.rollbackReplay();
      throw const IncomingCallPrePresentationAdmissionException(
        IncomingCallPrePresentationAdmissionFailureCode.deferred,
      );
    }
  }
}
