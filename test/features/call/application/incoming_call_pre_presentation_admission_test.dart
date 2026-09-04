import 'dart:convert';

import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/incoming_call_pre_presentation_admission.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const _nowMs = 2_000_000;
const _callHandle = '33333333-3333-4333-8333-333333333333';
const _messageId = '11111111-1111-4111-8111-111111111111';
final _callId = CallId.parse('22222222-2222-4222-8222-222222222222');

void main() {
  test(
    'authenticates exact mailbox invite without a coordinator and permits replay rollback',
    () async {
      final fixture = await _fixture();

      final admitted = await fixture.admission.authenticateMailboxInvite(
        nativeCallId: _callHandle,
        wakeExpiresAtMs: _nowMs + 45_000,
        event: fixture.event,
      );

      expect(admitted.signal.event, CallSignalType.invite);
      expect(admitted.signal.callId, _callId);
      expect(admitted.callHandle, _callHandle);
      expect(
        admitted.toString(),
        'AuthenticatedIncomingCallAdmission(redacted)',
      );
      expect(fixture.roster.resolvedTransports, <String>['sender-device']);
      expect(fixture.localAuthorityLoads, 1);

      admitted.rollbackReplay();
      final foregroundRetry = await fixture.admission.authenticateMailboxInvite(
        nativeCallId: _callHandle,
        wakeExpiresAtMs: _nowMs + 45_000,
        event: fixture.event,
      );
      foregroundRetry.commitReplay();

      await _expectFailure(
        fixture.admission.authenticateMailboxInvite(
          nativeCallId: _callHandle,
          wakeExpiresAtMs: _nowMs + 45_000,
          event: fixture.event,
        ),
        IncomingCallPrePresentationAdmissionFailureCode.duplicate,
      );
    },
  );

  test(
    'blocked and unknown authenticated transports reject permanently',
    () async {
      for (final authority in <TrustedCallDeviceAuthority?>[
        null,
        const TrustedCallDeviceAuthority(
          accountPeerId: 'sender-account',
          devicePeerId: 'sender-device',
          linked: false,
          deviceKeyEpoch: 1,
          signingPublicKey: 'sender-signing-key',
          mlKemPublicKey: 'sender-mlkem-key',
        ),
      ]) {
        final fixture = await _fixture(rosterAuthority: authority);

        await _expectFailure(
          fixture.admission.authenticateMailboxInvite(
            nativeCallId: _callHandle,
            wakeExpiresAtMs: _nowMs + 45_000,
            event: fixture.event,
          ),
          IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
        );
        expect(fixture.localAuthorityLoads, 0);
      }
    },
  );

  test('wake, outer, and inner mailbox binding mismatches reject', () async {
    for (final mismatch in _BindingMismatch.values) {
      final fixture = await _fixture();
      var nativeCallId = _callHandle;
      var wakeExpiresAtMs = _nowMs + 45_000;
      var event = fixture.event;
      switch (mismatch) {
        case _BindingMismatch.nativeCallId:
          nativeCallId = '44444444-4444-4444-8444-444444444444';
          break;
        case _BindingMismatch.wakeExpiry:
          wakeExpiresAtMs++;
          break;
        case _BindingMismatch.outerCallHandle:
          event = _copyEvent(
            event,
            callHandle: '44444444-4444-4444-8444-444444444444',
          );
          nativeCallId = event.callHandle;
          break;
        case _BindingMismatch.outerMessageId:
          event = _copyEvent(
            event,
            messageId: '55555555-5555-4555-8555-555555555555',
          );
          break;
        case _BindingMismatch.outerExpiry:
          event = _copyEvent(event, expiresAtMs: event.expiresAtMs + 1);
          wakeExpiresAtMs = event.expiresAtMs;
          break;
        case _BindingMismatch.recipient:
          event = _copyEvent(event, recipientDevicePeerId: 'other-device');
          break;
        case _BindingMismatch.sender:
          event = _copyEvent(
            event,
            authenticatedSenderDevicePeerId: 'other-device',
          );
          break;
      }

      await _expectFailure(
        fixture.admission.authenticateMailboxInvite(
          nativeCallId: nativeCallId,
          wakeExpiresAtMs: wakeExpiresAtMs,
          event: event,
        ),
        IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
        reason: mismatch.name,
      );
    }
  });

  test('crypto unavailability is deferred and remains retryable', () async {
    for (final phase in <String>['verify', 'decrypt']) {
      final crypto = _Crypto();
      final fixture = await _fixture(crypto: crypto);
      if (phase == 'verify') {
        crypto.throwOnVerify = true;
      } else {
        crypto.throwOnDecrypt = true;
      }

      await _expectFailure(
        fixture.admission.authenticateMailboxInvite(
          nativeCallId: _callHandle,
          wakeExpiresAtMs: _nowMs + 45_000,
          event: fixture.event,
        ),
        IncomingCallPrePresentationAdmissionFailureCode.deferred,
        reason: phase,
      );

      crypto.throwOnVerify = false;
      crypto.throwOnDecrypt = false;
      final retry = await fixture.admission.authenticateMailboxInvite(
        nativeCallId: _callHandle,
        wakeExpiresAtMs: _nowMs + 45_000,
        event: fixture.event,
      );
      retry.rollbackReplay();
    }
  });

  test(
    'authenticated terminal mailbox signal surfaces before presentation',
    () async {
      for (final event in <CallSignalType>[
        CallSignalType.reject,
        CallSignalType.terminate,
      ]) {
        final fixture = await _fixture(
          signal: _signal(
            event: event,
            payload: const <String, Object?>{'reason': 'remote_hangup'},
          ),
        );

        final terminal = await fixture.admission.authenticateMailboxEvent(
          nativeCallId: _callHandle,
          wakeExpiresAtMs: _nowMs + 45_000,
          event: fixture.event,
        );
        expect(terminal.signal.event, event);
        terminal.rollbackReplay();

        final foregroundRetry = await fixture.admission
            .authenticateMailboxEvent(
              nativeCallId: _callHandle,
              wakeExpiresAtMs: _nowMs + 45_000,
              event: fixture.event,
            );
        expect(foregroundRetry.signal.event, event);
        foregroundRetry.rollbackReplay();
      }
    },
  );
}

enum _BindingMismatch {
  nativeCallId,
  wakeExpiry,
  outerCallHandle,
  outerMessageId,
  outerExpiry,
  recipient,
  sender,
}

Future<void> _expectFailure(
  Future<AuthenticatedIncomingCallAdmission> future,
  IncomingCallPrePresentationAdmissionFailureCode code, {
  String? reason,
}) => expectLater(
  future,
  throwsA(
    isA<IncomingCallPrePresentationAdmissionException>().having(
      (error) => error.code,
      'code',
      code,
    ),
  ),
  reason: reason,
);

CallMailboxEvent _copyEvent(
  CallMailboxEvent event, {
  String? callHandle,
  String? messageId,
  String? authenticatedSenderDevicePeerId,
  String? recipientDevicePeerId,
  int? expiresAtMs,
}) => CallMailboxEvent(
  callHandle: callHandle ?? event.callHandle,
  messageId: messageId ?? event.messageId,
  authenticatedSenderDevicePeerId:
      authenticatedSenderDevicePeerId ?? event.authenticatedSenderDevicePeerId,
  recipientDevicePeerId: recipientDevicePeerId ?? event.recipientDevicePeerId,
  envelopeJson: event.envelopeJson,
  receiptAtMs: event.receiptAtMs,
  expiresAtMs: expiresAtMs ?? event.expiresAtMs,
);

Future<_Fixture> _fixture({
  CallSignal? signal,
  TrustedCallDeviceAuthority? rosterAuthority = _trustedAuthority,
  _Crypto? crypto,
}) async {
  final selectedCrypto = crypto ?? _Crypto();
  final selectedSignal = signal ?? _signal();
  final codec = SecureCallEnvelopeCodec(
    crypto: selectedCrypto,
    nowMs: () => _nowMs,
  );
  final envelope = await codec.encode(
    signal: selectedSignal,
    callHandle: _callHandle,
    recipientMlKemPublicKey: 'recipient-mlkem-key',
    senderSigningPrivateKey: 'sender-signing-key',
  );
  final roster = _Roster(rosterAuthority);
  var localAuthorityLoads = 0;
  final admission = IncomingCallPrePresentationAdmission(
    codec: codec,
    trustedRosterProvider: roster,
    localAuthorityProvider: () async {
      localAuthorityLoads++;
      return const CallLocalDeviceAuthority(
        accountPeerId: 'recipient-account',
        devicePeerId: 'recipient-device',
        mlKemSecretKey: 'recipient-mlkem-secret-key',
      );
    },
  );
  return _Fixture(
    admission: admission,
    roster: roster,
    event: CallMailboxEvent(
      callHandle: _callHandle,
      messageId: selectedSignal.messageId,
      authenticatedSenderDevicePeerId: 'sender-device',
      recipientDevicePeerId: 'recipient-device',
      envelopeJson: envelope,
      receiptAtMs: _nowMs,
      expiresAtMs: selectedSignal.expiresAtMs,
    ),
    localAuthorityLoads: () => localAuthorityLoads,
  );
}

CallSignal _signal({
  CallSignalType event = CallSignalType.invite,
  Map<String, Object?> payload = const <String, Object?>{},
}) => CallSignal.create(
  callId: _callId,
  messageId: _messageId,
  event: event,
  senderAccountPeerId: 'sender-account',
  senderDevicePeerId: 'sender-device',
  recipientAccountPeerId: 'recipient-account',
  recipientDevicePeerId: 'recipient-device',
  senderSequence: 1,
  iceGeneration: 0,
  createdAtMs: _nowMs,
  expiresAtMs: _nowMs + 45_000,
  payload: payload,
);

const _trustedAuthority = TrustedCallDeviceAuthority(
  accountPeerId: 'sender-account',
  devicePeerId: 'sender-device',
  linked: true,
  deviceKeyEpoch: 1,
  signingPublicKey: 'sender-signing-key',
  mlKemPublicKey: 'sender-mlkem-key',
);

final class _Fixture {
  const _Fixture({
    required this.admission,
    required this.roster,
    required this.event,
    required int Function() localAuthorityLoads,
  }) : _localAuthorityLoads = localAuthorityLoads;

  final IncomingCallPrePresentationAdmission admission;
  final _Roster roster;
  final CallMailboxEvent event;
  final int Function() _localAuthorityLoads;

  int get localAuthorityLoads => _localAuthorityLoads();
}

final class _Roster implements CallTrustedRosterProvider {
  _Roster(this.authority);

  final TrustedCallDeviceAuthority? authority;
  final List<String> resolvedTransports = <String>[];

  @override
  Future<CallTrustedRosterSnapshot> loadForContact(String peerId) async =>
      throw UnimplementedError();

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String authenticatedTransportPeerId,
  ) async {
    resolvedTransports.add(authenticatedTransportPeerId);
    return authority;
  }
}

final class _Crypto implements CallEnvelopeCrypto {
  bool throwOnVerify = false;
  bool throwOnDecrypt = false;

  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async => CallCiphertext(
    kem: base64Encode(utf8.encode('kem')),
    ciphertext: base64Encode(utf8.encode(plaintext)),
    nonce: base64Encode(utf8.encode('nonce')),
  );

  @override
  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  }) async {
    if (throwOnDecrypt) throw StateError('crypto unavailable');
    return utf8.decode(base64Decode(ciphertext.ciphertext));
  }

  @override
  Future<String> sign({
    required String senderSigningPrivateKey,
    required String canonicalData,
  }) async =>
      base64Encode(utf8.encode('$senderSigningPrivateKey:$canonicalData'));

  @override
  Future<bool> verify({
    required String senderSigningPublicKey,
    required String canonicalData,
    required String signature,
  }) async {
    if (throwOnVerify) throw StateError('crypto unavailable');
    return signature ==
        base64Encode(utf8.encode('$senderSigningPublicKey:$canonicalData'));
  }
}
