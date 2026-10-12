import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_app/features/update_check/domain/update_check_keys.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/version_file_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as nacl;

import '../support/update_check_test_keys.dart';

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

VersionFileCheck _verify(
  List<int> bytes, {
  int highestAcceptedRank = 0,
  Set<UpdatePlatform> platforms = const {UpdatePlatform.ios},
  VersionFileVerifier? verifier,
}) => (verifier ?? testVerifier()).verify(
  bytes,
  highestAcceptedRank: highestAcceptedRank,
  requiredPlatforms: platforms,
);

void main() {
  group('RFC 8032 Ed25519 test vectors (pinenacl)', () {
    // RFC 8032 section 7.1, TEST 1-3.
    const vectors = [
      (
        secret:
            '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
        public:
            'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
        message: '',
        signature:
            'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
            '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
      ),
      (
        secret:
            '4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb',
        public:
            '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
        message: '72',
        signature:
            '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da'
            '085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00',
      ),
      (
        secret:
            'c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7',
        public:
            'fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025',
        message: 'af82',
        signature:
            '6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac'
            '18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a',
      ),
    ];

    for (final (index, v) in vectors.indexed) {
      test('TEST ${index + 1}: key, signature and verify match', () {
        final key = nacl.SigningKey.fromSeed(_hex(v.secret));
        expect(key.verifyKey.asTypedList, _hex(v.public));
        final signature = key.sign(_hex(v.message)).signature.asTypedList;
        expect(signature, _hex(v.signature));
        expect(
          verifyEd25519(
            publicKey: _hex(v.public),
            message: _hex(v.message),
            signature: _hex(v.signature),
          ),
          isTrue,
        );
        final flipped = _hex(v.signature)..[0] ^= 0x01;
        expect(
          verifyEd25519(
            publicKey: _hex(v.public),
            message: _hex(v.message),
            signature: flipped,
          ),
          isFalse,
        );
      });
    }
  });

  group('envelope verification (AC2)', () {
    test('a valid envelope passes and parses the payload', () {
      final check = _verify(signedEnvelope(payloadBytes()));
      expect(check.isAccepted, isTrue);
      expect(check.file!.keyId, 'k1');
      expect(check.file!.rank, 1);
      expect(check.file!.payload.platforms[UpdatePlatform.ios]!.minBuild, 100);
    });

    test('changing one payload byte fails the signature', () {
      final payload = payloadBytes();
      final signature = testOnlyK1.sign(payload).signature.asTypedList;
      final tampered = Uint8List.fromList(payload)..[payload.length - 2] ^= 1;
      final envelope = encodeVersionEnvelope(
        keyId: 'k1',
        payloadBytes: tampered,
        signature: signature,
      );
      expect(_verify(envelope).rejection, VersionFileRejection.badSignature);
    });

    test('changing one signature byte fails', () {
      final payload = payloadBytes();
      final signature = testOnlyK1.sign(payload).signature.asTypedList;
      final tampered = Uint8List.fromList(signature)..[10] ^= 0x80;
      final envelope = encodeVersionEnvelope(
        keyId: 'k1',
        payloadBytes: payload,
        signature: tampered,
      );
      expect(_verify(envelope).rejection, VersionFileRejection.badSignature);
    });

    test('a key that is not built in is ignored', () {
      final envelope = signedEnvelope(
        payloadBytes(),
        keyId: 'k3',
        signer: testOnlyRogue,
      );
      expect(_verify(envelope).rejection, VersionFileRejection.unknownKey);
    });

    test('a known keyId signed by another key fails', () {
      final envelope = signedEnvelope(payloadBytes(), signer: testOnlyRogue);
      expect(_verify(envelope).rejection, VersionFileRejection.badSignature);
    });

    test('unsigned, bad base64 and malformed JSON are ignored', () {
      final payload = base64.encode(payloadBytes());
      final good = base64.encode(
        testOnlyK1.sign(payloadBytes()).signature.asTypedList,
      );
      final cases = <String, Object>{
        'unsigned': {'v': 1, 'keyId': 'k1', 'payload': payload},
        'empty sig': {'v': 1, 'keyId': 'k1', 'payload': payload, 'sig': ''},
        'bad base64 payload': {
          'v': 1,
          'keyId': 'k1',
          'payload': '@@not base64@@',
          'sig': good,
        },
        'unpadded base64 sig': {
          'v': 1,
          'keyId': 'k1',
          'payload': payload,
          'sig': good.replaceAll('=', ''),
        },
        'wrong version': {
          'v': 2,
          'keyId': 'k1',
          'payload': payload,
          'sig': good,
        },
        'non-string keyId': {
          'v': 1,
          'keyId': 1,
          'payload': payload,
          'sig': good,
        },
        'array': [1, 2, 3],
      };
      for (final entry in cases.entries) {
        final bytes = utf8.encode(jsonEncode(entry.value));
        final rejection = _verify(bytes).rejection;
        expect(
          rejection,
          anyOf(
            VersionFileRejection.malformedEnvelope,
            VersionFileRejection.badSignature,
          ),
          reason: entry.key,
        );
      }
      expect(
        _verify(utf8.encode('{"v":1,')).rejection,
        VersionFileRejection.malformedEnvelope,
      );
      expect(
        _verify([0xff, 0xfe, 0x00]).rejection,
        VersionFileRejection.malformedEnvelope,
      );
    });

    test('more than 16 KB is rejected before parsing', () {
      final big = Uint8List(maxVersionFileBytes + 1);
      expect(_verify(big).rejection, VersionFileRejection.tooLarge);
    });

    test('a key ranked below the stored rank is refused before verify', () {
      final envelope = signedEnvelope(payloadBytes(sequence: 999999));
      expect(
        _verify(envelope, highestAcceptedRank: 2).rejection,
        VersionFileRejection.rankBelowStored,
      );
    });
  });

  group('payload rules (AC1 parse side)', () {
    test('unknown schemaVersion is ignored', () {
      final envelope = signedEnvelope(payloadBytes(schemaVersion: 2));
      expect(
        _verify(envelope).rejection,
        VersionFileRejection.unsupportedSchema,
      );
    });

    test('missing platform section is ignored', () {
      final envelope = signedEnvelope(payloadBytes(ios: null));
      expect(_verify(envelope).rejection, VersionFileRejection.missingPlatform);
      // The other platform still accepts it.
      expect(
        _verify(envelope, platforms: {UpdatePlatform.android}).isAccepted,
        isTrue,
      );
    });

    test('minBuild > latestBuild is ignored', () {
      final envelope = signedEnvelope(payloadBytes(ios: section(100, 101)));
      expect(_verify(envelope).rejection, VersionFileRejection.minAboveLatest);
    });

    test('negative, fractional or string integers are ignored', () {
      for (final bad in [
        section(-1, 0),
        {'latestBuild': 120.0, 'minBuild': 100},
        {'latestBuild': '120', 'minBuild': 100},
      ]) {
        final envelope = signedEnvelope(payloadBytes(ios: bad));
        expect(
          _verify(envelope).rejection,
          VersionFileRejection.malformedPayload,
          reason: '$bad',
        );
      }
      expect(
        _verify(signedEnvelope(payloadBytes(sequence: -1))).rejection,
        VersionFileRejection.malformedPayload,
      );
    });

    test('unknown or missing reasonCode maps to general', () {
      for (final reason in ['brand_new_reason', null, 7]) {
        final check = _verify(
          signedEnvelope(payloadBytes(ios: section(120, 100, reason))),
        );
        expect(
          check.file!.payload.platforms[UpdatePlatform.ios]!.reasonCode,
          UpdateReasonCode.general,
        );
      }
      final security = _verify(
        signedEnvelope(payloadBytes(ios: section(120, 100, 'protocol_change'))),
      );
      expect(
        security.file!.payload.platforms[UpdatePlatform.ios]!.reasonCode,
        UpdateReasonCode.protocolChange,
      );
    });
  });

  group('sequence ratchet (AC3, AC4e)', () {
    VerifiedVersionFile file(
      int sequence, {
      String keyId = 'k1',
      int? latest,
    }) => _verify(
      signedEnvelope(
        payloadBytes(sequence: sequence, ios: section(latest ?? 120, 100)),
        keyId: keyId,
      ),
    ).file!;

    test('lower sequence in the same rank is ignored', () {
      final stored = file(5);
      expect(
        decideVersionFileRatchet(
          candidate: file(4),
          highestAcceptedRank: 1,
          storedSequence: 5,
          storedPayloadBytes: stored.payloadBytes,
        ),
        VersionFileRatchet.ignore,
      );
    });

    test('higher sequence in the same rank is accepted', () {
      final stored = file(5);
      expect(
        decideVersionFileRatchet(
          candidate: file(6),
          highestAcceptedRank: 1,
          storedSequence: 5,
          storedPayloadBytes: stored.payloadBytes,
        ),
        VersionFileRatchet.accept,
      );
    });

    test('equal sequence with identical payload is a refresh', () {
      final stored = file(5);
      expect(
        decideVersionFileRatchet(
          candidate: file(5),
          highestAcceptedRank: 1,
          storedSequence: 5,
          storedPayloadBytes: stored.payloadBytes,
        ),
        VersionFileRatchet.refresh,
      );
    });

    test('equal sequence with a different payload is ignored', () {
      final stored = file(5);
      expect(
        decideVersionFileRatchet(
          candidate: file(5, latest: 130),
          highestAcceptedRank: 1,
          storedSequence: 5,
          storedPayloadBytes: stored.payloadBytes,
        ),
        VersionFileRatchet.ignore,
      );
    });

    test('F2: same rank and sequence with no stored envelope is accepted', () {
      // The envelope was dropped (retired key, corrupt bytes); rank and
      // sequence stayed. Re-downloading that same file must restore the gate.
      expect(
        decideVersionFileRatchet(
          candidate: file(5, latest: 130),
          highestAcceptedRank: 1,
          storedSequence: 5,
          storedPayloadBytes: null,
        ),
        VersionFileRatchet.accept,
      );
      // A lower sequence is still a rollback.
      expect(
        decideVersionFileRatchet(
          candidate: file(4),
          highestAcceptedRank: 1,
          storedSequence: 5,
          storedPayloadBytes: null,
        ),
        VersionFileRatchet.ignore,
      );
    });

    test('a higher rank accepts any sequence (fresh start)', () {
      expect(
        decideVersionFileRatchet(
          candidate: file(1, keyId: 'k2'),
          highestAcceptedRank: 1,
          storedSequence: 999999,
          storedPayloadBytes: file(999999).payloadBytes,
        ),
        VersionFileRatchet.accept,
      );
    });

    test('a lower rank is ignored whatever its sequence', () {
      expect(
        decideVersionFileRatchet(
          candidate: file(999999),
          highestAcceptedRank: 2,
          storedSequence: 1,
          storedPayloadBytes: null,
        ),
        VersionFileRatchet.ignore,
      );
    });
  });

  test('built-in keys and URL are the production values (SE-41 O1/O2)', () {
    final keys = builtInVersionKeys();
    expect(keys.map((k) => (k.keyId, k.rank)), [('k1', 1), ('k2', 2)]);
    expect(updateCheckK1PublicKeyBase64, isNot(updateCheckK2PublicKeyBase64));
    expect(
      updateCheckVersionFileUrl,
      'https://updates.mknoon.xyz/mknoon/version.json',
    );
    // A file signed with any other key (here the test-only k1) is not trusted
    // by the shipped keys.
    expect(
      VersionFileVerifier(keys)
          .verify(
            signedEnvelope(payloadBytes()),
            highestAcceptedRank: 0,
            requiredPlatforms: {UpdatePlatform.ios},
          )
          .rejection,
      VersionFileRejection.badSignature,
    );
  });
}
