import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'dart:convert';

import 'package:flutter_app/app/bootstrap/production_headless_call_admission.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/incoming_call_pre_presentation_admission.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_signal_v2.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/headless_call_admission_entrypoint.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const _now = 2000000;
const _handle = '33333333-3333-4333-8333-333333333333';
const _call = '22222222-2222-4222-8222-222222222222';
const _message = '11111111-1111-4111-8111-111111111111';
const _other = '44444444-4444-4444-8444-444444444444';
const _witness = (fingerprint: 'fixture-relationship', relationshipRevision: 7);

Map<String, Object?> _inner({String event = 'invite', bool legacy = false}) => {
  'schema': legacy ? CallSignal.schema : CallSignalV2.schema,
  'call_id': _call,
  'message_id': _message,
  'event': event,
  'sender_account_peer_id': 'sender-account',
  'sender_device_peer_id': 'sender-device',
  'recipient_account_peer_id': 'recipient-account',
  'recipient_device_peer_id': 'recipient-device',
  'sender_sequence': 1,
  'ice_generation': 0,
  'created_at_ms': _now,
  'expires_at_ms': _now + 45000,
  'payload': switch (event) {
    'invite' when !legacy => {
      'media': 'video',
      'camera': 'off',
      'capabilities': ['audio', 'video'],
    },
    'accept' when !legacy => {'media': 'audio', 'camera': 'off'},
    'reject' || 'terminate' => {'reason': 'unsupported'},
    'camera_state' => {'media_revision': 0, 'state': 'paused'},
    _ => <String, Object?>{},
  },
};

Matcher _failure(
  IncomingCallPrePresentationAdmissionFailureCode code, {
  IncomingCallPrePresentationAdmissionGate? gate,
  CallEnvelopeErrorCode? envelopeCode,
}) {
  var matcher = isA<IncomingCallPrePresentationAdmissionException>().having(
    (error) => error.code,
    'classification',
    code,
  );
  if (gate != null) {
    matcher = matcher.having((error) => error.gate, 'gate', gate);
  }
  if (envelopeCode != null) {
    matcher = matcher.having(
      (error) => error.envelopeCode,
      'envelope code',
      envelopeCode,
    );
  }
  return throwsA(matcher);
}

const _trusted = TrustedCallDeviceAuthority(
  accountPeerId: 'sender-account',
  devicePeerId: 'sender-device',
  linked: true,
  deviceKeyEpoch: 1,
  signingPublicKey: 'fixture-signing-key',
  mlKemPublicKey: 'sender-kem',
  admissionAuthority: _witness,
);

Future<_Fixture> _fixture({
  bool? videoEnabled = true,
  bool codecEnabled = true,
  bool bindEndpoint = false,
  bool legacy = false,
  String eventName = 'invite',
  Map<String, Object?>? inner,
}) async {
  final crypto = _Crypto();
  final senderCodec = SecureCallEnvelopeCodec(
    crypto: crypto,
    nowMs: () => _now,
    videoEnabled: true,
  );
  final data = inner ?? _inner(event: eventName, legacy: legacy);
  final envelope = legacy
      ? await senderCodec.encode(
          signal: CallSignal.fromMap(data),
          callHandle: _handle,
          recipientMlKemPublicKey: 'recipient-kem',
          senderSigningPrivateKey: 'fixture-signing-key',
        )
      : await senderCodec.encodeV2(
          signal: CallSignalV2.fromMap(data, videoEnabled: true),
          callHandle: _handle,
          recipientMlKemPublicKey: 'recipient-kem',
          senderSigningPrivateKey: 'fixture-signing-key',
        );
  return _Fixture(
    crypto: crypto,
    bindEndpoint: bindEndpoint,
    codecEnabled: codecEnabled,
    videoEnabled: videoEnabled,
    event: CallMailboxEvent(
      callHandle: _handle,
      messageId: data['message_id']! as String,
      authenticatedSenderDevicePeerId: data['sender_device_peer_id']! as String,
      recipientDevicePeerId: 'recipient-device',
      envelopeJson: envelope,
      receiptAtMs: _now,
      expiresAtMs: data['expires_at_ms']! as int,
    ),
  );
}

final class _Fixture {
  _Fixture({
    required this.crypto,
    required this.event,
    required bool codecEnabled,
    required bool bindEndpoint,
    required bool? videoEnabled,
  }) {
    final codec = SecureCallEnvelopeCodec(
      crypto: crypto,
      nowMs: () => now,
      videoEnabled: codecEnabled,
    );
    Future<CallLocalDeviceAuthority> local() async {
      localLoads++;
      if (localThrows) throw StateError('private local authority unavailable');
      return localAuthority;
    }

    admission = videoEnabled == null
        ? IncomingCallPrePresentationAdmission(
            codec: codec,
            trustedRosterProvider: roster,
            localAuthorityProvider: local,
          )
        : IncomingCallPrePresentationAdmission(
            codec: codec,
            trustedRosterProvider: roster,
            localAuthorityProvider: local,
            videoEnabled: videoEnabled,
            resolveV2Endpoint: bindEndpoint ? resolveEndpoint : null,
            nowMs: () => now,
          );
  }

  final _Crypto crypto;
  final _Roster roster = _Roster();
  final CallMailboxEvent event;
  late final IncomingCallPrePresentationAdmission admission;
  int now = _now;
  int localLoads = 0;
  int endpointLoads = 0;
  ResolvedCallEndpoint endpoint = _endpoint();
  Object? endpointError;
  Future<void> Function()? beforeEndpoint;

  Future<ResolvedCallEndpoint> resolveEndpoint(String account) async {
    expect(account, 'sender-account');
    endpointLoads++;
    await beforeEndpoint?.call();
    if (endpointError case final Object error) throw error;
    return endpoint;
  }

  bool localThrows = false;
  CallLocalDeviceAuthority localAuthority = const CallLocalDeviceAuthority(
    accountPeerId: 'recipient-account',
    devicePeerId: 'recipient-device',
    mlKemSecretKey: 'fixture-secret',
  );

  Future<AuthenticatedIncomingCallWireAdmission> direct() =>
      admission.authenticateVersionedSignal(
        envelopeJson: event.envelopeJson,
        authenticatedTransportPeerId: 'sender-device',
      );

  Future<AuthenticatedIncomingCallWireAdmission> mailbox({
    bool inviteOnly = true,
    String nativeCallId = _handle,
    int wakeExpiry = _now + 45000,
    CallMailboxEvent? row,
  }) => inviteOnly
      ? admission.authenticateVersionedMailboxInvite(
          nativeCallId: nativeCallId,
          wakeExpiresAtMs: wakeExpiry,
          event: row ?? event,
        )
      : admission.authenticateVersionedMailboxEvent(
          nativeCallId: nativeCallId,
          wakeExpiresAtMs: wakeExpiry,
          event: row ?? event,
        );

  AuthenticateHeadlessMailboxEvent coldAuthenticator({
    required bool videoEnabled,
  }) => createProductionHeadlessMailboxAuthenticator(
    codec: SecureCallEnvelopeCodec(
      crypto: crypto,
      nowMs: () => now,
      videoEnabled: true,
    ),
    roster: roster,
    localAuthorityProvider: () async => localAuthority,
    videoEnabled: videoEnabled,
    resolveV2Endpoint: videoEnabled ? resolveEndpoint : null,
    nowMs: () => now,
  );
}

final class _Roster implements CallTrustedRosterProvider {
  TrustedCallDeviceAuthority? authority = _trusted;
  bool blocked = false;
  bool unavailable = false;
  final List<String> lookups = [];
  final additionalDevices = <String, TrustedCallDeviceAuthority>{};

  @override
  Future<CallTrustedRosterSnapshot> loadForContact(String peerId) async =>
      throw UnimplementedError();

  @override
  Future<TrustedCallDeviceAuthority?> resolveAuthenticatedTransport(
    String authenticatedTransportPeerId,
  ) async {
    lookups.add(authenticatedTransportPeerId);
    if (blocked) throw const CallSenderBlockedException();
    if (unavailable) throw StateError('private roster unavailable');
    return additionalDevices[authenticatedTransportPeerId] ?? authority;
  }
}

final class _ColdMailbox extends Fake implements CallMailboxClient {
  _ColdMailbox(this.events);

  final List<CallMailboxEvent> events;
  final acknowledgements = <List<String>>[];

  @override
  Future<CallMailboxRetrieveResult> retrieve({
    String? callHandle,
    int limit = 64,
  }) async => CallMailboxRetrieveResult(
    events: events.where((event) => event.callHandle == callHandle).toList(),
    receiptAtMs: _now,
    expiresAtMs: _now + 45000,
    hasMore: false,
  );

  @override
  Future<int> ack({
    required String callHandle,
    required List<String> messageIds,
  }) async {
    acknowledgements.add(messageIds);
    return messageIds.length;
  }
}

final class _Crypto implements CallEnvelopeCrypto {
  bool throwOnVerify = false;
  bool throwOnDecrypt = false;
  bool signatureValid = true;
  int decryptCalls = 0;
  void Function()? onDecrypt;

  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async => CallCiphertext(
    kem: base64Encode(utf8.encode('fixture-kem')),
    ciphertext: base64Encode(utf8.encode(plaintext)),
    nonce: base64Encode(utf8.encode('fixture-nonce')),
  );

  @override
  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  }) async {
    decryptCalls++;
    if (throwOnDecrypt) throw StateError('private crypto unavailable');
    onDecrypt?.call();
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
    if (throwOnVerify) throw StateError('private crypto unavailable');
    return signatureValid &&
        signature ==
            base64Encode(utf8.encode('$senderSigningPublicKey:$canonicalData'));
  }
}

ResolvedCallEndpoint _endpoint({
  String account = 'sender-account',
  String device = 'sender-device',
  String signing = 'fixture-signing-key',
  String kem = 'sender-kem',
  int epoch = 1,
  int expires = _now + 45000,
  CallAdmissionAuthorityWitness? witness = _witness,
  Set<String> capabilities = const {'voice_call_v1', 'video_call_v2'},
}) => ResolvedCallEndpoint(
  accountPeerId: account,
  devicePeerId: device,
  signingPublicKey: signing,
  mlKemPublicKey: kem,
  deviceKeyEpoch: epoch,
  preferenceEpoch: 1,
  admissionAuthority: witness,
  platform: CallEndpointPlatform.android,
  expiresAtMs: expires,
  routingHandle: '0123456789abcdef0123456789abcdef',
  wakeHandle: 'fedcba9876543210fedcba9876543210',
  capabilities: capabilities,
);

Map<String, Object?> _audioInvite() => {
  ..._inner(),
  'payload': {
    'media': 'audio',
    'camera': 'off',
    'capabilities': ['audio', 'video'],
  },
};

HeadlessCallAdmissionInvocation _coldInvocation(
  HeadlessCallAdmissionMode mode,
) => HeadlessCallAdmissionInvocation(
  nonce: '55555555-5555-4555-8555-555555555555',
  callId: _handle,
  wakeHandle: '66666666666646668666666666666666',
  expiresAtMs: _now + 45000,
  mode: mode,
);

Future<HeadlessCallAdmissionCleanup> _coldCleanup() async =>
    const HeadlessCallAdmissionCleanup(
      databaseClosed: true,
      leaseReleased: true,
    );

void main() {
  for (final (legacy, enabled) in [
    (true, false),
    (false, true),
    (false, false),
  ]) {
    test(
      legacy || enabled
          ? 'BL-112 cold mailbox admits ${legacy ? 'V1' : 'V2'} audio invite'
          : 'BL-112 cold mailbox refuses V2 audio invite with the flag off',
      () async {
        const deadline = Duration(seconds: 3);
        final f = await _fixture(
          legacy: legacy,
          inner: legacy ? null : _audioInvite(),
        ).timeout(deadline);
        final session = MailboxProductionHeadlessCallAdmissionSession(
          mailboxClient: _ColdMailbox([f.event]),
          authenticateEvent: f.coldAuthenticator(videoEnabled: enabled),
          closeResources: _coldCleanup,
        );
        final disposition = await session
            .evaluate(_coldInvocation(HeadlessCallAdmissionMode.admission))
            .timeout(deadline);
        expect(
          disposition,
          legacy || enabled
              ? HeadlessCallAdmissionDisposition.admitted
              : HeadlessCallAdmissionDisposition.permanentReject,
          reason: session.diagnosticCause,
        );
        expect(f.endpointLoads, enabled ? 1 : 0);
      },
    );
  }

  for (final terminalBinding in [
    'same',
    'schema',
    'sender device',
    'V1 terminal with unresolved V2 invite',
  ]) {
    test('BL-112 cold mailbox terminal binding $terminalBinding', () async {
      const deadline = Duration(seconds: 3);
      final f = await _fixture(inner: _audioInvite()).timeout(deadline);
      final unresolvedInvite =
          terminalBinding == 'V1 terminal with unresolved V2 invite';
      final legacyTerminal = terminalBinding == 'schema' || unresolvedInvite;
      final otherDevice = terminalBinding == 'sender device';
      if (unresolvedInvite) {
        f.endpointError = const CallEndpointResolutionException(
          CallEndpointResolutionCode.unavailable,
        );
      }
      if (otherDevice) {
        f.roster.additionalDevices['other-device'] =
            const TrustedCallDeviceAuthority(
              accountPeerId: 'sender-account',
              devicePeerId: 'other-device',
              linked: true,
              deviceKeyEpoch: 1,
              signingPublicKey: 'fixture-signing-key',
              mlKemPublicKey: 'sender-kem',
            );
      }
      final terminal = await _fixture(
        legacy: legacyTerminal,
        inner: {
          ..._inner(event: 'terminate', legacy: legacyTerminal),
          'message_id': _other,
          'sender_sequence': 2,
          if (otherDevice) 'sender_device_peer_id': 'other-device',
          'created_at_ms': _now + 10,
          'expires_at_ms': _now + 45010,
        },
      ).timeout(deadline);
      final authenticate = f.coldAuthenticator(videoEnabled: true);
      final sameCall = terminalBinding == 'same';
      for (final mode in const [
        HeadlessCallAdmissionMode.admission,
        HeadlessCallAdmissionMode.declineReply,
        HeadlessCallAdmissionMode.ringingReply,
      ]) {
        final mailbox = _ColdMailbox([f.event, terminal.event]);
        final replies = <AuthenticatedIncomingCallAdmissionV2>[];
        Future<bool> send(AuthenticatedIncomingCallAdmissionV2 invite) async {
          replies.add(invite);
          return true;
        }

        final session = MailboxProductionHeadlessCallAdmissionSession(
          mailboxClient: mailbox,
          authenticateEvent: authenticate,
          closeResources: _coldCleanup,
          ringingV2ReplySender: send,
          declineV2ReplySender: send,
        );
        expect(
          await session.evaluate(_coldInvocation(mode)).timeout(deadline),
          switch (mode) {
            _ when unresolvedInvite =>
              HeadlessCallAdmissionDisposition.deferred,
            HeadlessCallAdmissionMode.admission when !sameCall =>
              HeadlessCallAdmissionDisposition.admitted,
            HeadlessCallAdmissionMode.ringingReply when sameCall =>
              HeadlessCallAdmissionDisposition.deferred,
            _ => HeadlessCallAdmissionDisposition.terminal,
          },
          reason: mode.wireName,
        );
        if (!sameCall &&
            !unresolvedInvite &&
            mode != HeadlessCallAdmissionMode.admission) {
          final invite = replies.single;
          expect(invite.callHandle, _handle);
          expect(invite.admissionAuthority, _witness);
          expect(invite.admittedEndpoint?.devicePeerId, _trusted.devicePeerId);
        } else {
          expect(replies, isEmpty);
        }
        expect(mailbox.acknowledgements, switch (mode) {
          _ when unresolvedInvite => const <List<String>>[],
          HeadlessCallAdmissionMode.ringingReply => const <List<String>>[],
          _ when sameCall => const [
            [_message, _other],
          ],
          HeadlessCallAdmissionMode.declineReply => const [
            [_message],
          ],
          _ => const <List<String>>[],
        });
      }
    });
  }

  test(
    'BL-112 presentation failure defers a V2 invite without a V1 reply or ACK',
    () async {
      const bound = Duration(seconds: 3);
      final invite = await _fixture(inner: _audioInvite()).timeout(bound);
      final terminal = await _fixture(
        legacy: true,
        inner: {
          ..._inner(event: 'terminate', legacy: true),
          'message_id': _other,
          'sender_sequence': 2,
        },
      ).timeout(bound);
      final mailbox = _ColdMailbox([invite.event, terminal.event]);
      var sent = 0;
      final session = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: mailbox,
        authenticateEvent: invite.coldAuthenticator(videoEnabled: true),
        closeResources: _coldCleanup,
        presentationFailureReplySender: (_, _) async {
          sent++;
          return true;
        },
      );

      expect(
        await session
            .evaluate(
              _coldInvocation(
                HeadlessCallAdmissionMode.presentationFailureReply,
              ),
            )
            .timeout(bound),
        HeadlessCallAdmissionDisposition.deferred,
      );
      expect(invite.endpointLoads, 1);
      expect(sent, 0);
      expect(mailbox.acknowledgements, isEmpty);
    },
  );

  for (final mailbox in [false, true]) {
    test(
      'U3h freezes signed endpoint at authenticated invite admission mailbox=$mailbox',
      () async {
        final f = await _fixture(bindEndpoint: true);
        final caps = <String>{'voice_call_v1', 'video_call_v2'};
        f.endpoint = _endpoint(capabilities: caps);
        final result =
            (mailbox ? await f.mailbox() : await f.direct())
                as AuthenticatedIncomingCallAdmissionV2;
        expect(f.endpointLoads, 1);
        caps.clear();
        expect(result.admittedEndpoint?.capabilities, {
          'voice_call_v1',
          'video_call_v2',
        });
        expect(result.admittedEndpoint?.admissionAuthority, _witness);
        expect(
          () => result.admittedEndpoint!.capabilities.clear(),
          throwsUnsupportedError,
        );
        expect(result.toString(), isNot(contains('fixture-signing-key')));
        result.rollbackReplay();
      },
    );
  }

  final mismatches = <String, ResolvedCallEndpoint>{
    'account': _endpoint(account: 'other-account'),
    'device': _endpoint(device: 'other-device'),
    'signing key': _endpoint(signing: 'other-key'),
    'KEM key': _endpoint(kem: 'other-kem'),
    'key epoch': _endpoint(epoch: 2),
    'relationship': _endpoint(
      witness: (fingerprint: 'other', relationshipRevision: 8),
    ),
    'expired': _endpoint(expires: _now),
    'missing voice': _endpoint(capabilities: {'video_call_v2'}),
    'missing video': _endpoint(capabilities: {'voice_call_v1'}),
  };
  for (final entry in mismatches.entries) {
    test(
      'U3h refuses authenticated invite endpoint ${entry.key} and commits replay',
      () async {
        final f = await _fixture(bindEndpoint: true);
        f.endpoint = entry.value;
        await expectLater(
          f.direct(),
          _failure(
            IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
          ),
        );
        f.endpoint = _endpoint();
        await expectLater(
          f.direct(),
          _failure(IncomingCallPrePresentationAdmissionFailureCode.duplicate),
        );
      },
    );
  }

  test(
    'U3h transient endpoint lookup rolls back replay for fresh admission',
    () async {
      final f = await _fixture(bindEndpoint: true);
      f.endpointError = const CallEndpointResolutionException(
        CallEndpointResolutionCode.unavailable,
      );
      await expectLater(
        f.direct(),
        _failure(IncomingCallPrePresentationAdmissionFailureCode.deferred),
      );
      f.endpointError = null;
      final result = await f.direct() as AuthenticatedIncomingCallAdmissionV2;
      expect(result.admittedEndpoint, isNotNull);
      expect(f.endpointLoads, 2);
      result.rollbackReplay();
    },
  );

  test('U3h invite expiry is rechecked after endpoint await', () async {
    final f = await _fixture(bindEndpoint: true);
    f.beforeEndpoint = () async {
      f.now += 45000;
    };
    await expectLater(
      f.direct(),
      _failure(IncomingCallPrePresentationAdmissionFailureCode.permanentReject),
    );
    expect(f.endpointLoads, 1);
  });

  for (final event in ['terminate', 'reject', 'accept']) {
    test(
      'U3h authenticated $event does not depend on a fresh invite endpoint',
      () async {
        final f = await _fixture(bindEndpoint: true, eventName: event);
        f.endpointError = StateError('directory offline');
        final result = await f.direct() as AuthenticatedIncomingCallAdmissionV2;
        expect(f.endpointLoads, 0);
        expect(result.admittedEndpoint, isNull);
        result.rollbackReplay();
      },
    );
  }

  for (final event in ['ringing', 'accept', 'camera_state']) {
    test('U3d direct $event authenticates without presenting a call', () async {
      final f = await _fixture(eventName: event);
      final admitted = await f.direct();
      expect(admitted.signal.eventWireName, event);
      expect(admitted.signal.toMap(), _inner(event: event));
      admitted.rollbackReplay();
    });
    test('U3d wake admission refuses and commits non-wake $event', () async {
      final f = await _fixture(eventName: event);
      await expectLater(
        f.mailbox(inviteOnly: false),
        _failure(
          IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
          gate: IncomingCallPrePresentationAdmissionGate.unexpectedSignal,
        ),
      );
      await expectLater(
        f.direct(),
        _failure(IncomingCallPrePresentationAdmissionFailureCode.duplicate),
      );
    });
  }

  for (final binding in ['invalid-native', 'other-native', 'expiry', 'zero']) {
    test('U3d rejects $binding wake before loading any authority', () async {
      final f = await _fixture();
      await expectLater(
        f.mailbox(
          nativeCallId: switch (binding) {
            'invalid-native' => 'not-a-uuid',
            'other-native' => _other,
            _ => _handle,
          },
          wakeExpiry: switch (binding) {
            'expiry' => _now + 44999,
            'zero' => 0,
            _ => _now + 45000,
          },
        ),
        _failure(
          IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
          gate: IncomingCallPrePresentationAdmissionGate.mailboxBinding,
        ),
      );
      expect(f.roster.lookups, isEmpty);
      expect(f.localLoads, 0);
      expect(f.crypto.decryptCalls, 0);
    });
  }

  for (final binding in ['handle', 'message', 'expiry', 'recipient']) {
    test('U3d commits authenticated mailbox $binding mismatch', () async {
      final f = await _fixture();
      final row = CallMailboxEvent(
        callHandle: binding == 'handle' ? _other : _handle,
        messageId: binding == 'message' ? _other : _message,
        expiresAtMs: binding == 'expiry' ? _now + 44999 : _now + 45000,
        recipientDevicePeerId: binding == 'recipient'
            ? 'other-device'
            : 'recipient-device',
        authenticatedSenderDevicePeerId: 'sender-device',
        envelopeJson: f.event.envelopeJson,
        receiptAtMs: _now,
      );
      await expectLater(
        f.mailbox(
          row: row,
          nativeCallId: row.callHandle,
          wakeExpiry: row.expiresAtMs,
        ),
        _failure(
          IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
          gate: IncomingCallPrePresentationAdmissionGate.expectationMismatch,
        ),
      );
      await expectLater(
        f.direct(),
        _failure(IncomingCallPrePresentationAdmissionFailureCode.duplicate),
      );
    });
  }

  for (final field in [
    'sender_account_peer_id',
    'sender_device_peer_id',
    'recipient_account_peer_id',
    'recipient_device_peer_id',
  ]) {
    test('U3d refuses authenticated inner $field mismatch', () async {
      final f = await _fixture(inner: {..._inner(), field: 'other-peer'});
      await expectLater(
        f.direct(),
        _failure(
          IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
          envelopeCode: CallEnvelopeErrorCode.authorityMismatch,
        ),
      );
    });
  }

  test('U3d binds the authenticated transport to the trusted sender', () async {
    final f = await _fixture();
    await expectLater(
      f.admission.authenticateVersionedSignal(
        envelopeJson: f.event.envelopeJson,
        authenticatedTransportPeerId: 'other-transport',
      ),
      _failure(
        IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
        envelopeCode: CallEnvelopeErrorCode.authorityMismatch,
      ),
    );
    expect(f.roster.lookups, ['other-transport']);
  });

  for (final condition in ['unknown', 'unlinked', 'blocked', 'unavailable']) {
    test(
      'U3d trusted roster $condition stops before local authority',
      () async {
        final f = await _fixture();
        switch (condition) {
          case 'unknown':
            f.roster.authority = null;
          case 'unlinked':
            f.roster.authority = const TrustedCallDeviceAuthority(
              accountPeerId: 'sender-account',
              devicePeerId: 'sender-device',
              linked: false,
              deviceKeyEpoch: 1,
              signingPublicKey: 'fixture-signing-key',
              mlKemPublicKey: 'sender-kem',
            );
          case 'blocked':
            f.roster.blocked = true;
          case 'unavailable':
            f.roster.unavailable = true;
        }
        await expectLater(
          f.direct(),
          _failure(
            condition == 'unavailable'
                ? IncomingCallPrePresentationAdmissionFailureCode.deferred
                : IncomingCallPrePresentationAdmissionFailureCode
                      .permanentReject,
            gate: switch (condition) {
              'blocked' =>
                IncomingCallPrePresentationAdmissionGate.senderBlocked,
              'unavailable' =>
                IncomingCallPrePresentationAdmissionGate.rosterUnavailable,
              _ => IncomingCallPrePresentationAdmissionGate.senderUnknown,
            },
          ),
        );
        expect(f.localLoads, 0);
        expect(f.crypto.decryptCalls, 0);
      },
    );
  }

  for (final missing in ['account', 'device', 'secret', 'provider']) {
    test('U3d missing local $missing defers before decryption', () async {
      final f = await _fixture();
      f.localThrows = missing == 'provider';
      f.localAuthority = CallLocalDeviceAuthority(
        accountPeerId: missing == 'account' ? '  ' : 'recipient-account',
        devicePeerId: missing == 'device' ? '' : 'recipient-device',
        mlKemSecretKey: missing == 'secret' ? ' ' : 'fixture-secret',
      );
      await expectLater(
        f.direct(),
        _failure(
          IncomingCallPrePresentationAdmissionFailureCode.deferred,
          gate: IncomingCallPrePresentationAdmissionGate
              .localAuthorityUnavailable,
        ),
      );
      expect(f.crypto.decryptCalls, 0);
    });
  }

  for (final phase in ['verify', 'decrypt']) {
    test('U3d transient $phase failure defers and remains retryable', () async {
      final f = await _fixture();
      f.crypto.throwOnVerify = phase == 'verify';
      f.crypto.throwOnDecrypt = phase == 'decrypt';
      await expectLater(
        f.direct(),
        _failure(
          IncomingCallPrePresentationAdmissionFailureCode.deferred,
          envelopeCode: CallEnvelopeErrorCode.cryptoUnavailable,
        ),
      );
      f.crypto.throwOnVerify = false;
      f.crypto.throwOnDecrypt = false;
      final retry = await f.direct();
      retry.commitReplay();
    });
  }

  test('U3d invalid signature is permanent and never decrypts', () async {
    final f = await _fixture();
    f.crypto.signatureValid = false;
    await expectLater(
      f.direct(),
      _failure(
        IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
        envelopeCode: CallEnvelopeErrorCode.invalidSignature,
      ),
    );
    expect(f.crypto.decryptCalls, 0);
  });

  test('U3d expiry during crypto wait cannot admit a stale invite', () async {
    final f = await _fixture();
    f.crypto.onDecrypt = () => f.now = _now + 45000;
    await expectLater(
      f.direct(),
      _failure(
        IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
        envelopeCode: CallEnvelopeErrorCode.expired,
      ),
    );
  });

  test('U3d admission defaults off even when codec enables v2', () async {
    final f = await _fixture(videoEnabled: null);
    await expectLater(
      f.direct(),
      _failure(
        IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
        envelopeCode: CallEnvelopeErrorCode.invalidSchema,
      ),
    );
  });

  test('U3d codec gate also rejects an enabled admission owner', () async {
    final f = await _fixture(codecEnabled: false);
    await expectLater(
      f.direct(),
      _failure(
        IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
        envelopeCode: CallEnvelopeErrorCode.invalidSchema,
      ),
    );
  });

  test(
    'U3d all three legacy entry points remain v1-only when enabled',
    () async {
      final f = await _fixture();
      for (final legacy
          in <Future<AuthenticatedIncomingCallAdmission> Function()>[
            () => f.admission.authenticateSignal(
              envelopeJson: f.event.envelopeJson,
              authenticatedTransportPeerId: 'sender-device',
            ),
            () => f.admission.authenticateMailboxEvent(
              nativeCallId: _handle,
              wakeExpiresAtMs: _now + 45000,
              event: f.event,
            ),
            () => f.admission.authenticateMailboxInvite(
              nativeCallId: _handle,
              wakeExpiresAtMs: _now + 45000,
              event: f.event,
            ),
          ]) {
        await expectLater(
          legacy(),
          _failure(
            IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
            envelopeCode: CallEnvelopeErrorCode.invalidSchema,
          ),
        );
      }
    },
  );

  for (final enabled in [false, true]) {
    test('U3d versioned entry retains typed v1 with gate $enabled', () async {
      final f = await _fixture(legacy: true, videoEnabled: enabled);
      final admitted = await f.mailbox();
      expect(admitted, isA<AuthenticatedIncomingCallAdmission>());
      expect(admitted.signal.toMap(), _inner(legacy: true));
      admitted.rollbackReplay();
      final old = await f.admission.authenticateMailboxInvite(
        nativeCallId: _handle,
        wakeExpiresAtMs: _now + 45000,
        event: f.event,
      );
      expect(old.signal.event, CallSignalType.invite);
      old.commitReplay();
      await expectLater(
        f.direct(),
        _failure(IncomingCallPrePresentationAdmissionFailureCode.duplicate),
      );
    });
  }

  test('U3d v2 invite retains exact bindings and authority witness', () async {
    final f = await _fixture();
    final admitted = await f.mailbox();
    expect(admitted, isA<AuthenticatedIncomingCallAdmissionV2>());
    expect(admitted.signal.toMap(), _inner());
    expect(admitted.callHandle, _handle);
    expect(admitted.signal.callId.value, _call);
    expect(admitted.admissionAuthority, _witness);
    expect(
      admitted.toString(),
      'AuthenticatedIncomingCallAdmissionV2(redacted)',
    );
    expect(f.roster.lookups, ['sender-device']);
    expect(f.localLoads, 1);
    admitted.rollbackReplay();
  });

  test(
    'U3d rollback permits canonical replay; commit rejects duplicate',
    () async {
      final f = await _fixture();
      final first = await f.mailbox();
      first.rollbackReplay();
      final foreground = await f.direct();
      foreground.commitReplay();
      await expectLater(
        f.mailbox(),
        _failure(IncomingCallPrePresentationAdmissionFailureCode.duplicate),
      );
    },
  );

  test('U3d direct and mailbox share provisional replay custody', () async {
    final f = await _fixture();
    final direct = await f.direct();
    await expectLater(
      f.mailbox(),
      _failure(IncomingCallPrePresentationAdmissionFailureCode.duplicate),
    );
    direct.rollbackReplay();
    final retry = await f.mailbox();
    retry.commitReplay();
  });

  for (final event in ['reject', 'terminate']) {
    test('U3d authenticated $event surfaces before presentation', () async {
      final f = await _fixture(eventName: event);
      final terminal = await f.mailbox(inviteOnly: false);
      expect(terminal, isA<AuthenticatedIncomingCallAdmissionV2>());
      expect(terminal.signal.eventWireName, event);
      expect(terminal.signal.payload, {'reason': 'unsupported'});
      terminal.rollbackReplay();
      final foreground = await f.direct();
      foreground.commitReplay();
    });
    test('U3d invite-only path rejects and commits $event', () async {
      final f = await _fixture(eventName: event);
      await expectLater(
        f.mailbox(),
        _failure(
          IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
          gate: IncomingCallPrePresentationAdmissionGate.unexpectedSignal,
        ),
      );
      await expectLater(
        f.direct(),
        _failure(IncomingCallPrePresentationAdmissionFailureCode.duplicate),
      );
    });
  }
}
