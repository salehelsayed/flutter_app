import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_test/flutter_test.dart';

final class _DeterministicCrypto implements CallEnvelopeCrypto {
  int decryptCalls = 0;
  String? decryptedOverride;
  bool throwOnDecrypt = false;
  bool throwOnVerify = false;

  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async {
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
    decryptCalls += 1;
    if (throwOnDecrypt) throw StateError('fixture crypto failure');
    final override = decryptedOverride;
    if (override != null) return override;
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
    if (throwOnVerify) throw StateError('fixture crypto unavailable');
    return signature ==
        base64Encode(utf8.encode('$senderSigningPublicKey:$canonicalData'));
  }
}

final class _ScriptedBridge extends Bridge {
  _ScriptedBridge(this._reply);

  final Future<String> Function(String command) _reply;

  @override
  bool get isInitialized => true;

  @override
  Future<bool> checkHealth() async => true;

  @override
  void dispose() {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> reinitialize() async {}

  @override
  Future<String> send(String message) {
    final request = jsonDecode(message) as Map<String, dynamic>;
    return _reply(request['cmd']! as String);
  }
}

Future<String> _neverCompletes() => Completer<String>().future;

Future<String> _bridgeResponse(Map<String, Object?> response) async =>
    jsonEncode(response);

const _nowMs = 2_000_000;
const _senderAccount = 'sender-account-peer';
const _senderDevice = 'sender-device-peer';
const _recipientAccount = 'recipient-account-peer';
const _recipientDevice = 'recipient-device-peer';
const _signingKey = 'signing-key';
const _callHandle = '33333333-3333-4333-8333-333333333333';

CallSignal _signal({
  String messageId = '11111111-1111-4111-8111-111111111111',
  int senderSequence = 1,
  String event = 'invite',
  Map<String, Object?> payload = const <String, Object?>{},
  int createdAtMs = _nowMs,
  int expiresAtMs = _nowMs + 45_000,
}) {
  return CallSignal.create(
    callId: CallId.parse('22222222-2222-4222-8222-222222222222'),
    messageId: messageId,
    event: CallSignalType.parse(event),
    senderAccountPeerId: _senderAccount,
    senderDevicePeerId: _senderDevice,
    recipientAccountPeerId: _recipientAccount,
    recipientDevicePeerId: _recipientDevice,
    senderSequence: senderSequence,
    iceGeneration: 0,
    createdAtMs: createdAtMs,
    expiresAtMs: expiresAtMs,
    payload: payload,
  );
}

CallEnvelopeAuthority _authority() => const CallEnvelopeAuthority(
  authenticatedTransportPeerId: _senderDevice,
  expectedSenderAccountPeerId: _senderAccount,
  expectedSenderDevicePeerId: _senderDevice,
  expectedRecipientAccountPeerId: _recipientAccount,
  expectedRecipientDevicePeerId: _recipientDevice,
  senderSigningPublicKey: _signingKey,
  ownMlKemSecretKey: 'recipient-mlkem-secret',
);

String _canonicalFlatJson(Map<String, Object?> value) {
  final keys = value.keys.toList()..sort();
  return jsonEncode(<String, Object?>{for (final key in keys) key: value[key]});
}

Future<String> _encodeUnchecked({
  required _DeterministicCrypto crypto,
  required CallSignal signal,
}) async {
  final encrypted = await crypto.encrypt(
    recipientMlKemPublicKey: 'recipient-mlkem-public',
    plaintext: jsonEncode(signal.toMap()),
  );
  final unsigned = <String, Object?>{
    'type': 'call_signal',
    'version': '1',
    'message_id': signal.messageId,
    'call_handle': _callHandle,
    'expires_at_ms': signal.expiresAtMs,
    'kem': encrypted.kem,
    'ciphertext': encrypted.ciphertext,
    'nonce': encrypted.nonce,
  };
  final signature = await crypto.sign(
    senderSigningPrivateKey: _signingKey,
    canonicalData: _canonicalFlatJson(unsigned),
  );
  return jsonEncode(<String, Object?>{...unsigned, 'signature': signature});
}

void main() {
  late _DeterministicCrypto crypto;
  late SecureCallEnvelopeCodec codec;

  setUp(() {
    crypto = _DeterministicCrypto();
    codec = SecureCallEnvelopeCodec(crypto: crypto, nowMs: () => _nowMs);
  });

  test(
    'round trips a signed encrypted versioned device-targeted signal',
    () async {
      final encoded = await codec.encode(
        signal: _signal(),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );

      final outer = jsonDecode(encoded) as Map<String, dynamic>;
      expect(outer.keys.toSet(), <String>{
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
      expect(outer['type'], 'call_signal');
      expect(outer['version'], '1');
      expect(encoded, isNot(contains(_senderAccount)));
      expect(encoded, isNot(contains(_recipientAccount)));

      final decoded = await codec.decode(
        envelopeJson: encoded,
        authority: _authority(),
      );
      expect(decoded.callHandle, _callHandle);
      expect(decoded.signal.event, CallSignalType.invite);
      expect(decoded.signal.senderDevicePeerId, _senderDevice);
      expect(decoded.signal.recipientDevicePeerId, _recipientDevice);
    },
  );

  test('rejects an unknown outer field before decryption', () async {
    final encoded = await codec.encode(
      signal: _signal(),
      callHandle: _callHandle,
      recipientMlKemPublicKey: 'recipient-mlkem-public',
      senderSigningPrivateKey: _signingKey,
    );
    final outer = jsonDecode(encoded) as Map<String, dynamic>;
    outer['sender_peer_id'] = _senderDevice;

    await expectLater(
      codec.decode(envelopeJson: jsonEncode(outer), authority: _authority()),
      throwsA(
        isA<CallEnvelopeException>().having(
          (error) => error.code,
          'code',
          CallEnvelopeErrorCode.invalidSchema,
        ),
      ),
    );
    expect(crypto.decryptCalls, 0);
  });

  test(
    'rejects invalid signature before decryption with privacy-safe error',
    () async {
      final encoded = await codec.encode(
        signal: _signal(),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );
      final outer = jsonDecode(encoded) as Map<String, dynamic>;
      outer['signature'] = base64Encode(utf8.encode('forged'));

      Object? captured;
      try {
        await codec.decode(
          envelopeJson: jsonEncode(outer),
          authority: _authority(),
        );
      } catch (error) {
        captured = error;
      }

      expect(captured, isA<CallEnvelopeException>());
      expect(
        (captured! as CallEnvelopeException).code,
        CallEnvelopeErrorCode.invalidSignature,
      );
      expect(captured.toString(), isNot(contains(_senderAccount)));
      expect(
        captured.toString(),
        isNot(contains(outer['ciphertext'] as String)),
      );
      expect(crypto.decryptCalls, 0);
    },
  );

  test('binds transport peer, sender, recipient account, and device', () async {
    final encoded = await codec.encode(
      signal: _signal(),
      callHandle: _callHandle,
      recipientMlKemPublicKey: 'recipient-mlkem-public',
      senderSigningPrivateKey: _signingKey,
    );

    for (final authority in <CallEnvelopeAuthority>[
      CallEnvelopeAuthority(
        authenticatedTransportPeerId: 'other-transport-peer',
        expectedSenderAccountPeerId: _senderAccount,
        expectedSenderDevicePeerId: _senderDevice,
        expectedRecipientAccountPeerId: _recipientAccount,
        expectedRecipientDevicePeerId: _recipientDevice,
        senderSigningPublicKey: _signingKey,
        ownMlKemSecretKey: 'recipient-mlkem-secret',
      ),
      CallEnvelopeAuthority(
        authenticatedTransportPeerId: _senderDevice,
        expectedSenderAccountPeerId: _senderAccount,
        expectedSenderDevicePeerId: _senderDevice,
        expectedRecipientAccountPeerId: _recipientAccount,
        expectedRecipientDevicePeerId: 'wrong-recipient-device',
        senderSigningPublicKey: _signingKey,
        ownMlKemSecretKey: 'recipient-mlkem-secret',
      ),
    ]) {
      final freshCodec = SecureCallEnvelopeCodec(
        crypto: crypto,
        nowMs: () => _nowMs,
      );
      await expectLater(
        freshCodec.decode(envelopeJson: encoded, authority: authority),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.authorityMismatch,
          ),
        ),
      );
    }
  });

  test(
    'rejects duplicate message IDs and non-monotonic sender sequence',
    () async {
      final first = await codec.encode(
        signal: _signal(),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );
      await codec.decode(envelopeJson: first, authority: _authority());

      await expectLater(
        codec.decode(envelopeJson: first, authority: _authority()),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.replay,
          ),
        ),
      );

      final staleSequence = await codec.encode(
        signal: _signal(
          messageId: '44444444-4444-4444-8444-444444444444',
          senderSequence: 1,
        ),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );
      await expectLater(
        codec.decode(envelopeJson: staleSequence, authority: _authority()),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.nonMonotonicSequence,
          ),
        ),
      );
    },
  );

  test(
    'accepts distinct authenticated signals that arrive out of sequence',
    () async {
      final laterIce = await codec.encode(
        signal: _signal(
          messageId: '88888888-8888-4888-8888-888888888888',
          senderSequence: 7,
          event: 'ice',
          payload: const <String, Object?>{'candidate': 'candidate:later'},
        ),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );
      final earlierOffer = await codec.encode(
        signal: _signal(
          messageId: '99999999-9999-4999-8999-999999999999',
          senderSequence: 6,
          event: 'offer',
          payload: const <String, Object?>{
            'description': 'v=0',
            'fingerprint': 'sha-256 AA:BB',
          },
        ),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );

      final admittedIce = await codec.decode(
        envelopeJson: laterIce,
        authority: _authority(),
      );
      admittedIce.commitReplay();

      final admittedOffer = await codec.decode(
        envelopeJson: earlierOffer,
        authority: _authority(),
      );
      expect(admittedOffer.signal.event, CallSignalType.offer);
      admittedOffer.commitReplay();

      await expectLater(
        codec.decode(envelopeJson: laterIce, authority: _authority()),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.replay,
          ),
        ),
      );

      final reusedSequence = await codec.encode(
        signal: _signal(
          messageId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          senderSequence: 6,
          event: 'ice',
          payload: const <String, Object?>{'candidate': 'candidate:reused'},
        ),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );
      await expectLater(
        codec.decode(envelopeJson: reusedSequence, authority: _authority()),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.nonMonotonicSequence,
          ),
        ),
      );
    },
  );

  test(
    'bounds negotiation reordering and keeps control signals strictly ordered',
    () async {
      Future<String> encodeFor(
        SecureCallEnvelopeCodec target, {
        required String messageId,
        required int senderSequence,
        required String event,
        required Map<String, Object?> payload,
      }) => target.encode(
        signal: _signal(
          messageId: messageId,
          senderSequence: senderSequence,
          event: event,
          payload: payload,
        ),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );

      final boundedCodec = SecureCallEnvelopeCodec(
        crypto: crypto,
        nowMs: () => _nowMs,
      );
      final highIce = await encodeFor(
        boundedCodec,
        messageId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        senderSequence: CallSignal.maximumNegotiationReorderingDistance + 2,
        event: 'ice',
        payload: const <String, Object?>{'candidate': 'candidate:high'},
      );
      (await boundedCodec.decode(
        envelopeJson: highIce,
        authority: _authority(),
      )).commitReplay();
      final tooOldOffer = await encodeFor(
        boundedCodec,
        messageId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        senderSequence: 1,
        event: 'offer',
        payload: const <String, Object?>{
          'description': 'v=0',
          'fingerprint': 'sha-256 CC:DD',
        },
      );
      await expectLater(
        boundedCodec.decode(envelopeJson: tooOldOffer, authority: _authority()),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.nonMonotonicSequence,
          ),
        ),
      );

      final controlCodec = SecureCallEnvelopeCodec(
        crypto: crypto,
        nowMs: () => _nowMs,
      );
      final controlHighIce = await encodeFor(
        controlCodec,
        messageId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        senderSequence: 3,
        event: 'ice',
        payload: const <String, Object?>{'candidate': 'candidate:control'},
      );
      (await controlCodec.decode(
        envelopeJson: controlHighIce,
        authority: _authority(),
      )).commitReplay();
      final reorderedAccept = await encodeFor(
        controlCodec,
        messageId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        senderSequence: 2,
        event: 'accept',
        payload: const <String, Object?>{},
      );
      await expectLater(
        controlCodec.decode(
          envelopeJson: reorderedAccept,
          authority: _authority(),
        ),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.nonMonotonicSequence,
          ),
        ),
      );
    },
  );

  test(
    'exact bytes duplicate and changed bytes with the same signed ID reject',
    () async {
      final original = await codec.encode(
        signal: _signal(),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );
      final admitted = await codec.decode(
        envelopeJson: original,
        authority: _authority(),
      );
      admitted.commitReplay();

      final exactCopy = String.fromCharCodes(original.codeUnits);
      expect(exactCopy, original);
      await expectLater(
        codec.decode(envelopeJson: exactCopy, authority: _authority()),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.replay,
          ),
        ),
      );

      final changedAndResigned = await codec.encode(
        signal: _signal(
          senderSequence: 2,
          payload: const <String, Object?>{
            'metadata': <String, Object?>{'changed': true},
          },
        ),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );
      expect(changedAndResigned, isNot(original));
      await expectLater(
        codec.decode(envelopeJson: changedAndResigned, authority: _authority()),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.messageIdConflict,
          ),
        ),
      );
    },
  );

  test('rejects expired, oversized, and invite SDP payloads', () async {
    final expiredCodec = SecureCallEnvelopeCodec(
      crypto: crypto,
      nowMs: () => _nowMs + 45_001,
    );
    final expired = await codec.encode(
      signal: _signal(),
      callHandle: _callHandle,
      recipientMlKemPublicKey: 'recipient-mlkem-public',
      senderSigningPrivateKey: _signingKey,
    );
    await expectLater(
      expiredCodec.decode(envelopeJson: expired, authority: _authority()),
      throwsA(
        isA<CallEnvelopeException>().having(
          (error) => error.code,
          'code',
          CallEnvelopeErrorCode.expired,
        ),
      ),
    );

    expect(
      () => _signal(payload: <String, Object?>{'sdp': 'v=0'}),
      throwsFormatException,
    );

    await expectLater(
      codec.decode(
        envelopeJson: 'x' * (SecureCallEnvelopeCodec.maxSignalBytes + 1),
        authority: _authority(),
      ),
      throwsA(
        isA<CallEnvelopeException>().having(
          (error) => error.code,
          'code',
          CallEnvelopeErrorCode.oversized,
        ),
      ),
    );
  });

  test('requires an authenticated fingerprint in offer and answer', () async {
    for (final event in <String>['offer', 'answer']) {
      await expectLater(
        Future<void>.sync(() {
          _signal(
            messageId: event == 'offer'
                ? '55555555-5555-4555-8555-555555555555'
                : '66666666-6666-4666-8666-666666666666',
            event: event,
            payload: const <String, Object?>{'description': 'opaque'},
          );
        }),
        throwsFormatException,
      );
    }
  });

  test(
    'bounded replay store fails closed instead of growing without limit',
    () async {
      final bounded = SecureCallEnvelopeCodec(
        crypto: crypto,
        nowMs: () => _nowMs,
        replayStore: InMemoryBoundedCallReplayProtectionStore(maxEntries: 2),
      );
      final first = await bounded.encode(
        signal: _signal(),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );
      await bounded.decode(envelopeJson: first, authority: _authority());

      final second = await bounded.encode(
        signal: _signal(
          messageId: '77777777-7777-4777-8777-777777777777',
          senderSequence: 2,
        ),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );
      await expectLater(
        bounded.decode(envelopeJson: second, authority: _authority()),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.replayStateCapacity,
          ),
        ),
      );
    },
  );

  test(
    'rejects malformed JSON, base64, crypto failure, type, and version',
    () async {
      await expectLater(
        codec.decode(envelopeJson: '{', authority: _authority()),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.invalidSchema,
          ),
        ),
      );

      final encoded = await codec.encode(
        signal: _signal(),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );
      final original = jsonDecode(encoded) as Map<String, dynamic>;
      for (final mutation in <Map<String, dynamic> Function()>[
        () => <String, dynamic>{...original, 'kem': '*not-base64*'},
        () => <String, dynamic>{...original, 'type': 'chat_message'},
        () => <String, dynamic>{...original, 'version': '2'},
      ]) {
        final candidate = mutation();
        final expected = candidate['type'] != 'call_signal'
            ? CallEnvelopeErrorCode.invalidSchema
            : candidate['version'] != '1'
            ? CallEnvelopeErrorCode.unsupportedVersion
            : CallEnvelopeErrorCode.invalidCryptoFields;
        await expectLater(
          SecureCallEnvelopeCodec(crypto: crypto, nowMs: () => _nowMs).decode(
            envelopeJson: jsonEncode(candidate),
            authority: _authority(),
          ),
          throwsA(
            isA<CallEnvelopeException>().having(
              (error) => error.code,
              'code',
              expected,
            ),
          ),
        );
      }

      for (final phase in <String>['verify', 'decrypt']) {
        crypto.throwOnVerify = phase == 'verify';
        crypto.throwOnDecrypt = phase == 'decrypt';
        await expectLater(
          SecureCallEnvelopeCodec(
            crypto: crypto,
            nowMs: () => _nowMs,
          ).decode(envelopeJson: encoded, authority: _authority()),
          throwsA(
            isA<CallEnvelopeException>().having(
              (error) => error.code,
              'code',
              CallEnvelopeErrorCode.cryptoUnavailable,
            ),
          ),
          reason: phase,
        );
      }
      crypto.throwOnVerify = false;
      crypto.throwOnDecrypt = false;
    },
  );

  test(
    'production bridge crypto keeps unavailability transient and forgery permanent',
    () async {
      final encoded = await codec.encode(
        signal: _signal(),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );

      Future<void> expectCode(
        _ScriptedBridge bridge,
        CallEnvelopeErrorCode expected,
      ) async {
        final productionCodec = SecureCallEnvelopeCodec(
          crypto: BridgeCallEnvelopeCrypto(
            bridge: bridge,
            timeout: const Duration(milliseconds: 1),
          ),
          nowMs: () => _nowMs,
        );
        await expectLater(
          productionCodec.decode(
            envelopeJson: encoded,
            authority: _authority(),
          ),
          throwsA(
            isA<CallEnvelopeException>().having(
              (error) => error.code,
              'code',
              expected,
            ),
          ),
        );
      }

      await expectCode(
        _ScriptedBridge((_) => _neverCompletes()),
        CallEnvelopeErrorCode.cryptoUnavailable,
      );
      await expectCode(
        _ScriptedBridge(
          (_) => _bridgeResponse(const <String, Object?>{
            'ok': false,
            'errorCode': 'PLATFORM_ERROR',
          }),
        ),
        CallEnvelopeErrorCode.cryptoUnavailable,
      );
      await expectCode(
        _ScriptedBridge(
          (_) => _bridgeResponse(const <String, Object?>{
            'ok': true,
            'valid': false,
          }),
        ),
        CallEnvelopeErrorCode.invalidSignature,
      );
      await expectCode(
        _ScriptedBridge(
          (command) => command == 'payload.verify'
              ? _bridgeResponse(const <String, Object?>{
                  'ok': true,
                  'valid': true,
                })
              : _neverCompletes(),
        ),
        CallEnvelopeErrorCode.cryptoUnavailable,
      );
      await expectCode(
        _ScriptedBridge(
          (command) => command == 'payload.verify'
              ? _bridgeResponse(const <String, Object?>{
                  'ok': true,
                  'valid': true,
                })
              : _bridgeResponse(const <String, Object?>{
                  'ok': false,
                  'errorCode': 'DECRYPT_FAILED',
                }),
        ),
        CallEnvelopeErrorCode.decryptionFailed,
      );
    },
  );

  test(
    'binds outer message ID and expiry to the authenticated inner',
    () async {
      final encoded = await codec.encode(
        signal: _signal(),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );
      for (final mutate in <void Function(Map<String, Object?>)>[
        (inner) => inner['message_id'] = '44444444-4444-4444-8444-444444444444',
        (inner) => inner['expires_at_ms'] = _nowMs + 44_000,
      ]) {
        final inner = _signal().toMap();
        mutate(inner);
        crypto.decryptedOverride = jsonEncode(inner);
        await expectLater(
          SecureCallEnvelopeCodec(
            crypto: crypto,
            nowMs: () => _nowMs,
          ).decode(envelopeJson: encoded, authority: _authority()),
          throwsA(
            isA<CallEnvelopeException>().having(
              (error) => error.code,
              'code',
              CallEnvelopeErrorCode.authorityMismatch,
            ),
          ),
        );
      }
    },
  );

  test(
    'rejects invalid 128-bit identifiers, unknown inner fields, and future skew',
    () async {
      expect(
        () => codec.encode(
          signal: _signal(),
          callHandle: 'not-a-uuid-v4',
          recipientMlKemPublicKey: 'recipient-mlkem-public',
          senderSigningPrivateKey: _signingKey,
        ),
        throwsA(isA<CallEnvelopeException>()),
      );
      for (final mutate in <void Function(Map<String, Object?>)>[
        (inner) => inner['call_id'] = 'not-a-uuid-v4',
        (inner) => inner['message_id'] = 'not-a-uuid-v4',
        (inner) => inner['unknown'] = true,
      ]) {
        final signal = _signal();
        final encoded = await codec.encode(
          signal: signal,
          callHandle: _callHandle,
          recipientMlKemPublicKey: 'recipient-mlkem-public',
          senderSigningPrivateKey: _signingKey,
        );
        final inner = signal.toMap();
        mutate(inner);
        crypto.decryptedOverride = jsonEncode(inner);
        await expectLater(
          SecureCallEnvelopeCodec(
            crypto: crypto,
            nowMs: () => _nowMs,
          ).decode(envelopeJson: encoded, authority: _authority()),
          throwsA(
            isA<CallEnvelopeException>().having(
              (error) => error.code,
              'code',
              CallEnvelopeErrorCode.invalidSchema,
            ),
          ),
        );
      }

      crypto.decryptedOverride = null;
      final atFutureSkewLimit = _signal(
        event: 'offer',
        messageId: '77777777-7777-4777-8777-777777777777',
        createdAtMs: _nowMs + 30_000,
        expiresAtMs: _nowMs + 90_000,
        payload: const <String, Object?>{
          'description': 'opaque-offer',
          'fingerprint': 'sha-256 fixture',
        },
      );
      await expectLater(
        codec.encode(
          signal: atFutureSkewLimit,
          callHandle: _callHandle,
          recipientMlKemPublicKey: 'recipient-mlkem-public',
          senderSigningPrivateKey: _signingKey,
        ),
        completes,
      );

      final future = _signal(
        event: 'offer',
        messageId: '88888888-8888-4888-8888-888888888888',
        createdAtMs: _nowMs + 30_001,
        expiresAtMs: _nowMs + 90_000,
        payload: const <String, Object?>{
          'description': 'opaque-offer',
          'fingerprint': 'sha-256 fixture',
        },
      );
      await expectLater(
        codec.encode(
          signal: future,
          callHandle: _callHandle,
          recipientMlKemPublicKey: 'recipient-mlkem-public',
          senderSigningPrivateKey: _signingKey,
        ),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.excessiveClockSkew,
          ),
        ),
      );
    },
  );

  test('the encoded envelope byte bound is inclusive at 96 KiB', () async {
    final exactlyAtBound =
        '{${' ' * (SecureCallEnvelopeCodec.maxSignalBytes - 1)}';
    expect(utf8.encode(exactlyAtBound), hasLength(96 * 1024));
    await expectLater(
      codec.decode(envelopeJson: exactlyAtBound, authority: _authority()),
      throwsA(
        isA<CallEnvelopeException>().having(
          (error) => error.code,
          'code',
          CallEnvelopeErrorCode.invalidSchema,
        ),
      ),
    );
    await expectLater(
      codec.decode(envelopeJson: '$exactlyAtBound ', authority: _authority()),
      throwsA(
        isA<CallEnvelopeException>().having(
          (error) => error.code,
          'code',
          CallEnvelopeErrorCode.oversized,
        ),
      ),
    );
  });

  test(
    'offer and answer fingerprints authenticate and ciphertext tamper fails',
    () async {
      for (final event in <String>['offer', 'answer']) {
        final encoded = await codec.encode(
          signal: _signal(
            messageId: event == 'offer'
                ? '55555555-5555-4555-8555-555555555555'
                : '66666666-6666-4666-8666-666666666666',
            event: event,
            payload: const <String, Object?>{
              'description': 'opaque-session-description',
              'fingerprint': 'sha-256 authenticated-fixture',
            },
          ),
          callHandle: _callHandle,
          recipientMlKemPublicKey: 'recipient-mlkem-public',
          senderSigningPrivateKey: _signingKey,
        );
        final fresh = SecureCallEnvelopeCodec(
          crypto: crypto,
          nowMs: () => _nowMs,
        );
        final decoded = await fresh.decode(
          envelopeJson: encoded,
          authority: _authority(),
        );
        expect(decoded.signal.payload['fingerprint'], contains('sha-256'));

        final tampered = jsonDecode(encoded) as Map<String, dynamic>;
        tampered['ciphertext'] = base64Encode(utf8.encode('tampered'));
        await expectLater(
          SecureCallEnvelopeCodec(
            crypto: crypto,
            nowMs: () => _nowMs,
          ).decode(envelopeJson: jsonEncode(tampered), authority: _authority()),
          throwsA(
            isA<CallEnvelopeException>().having(
              (error) => error.code,
              'code',
              CallEnvelopeErrorCode.invalidSignature,
            ),
          ),
        );
      }
    },
  );

  test(
    'all sender and recipient authority mismatches are detail-free',
    () async {
      final encoded = await codec.encode(
        signal: _signal(),
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );
      for (final authority in <CallEnvelopeAuthority>[
        const CallEnvelopeAuthority(
          authenticatedTransportPeerId: _senderDevice,
          expectedSenderAccountPeerId: 'wrong-sender-account',
          expectedSenderDevicePeerId: _senderDevice,
          expectedRecipientAccountPeerId: _recipientAccount,
          expectedRecipientDevicePeerId: _recipientDevice,
          senderSigningPublicKey: _signingKey,
          ownMlKemSecretKey: 'recipient-mlkem-secret',
        ),
        const CallEnvelopeAuthority(
          authenticatedTransportPeerId: _senderDevice,
          expectedSenderAccountPeerId: _senderAccount,
          expectedSenderDevicePeerId: 'wrong-sender-device',
          expectedRecipientAccountPeerId: _recipientAccount,
          expectedRecipientDevicePeerId: _recipientDevice,
          senderSigningPublicKey: _signingKey,
          ownMlKemSecretKey: 'recipient-mlkem-secret',
        ),
        const CallEnvelopeAuthority(
          authenticatedTransportPeerId: _senderDevice,
          expectedSenderAccountPeerId: _senderAccount,
          expectedSenderDevicePeerId: _senderDevice,
          expectedRecipientAccountPeerId: 'wrong-recipient-account',
          expectedRecipientDevicePeerId: _recipientDevice,
          senderSigningPublicKey: _signingKey,
          ownMlKemSecretKey: 'recipient-mlkem-secret',
        ),
        const CallEnvelopeAuthority(
          authenticatedTransportPeerId: _senderDevice,
          expectedSenderAccountPeerId: _senderAccount,
          expectedSenderDevicePeerId: _senderDevice,
          expectedRecipientAccountPeerId: _recipientAccount,
          expectedRecipientDevicePeerId: 'wrong-recipient-device',
          senderSigningPublicKey: _signingKey,
          ownMlKemSecretKey: 'recipient-mlkem-secret',
        ),
      ]) {
        Object? captured;
        try {
          await SecureCallEnvelopeCodec(
            crypto: crypto,
            nowMs: () => _nowMs,
          ).decode(envelopeJson: encoded, authority: authority);
        } catch (error) {
          captured = error;
        }
        expect(captured, isA<CallEnvelopeException>());
        expect(
          (captured! as CallEnvelopeException).code,
          CallEnvelopeErrorCode.authorityMismatch,
        );
        expect(captured.toString(), isNot(contains('wrong-')));
        expect(captured.toString(), isNot(contains(_senderDevice)));
      }
    },
  );

  test(
    'postconnect validity is capped at the ten-minute protocol bound',
    () async {
      final tooLong = _signal(
        event: 'offer',
        expiresAtMs: _nowMs + const Duration(minutes: 20).inMilliseconds,
        payload: const <String, Object?>{
          'description': 'opaque-offer',
          'fingerprint': 'sha-256 fixture',
        },
      );
      await expectLater(
        codec.encode(
          signal: tooLong,
          callHandle: _callHandle,
          recipientMlKemPublicKey: 'recipient-mlkem-public',
          senderSigningPrivateKey: _signingKey,
        ),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.ttlExceeded,
          ),
        ),
      );

      final atBound = _signal(
        event: 'offer',
        expiresAtMs: _nowMs + const Duration(minutes: 10).inMilliseconds,
        payload: const <String, Object?>{
          'description': 'opaque-offer',
          'fingerprint': 'sha-256 fixture',
        },
      );
      await expectLater(
        codec.encode(
          signal: atBound,
          callHandle: _callHandle,
          recipientMlKemPublicKey: 'recipient-mlkem-public',
          senderSigningPrivateKey: _signingKey,
        ),
        completes,
      );
    },
  );

  test(
    'signed far-future expiry rejects before decrypt or DateTime conversion',
    () async {
      final farFuture = _signal(
        event: 'offer',
        expiresAtMs: 9000000000000000,
        payload: const <String, Object?>{
          'description': 'opaque-offer',
          'fingerprint': 'sha-256 fixture',
        },
      );
      final signed = await _encodeUnchecked(crypto: crypto, signal: farFuture);

      await expectLater(
        codec.decode(envelopeJson: signed, authority: _authority()),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.ttlExceeded,
          ),
        ),
      );
      expect(crypto.decryptCalls, 0);
    },
  );

  test(
    'replay reservations roll back or retain through accepted expiry',
    () async {
      var now = _nowMs;
      final longLivedSignal = _signal(
        event: 'offer',
        createdAtMs: _nowMs + const Duration(seconds: 30).inMilliseconds,
        expiresAtMs:
            _nowMs + const Duration(minutes: 10, seconds: 30).inMilliseconds,
        payload: const <String, Object?>{
          'description': 'opaque-offer',
          'fingerprint': 'sha-256 fixture',
        },
      );
      final replayCodec = SecureCallEnvelopeCodec(
        crypto: crypto,
        nowMs: () => now,
      );
      final encoded = await replayCodec.encode(
        signal: longLivedSignal,
        callHandle: _callHandle,
        recipientMlKemPublicKey: 'recipient-mlkem-public',
        senderSigningPrivateKey: _signingKey,
      );

      final provisional = await replayCodec.decode(
        envelopeJson: encoded,
        authority: _authority(),
      );
      provisional.rollbackReplay();
      final committed = await replayCodec.decode(
        envelopeJson: encoded,
        authority: _authority(),
      );
      committed.commitReplay();

      now += const Duration(minutes: 10).inMilliseconds;
      await expectLater(
        replayCodec.decode(envelopeJson: encoded, authority: _authority()),
        throwsA(
          isA<CallEnvelopeException>().having(
            (error) => error.code,
            'code',
            CallEnvelopeErrorCode.replay,
          ),
        ),
      );
      expect(
        () => SecureCallEnvelopeCodec(
          crypto: crypto,
          nowMs: () => now,
          replayTombstoneTtl: const Duration(minutes: 9),
        ),
        throwsArgumentError,
      );
    },
  );
}
