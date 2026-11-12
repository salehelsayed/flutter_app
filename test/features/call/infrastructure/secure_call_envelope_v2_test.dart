import 'dart:convert';

import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_signal_v2.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const _now = 2000000;
const _handle = '33333333-3333-4333-8333-333333333333';
const _call = '22222222-2222-4222-8222-222222222222';
const _negotiation = '44444444-4444-4444-8444-444444444444';
const _switch = '55555555-5555-4555-8555-555555555555';
const _key = 'fixture-signing-key';

String _id(int value) =>
    '11111111-1111-4111-8111-${value.toRadixString(16).padLeft(12, '0')}';

Map<String, Object?> _inner({
  String event = 'invite',
  int id = 1,
  int sequence = 1,
  int generation = 0,
  int created = _now,
  int expires = _now + 40000,
  Map<String, Object?>? payload,
}) => {
  'schema': CallSignalV2.schema,
  'call_id': _call,
  'message_id': _id(id),
  'event': event,
  'sender_account_peer_id': 'sender-account',
  'sender_device_peer_id': 'sender-device',
  'recipient_account_peer_id': 'recipient-account',
  'recipient_device_peer_id': 'recipient-device',
  'sender_sequence': sequence,
  'ice_generation': generation,
  'created_at_ms': created,
  'expires_at_ms': expires,
  'payload': payload ?? _payload(event),
};

Map<String, Object?> _payload(String event) => switch (event) {
  'invite' => {
    'media': 'video',
    'camera': 'off',
    'capabilities': ['audio', 'video'],
  },
  'offer' || 'answer' => {
    'negotiation_id': _negotiation,
    'purpose': 'initial',
    'switch_id': null,
    'media_revision': 0,
    'media': 'video',
    'description': 'opaque-sdp-fixture',
    'fingerprint': 'sha-256 fixture',
  },
  'ice' => {
    'negotiation_id': _negotiation,
    'candidate': 'opaque-ice-fixture',
    'media_id': '0',
    'media_line_index': 0,
  },
  'media_commit' => {
    'switch_id': _switch,
    'media_revision': 1,
    'media': 'video',
  },
  'media_abort' => {
    'switch_id': _switch,
    'base_revision': 0,
    'media_revision': 1,
    'media': 'audio',
    'reason': 'cancelled',
  },
  'terminate' => {'reason': 'caller_cancelled'},
  _ => throw StateError('No fixture for $event'),
};

CallEnvelopeAuthority _authority({
  String transport = 'sender-device',
  String senderAccount = 'sender-account',
  String senderDevice = 'sender-device',
  String recipientAccount = 'recipient-account',
  String recipientDevice = 'recipient-device',
}) => CallEnvelopeAuthority(
  authenticatedTransportPeerId: transport,
  expectedSenderAccountPeerId: senderAccount,
  expectedSenderDevicePeerId: senderDevice,
  expectedRecipientAccountPeerId: recipientAccount,
  expectedRecipientDevicePeerId: recipientDevice,
  senderSigningPublicKey: _key,
  ownMlKemSecretKey: 'fixture-secret',
);

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String _json(Object? value) => jsonEncode(_canonical(value));

final class _Crypto implements CallEnvelopeCrypto {
  int decryptCalls = 0;
  int encryptCalls = 0;
  bool signatureValid = true;
  void Function()? onDecrypt;

  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async {
    encryptCalls++;
    return CallCiphertext(
      kem: base64Encode(utf8.encode('kem:$recipientMlKemPublicKey')),
      ciphertext: base64Encode(utf8.encode(plaintext)),
      nonce: base64Encode(utf8.encode('nonce')),
    );
  }

  @override
  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  }) async {
    decryptCalls++;
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
  }) async =>
      signatureValid &&
      signature ==
          base64Encode(utf8.encode('$senderSigningPublicKey:$canonicalData'));
}

/// Independent signed fixture builder; it does not pass through either parser.
Future<String> _wire(
  Map<String, Object?> inner, {
  String? messageId,
  int? expires,
  String version = '1',
}) async {
  final crypto = _Crypto();
  final encrypted = await crypto.encrypt(
    recipientMlKemPublicKey: 'fixture-public',
    plaintext: _json(inner),
  );
  final unsigned = <String, Object?>{
    'type': 'call_signal',
    'version': version,
    'message_id': messageId ?? inner['message_id'],
    'call_handle': _handle,
    'expires_at_ms': expires ?? inner['expires_at_ms'],
    'kem': encrypted.kem,
    'ciphertext': encrypted.ciphertext,
    'nonce': encrypted.nonce,
  };
  return _json({
    ...unsigned,
    'signature': await crypto.sign(
      senderSigningPrivateKey: _key,
      canonicalData: _json(unsigned),
    ),
  });
}

Matcher _error(CallEnvelopeErrorCode code) => throwsA(
  isA<CallEnvelopeException>().having((error) => error.code, 'code', code),
);

void main() {
  late _Crypto crypto;
  late SecureCallEnvelopeCodec codec;
  late int now;

  setUp(() {
    now = _now;
    crypto = _Crypto();
    codec = SecureCallEnvelopeCodec(
      crypto: crypto,
      nowMs: () => now,
      videoEnabled: true,
    );
  });

  Future<DecodedCallWireEnvelope> admit(Map<String, Object?> inner) async =>
      codec.decodeVersioned(
        envelopeJson: await _wire(inner),
        authority: _authority(),
      );

  Future<String> encodeV2(
    SecureCallEnvelopeCodec target,
    Map<String, Object?> inner,
  ) => target.encodeV2(
    signal: CallSignalV2.fromMap(inner, videoEnabled: true),
    callHandle: _handle,
    recipientMlKemPublicKey: 'fixture-public',
    senderSigningPrivateKey: _key,
  );

  test(
    'v1 encoding and typed decode preserve the existing signed wire',
    () async {
      final inner = {
        ..._inner(),
        'schema': CallSignal.schema,
        'payload': {
          'capabilities': ['audio'],
        },
      };
      final signal = CallSignal.fromMap(inner);
      final encoded = await codec.encode(
        signal: signal,
        callHandle: _handle,
        recipientMlKemPublicKey: 'fixture-public',
        senderSigningPrivateKey: _key,
      );
      expect(encoded, await _wire(inner));
      final decoded = await codec.decode(
        envelopeJson: encoded,
        authority: _authority(),
      );
      expect(decoded.signal.event, CallSignalType.invite);
      expect(decoded.signal.toMap(), inner);
    },
  );

  for (final enabled in [false, true]) {
    test('version dispatcher preserves v1 with video gate $enabled', () async {
      final inner = {
        ..._inner(),
        'schema': CallSignal.schema,
        'payload': {
          'capabilities': ['audio'],
        },
      };
      final target = SecureCallEnvelopeCodec(
        crypto: crypto,
        nowMs: () => now,
        videoEnabled: enabled,
      );
      final decoded = await target.decodeVersioned(
        envelopeJson: await _wire(inner),
        authority: _authority(),
      );
      expect(decoded, isA<DecodedSecureCallEnvelope>());
      expect(decoded.signal.toMap(), inner);
    });
  }

  test('v2 encoder is default off before crypto', () async {
    final target = SecureCallEnvelopeCodec(crypto: crypto, nowMs: () => now);
    await expectLater(
      encodeV2(target, _inner()),
      _error(CallEnvelopeErrorCode.unsupportedVersion),
    );
    expect(crypto.encryptCalls, 0);
  });

  test('v2 encryption preserves the exact existing outer wrapper', () async {
    expect(await encodeV2(codec, _inner()), await _wire(_inner()));
    final decoded = jsonDecode(await encodeV2(codec, _inner())) as Map;
    expect(decoded.keys.toSet(), {
      'type',
      'version',
      'message_id',
      'call_handle',
      'expires_at_ms',
      'kem',
      'ciphertext',
      'nonce',
      'signature',
    });
    expect(decoded['version'], '1');
  });

  test('default dispatcher rejects v2 without reserving its message', () async {
    final store = InMemoryBoundedCallReplayProtectionStore();
    final disabled = SecureCallEnvelopeCodec(
      crypto: crypto,
      nowMs: () => now,
      replayStore: store,
    );
    final enabled = SecureCallEnvelopeCodec(
      crypto: crypto,
      nowMs: () => now,
      replayStore: store,
      videoEnabled: true,
    );
    final wire = await _wire(_inner());
    await expectLater(
      disabled.decodeVersioned(envelopeJson: wire, authority: _authority()),
      _error(CallEnvelopeErrorCode.invalidSchema),
    );
    expect(
      await enabled.decodeVersioned(
        envelopeJson: wire,
        authority: _authority(),
      ),
      isA<DecodedSecureCallEnvelopeV2>(),
    );
  });

  test('legacy decoder stays v1 only even when the codec permits v2', () async {
    final wire = await _wire(_inner());
    await expectLater(
      codec.decode(envelopeJson: wire, authority: _authority()),
      _error(CallEnvelopeErrorCode.invalidSchema),
    );
    expect(
      await codec.decodeVersioned(envelopeJson: wire, authority: _authority()),
      isA<DecodedSecureCallEnvelopeV2>(),
    );
  });

  for (final event in [
    'invite',
    'offer',
    'ice',
    'media_commit',
    'media_abort',
  ]) {
    test(
      'authenticated v2 $event retains its typed payload and routing handle',
      () async {
        final inner = _inner(event: event);
        final decoded = await admit(inner);
        expect(decoded, isA<DecodedSecureCallEnvelopeV2>());
        expect(decoded.signal.toMap(), inner);
        expect(decoded.callHandle, _handle);
      },
    );
  }

  test(
    'signature rejection occurs before decryption and version parsing',
    () async {
      crypto.signatureValid = false;
      await expectLater(
        admit(_inner()),
        _error(CallEnvelopeErrorCode.invalidSignature),
      );
      expect(crypto.decryptCalls, 0);
    },
  );

  test('unknown outer version rejects before decryption', () async {
    await expectLater(
      codec.decodeVersioned(
        envelopeJson: await _wire(_inner(), version: '2'),
        authority: _authority(),
      ),
      _error(CallEnvelopeErrorCode.unsupportedVersion),
    );
    expect(crypto.decryptCalls, 0);
  });

  test('strict v2 payload rejection does not consume replay custody', () async {
    await expectLater(
      admit(_inner(payload: {..._payload('invite'), 'metadata': {}})),
      _error(CallEnvelopeErrorCode.invalidSchema),
    );
    expect(await admit(_inner()), isA<DecodedSecureCallEnvelopeV2>());
  });

  test('unknown inner schema cannot fall through to either parser', () async {
    await expectLater(
      admit({..._inner(), 'schema': 'mknoon.call_signal.v3'}),
      _error(CallEnvelopeErrorCode.invalidSchema),
    );
  });

  final mismatches = <String, CallEnvelopeAuthority>{
    'transport': _authority(transport: 'other-device'),
    'sender account': _authority(senderAccount: 'other-account'),
    'sender device': _authority(senderDevice: 'other-device'),
    'recipient account': _authority(recipientAccount: 'other-account'),
    'recipient device': _authority(recipientDevice: 'other-device'),
  };
  for (final entry in mismatches.entries) {
    test('v2 rejects an authenticated ${entry.key} mismatch', () async {
      await expectLater(
        codec.decodeVersioned(
          envelopeJson: await _wire(_inner()),
          authority: entry.value,
        ),
        _error(CallEnvelopeErrorCode.authorityMismatch),
      );
      expect(await admit(_inner()), isA<DecodedSecureCallEnvelopeV2>());
    });
  }

  test('inner message ID remains bound to the signed wrapper', () async {
    await expectLater(
      codec.decodeVersioned(
        envelopeJson: await _wire(_inner(), messageId: _id(2)),
        authority: _authority(),
      ),
      _error(CallEnvelopeErrorCode.authorityMismatch),
    );
  });

  test('inner expiry remains bound to the signed wrapper', () async {
    await expectLater(
      codec.decodeVersioned(
        envelopeJson: await _wire(_inner(), expires: _now + 41000),
        authority: _authority(),
      ),
      _error(CallEnvelopeErrorCode.authorityMismatch),
    );
  });

  test('expiry is rechecked after asynchronous decryption', () async {
    crypto.onDecrypt = () => now = _now + 40000;
    await expectLater(admit(_inner()), _error(CallEnvelopeErrorCode.expired));
  });

  test(
    'v2 retains the thirty-second authenticated future-clock bound',
    () async {
      await expectLater(
        admit(_inner(created: _now + 30001, expires: _now + 40000)),
        _error(CallEnvelopeErrorCode.excessiveClockSkew),
      );
    },
  );

  test('v2 postconnect lifetime cannot exceed ten minutes', () async {
    await expectLater(
      admit(_inner(event: 'offer', expires: _now + 600001)),
      _error(CallEnvelopeErrorCode.ttlExceeded),
    );
  });

  test(
    'v2 provisional replay can roll back then commit exactly once',
    () async {
      final first = await admit(_inner());
      first.rollbackReplay();
      final second = await admit(_inner());
      second.commitReplay();
      second.rollbackReplay();
      await expectLater(admit(_inner()), _error(CallEnvelopeErrorCode.replay));
    },
  );

  test('v1 and v2 share message-ID conflict custody', () async {
    (await admit(_inner())).commitReplay();
    final v1 = {
      ..._inner(sequence: 2),
      'schema': CallSignal.schema,
      'payload': {
        'capabilities': ['audio'],
      },
    };
    await expectLater(
      codec.decode(envelopeJson: await _wire(v1), authority: _authority()),
      _error(CallEnvelopeErrorCode.messageIdConflict),
    );
  });

  test('different v2 message IDs cannot reuse a sender sequence', () async {
    (await admit(_inner(event: 'offer'))).commitReplay();
    await expectLater(
      admit(_inner(event: 'ice', id: 2)),
      _error(CallEnvelopeErrorCode.nonMonotonicSequence),
    );
  });

  test(
    'same-generation v2 negotiation permits the existing 64-slot reordering',
    () async {
      (await admit(_inner(event: 'ice', sequence: 67))).commitReplay();
      expect(
        await admit(_inner(event: 'offer', sequence: 3, id: 2)),
        isA<DecodedSecureCallEnvelopeV2>(),
      );
    },
  );

  test('v2 negotiation rejects reordering beyond 64 slots', () async {
    (await admit(_inner(event: 'ice', sequence: 67))).commitReplay();
    await expectLater(
      admit(_inner(event: 'offer', sequence: 2, id: 2)),
      _error(CallEnvelopeErrorCode.nonMonotonicSequence),
    );
  });

  test(
    'media abort can reach the transaction owner after a later commit frame',
    () async {
      (await admit(_inner(event: 'media_commit', sequence: 4))).commitReplay();
      expect(
        await admit(_inner(event: 'media_abort', sequence: 3, id: 2)),
        isA<DecodedSecureCallEnvelopeV2>(),
      );
    },
  );

  test(
    'v2 control signals do not gain negotiation reorder permission',
    () async {
      (await admit(_inner(event: 'ice', sequence: 4))).commitReplay();
      await expectLater(
        admit(_inner(event: 'terminate', sequence: 3, id: 2)),
        _error(CallEnvelopeErrorCode.nonMonotonicSequence),
      );
    },
  );

  test('v2 reordering cannot cross an ICE generation', () async {
    (await admit(
      _inner(event: 'ice', sequence: 4, generation: 1),
    )).commitReplay();
    await expectLater(
      admit(_inner(event: 'offer', sequence: 3, id: 2)),
      _error(CallEnvelopeErrorCode.nonMonotonicSequence),
    );
  });

  test('v2 replay custody remains capacity bounded', () async {
    final target = SecureCallEnvelopeCodec(
      crypto: crypto,
      nowMs: () => now,
      replayStore: InMemoryBoundedCallReplayProtectionStore(maxEntries: 2),
      videoEnabled: true,
    );
    final first = await target.decodeVersioned(
      envelopeJson: await _wire(_inner(event: 'offer')),
      authority: _authority(),
    );
    first.commitReplay();
    await expectLater(
      target.decodeVersioned(
        envelopeJson: await _wire(_inner(event: 'ice', id: 2, sequence: 2)),
        authority: _authority(),
      ),
      _error(CallEnvelopeErrorCode.replayStateCapacity),
    );
  });

  test(
    'decoded envelope diagnostics do not expose media or identity material',
    () async {
      final decoded = await admit(_inner(event: 'offer'));
      for (final secret in [
        _call,
        _handle,
        'sender-device',
        'video',
        'opaque-sdp-fixture',
        'sha-256 fixture',
      ]) {
        expect(decoded.toString(), isNot(contains(secret)));
      }
    },
  );
}
