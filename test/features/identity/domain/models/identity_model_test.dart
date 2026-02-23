import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

void main() {
  const testPeerId = '12D3KooWTestPeerIdABCDEF';
  const testPublicKey = 'pubkey-base64';
  const testPrivateKey = 'privkey-base64';
  const testMnemonic =
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12';
  const testCreatedAt = '2026-01-01T00:00:00.000Z';
  const testUpdatedAt = '2026-01-02T00:00:00.000Z';

  IdentityModel makeIdentity({
    String? mlKemPublicKey,
    String? mlKemSecretKey,
    String username = 'TestUser',
    Uint8List? avatarBlob,
    String? avatarVersion,
  }) {
    return IdentityModel(
      peerId: testPeerId,
      publicKey: testPublicKey,
      privateKey: testPrivateKey,
      mnemonic12: testMnemonic,
      mlKemPublicKey: mlKemPublicKey,
      mlKemSecretKey: mlKemSecretKey,
      username: username,
      avatarBlob: avatarBlob,
      avatarVersion: avatarVersion,
      createdAt: testCreatedAt,
      updatedAt: testUpdatedAt,
    );
  }

  group('IdentityModel', () {
    group('fromJson / toJson', () {
      test('round-trips correctly with all fields', () {
        final original = makeIdentity(
          mlKemPublicKey: 'mlkem-pub-base64',
          mlKemSecretKey: 'mlkem-sec-base64',
          avatarBlob: Uint8List.fromList([1, 2, 3]),
          avatarVersion: 'v1',
        );

        final json = original.toJson();
        final restored = IdentityModel.fromJson(json);

        expect(restored.peerId, original.peerId);
        expect(restored.publicKey, original.publicKey);
        expect(restored.privateKey, original.privateKey);
        expect(restored.mnemonic12, original.mnemonic12);
        expect(restored.mlKemPublicKey, original.mlKemPublicKey);
        expect(restored.mlKemSecretKey, original.mlKemSecretKey);
        expect(restored.username, original.username);
        expect(restored.createdAt, original.createdAt);
        expect(restored.updatedAt, original.updatedAt);
      });

      test('handles optional mlKem fields as null', () {
        final original = makeIdentity();
        final json = original.toJson();
        final restored = IdentityModel.fromJson(json);

        expect(restored.mlKemPublicKey, isNull);
        expect(restored.mlKemSecretKey, isNull);
      });

      test('defaults username to Username when missing from JSON', () {
        final json = {
          'peerId': testPeerId,
          'publicKey': testPublicKey,
          'privateKey': testPrivateKey,
          'mnemonic12': testMnemonic,
          'createdAt': testCreatedAt,
          'updatedAt': testUpdatedAt,
        };

        final restored = IdentityModel.fromJson(json);
        expect(restored.username, 'Username');
      });

      test('toJson does not include avatarBlob', () {
        final model = makeIdentity(
          avatarBlob: Uint8List.fromList([10, 20, 30]),
        );
        final json = model.toJson();

        expect(json.containsKey('avatarBlob'), isFalse);
      });
    });

    group('equality', () {
      test('equal when all fields match', () {
        final a = makeIdentity();
        final b = makeIdentity();
        expect(a, equals(b));
      });

      test('not equal when peerId differs', () {
        final a = makeIdentity();
        final b = IdentityModel(
          peerId: 'different-peer-id',
          publicKey: testPublicKey,
          privateKey: testPrivateKey,
          mnemonic12: testMnemonic,
          username: 'TestUser',
          createdAt: testCreatedAt,
          updatedAt: testUpdatedAt,
        );
        expect(a, isNot(equals(b)));
      });

      test('avatarBlob equality uses listEquals', () {
        final a = makeIdentity(avatarBlob: Uint8List.fromList([1, 2, 3]));
        final b = makeIdentity(avatarBlob: Uint8List.fromList([1, 2, 3]));
        expect(a, equals(b));
      });

      test('not equal when avatarBlob differs', () {
        final a = makeIdentity(avatarBlob: Uint8List.fromList([1, 2, 3]));
        final b = makeIdentity(avatarBlob: Uint8List.fromList([4, 5, 6]));
        expect(a, isNot(equals(b)));
      });
    });

    group('hashCode', () {
      test('same for equal objects', () {
        final a = makeIdentity();
        final b = makeIdentity();
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different for different objects', () {
        final a = makeIdentity(username: 'Alice');
        final b = makeIdentity(username: 'Bob');
        // Hash codes *may* collide, but for these inputs they should differ.
        expect(a.hashCode, isNot(equals(b.hashCode)));
      });
    });

    group('toString', () {
      test('includes peerId', () {
        final model = makeIdentity();
        expect(model.toString(), contains(testPeerId));
      });

      test('includes createdAt and updatedAt', () {
        final model = makeIdentity();
        final str = model.toString();
        expect(str, contains(testCreatedAt));
        expect(str, contains(testUpdatedAt));
      });
    });
  });
}
