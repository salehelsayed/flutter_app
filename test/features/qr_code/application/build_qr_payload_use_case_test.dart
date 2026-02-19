import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeIdentityRepo implements IdentityRepository {
  IdentityModel? identity;

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {}
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

final _testIdentity = IdentityModel(
  peerId: '12D3KooWTestPeerIdForQR',
  publicKey: 'testPublicKeyBase64',
  privateKey: 'testPrivateKeyBase64',
  mnemonic12: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  mlKemPublicKey: 'mlkemPubKey',
  createdAt: '2024-01-01T00:00:00Z',
  updatedAt: '2024-01-01T00:00:00Z',
  username: 'TestUser',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeIdentityRepo repo;

  setUp(() {
    repo = _FakeIdentityRepo()..identity = _testIdentity;
  });

  test('success: builds signed QR payload with sorted keys', () async {
    final (result, jsonString) = await buildQRPayload(
      repo: repo,
      callSign: (data, privateKey) async {
        // Verify signing inputs
        expect(privateKey, equals('testPrivateKeyBase64'));
        // The data should be canonical JSON (sorted keys)
        final parsed = jsonDecode(data) as Map<String, dynamic>;
        expect(parsed.keys.toList(), equals(parsed.keys.toList()..sort()));
        return {'ok': true, 'signature': 'testSignature'};
      },
    );

    expect(result, equals(BuildQRPayloadResult.success));
    expect(jsonString, isNotNull);

    final payload = jsonDecode(jsonString!) as Map<String, dynamic>;
    expect(payload['ns'], equals('12D3KooWTestPeerIdForQR'));
    expect(payload['pk'], equals('testPublicKeyBase64'));
    expect(payload['un'], equals('TestUser'));
    expect(payload['sig'], equals('testSignature'));
    expect(payload['ts'], isNotNull);
    expect(payload['rv'], isNotNull);
    // ML-KEM public key should NOT be in QR payload
    expect(payload.containsKey('mlkem'), isFalse);
  });

  test('success with cached identity: skips repo load', () async {
    repo.identity = null; // Would fail if repo is called

    final (result, jsonString) = await buildQRPayload(
      repo: repo,
      callSign: (_, __) async => {'ok': true, 'signature': 'sig'},
      cachedIdentity: _testIdentity,
    );

    expect(result, equals(BuildQRPayloadResult.success));
    expect(jsonString, isNotNull);
  });

  test('noIdentity: returns error when no identity found', () async {
    repo.identity = null;

    final (result, jsonString) = await buildQRPayload(
      repo: repo,
      callSign: (_, __) async => {'ok': true, 'signature': 'sig'},
    );

    expect(result, equals(BuildQRPayloadResult.noIdentity));
    expect(jsonString, isNull);
  });

  test('signingError: returns error when signing fails', () async {
    final (result, jsonString) = await buildQRPayload(
      repo: repo,
      callSign: (_, __) async => {
        'ok': false,
        'errorCode': 'SIGN_FAILED',
        'errorMessage': 'Key error',
      },
    );

    expect(result, equals(BuildQRPayloadResult.signingError));
    expect(jsonString, isNull);
  });

  test('payload keys are sorted alphabetically', () async {
    final (_, jsonString) = await buildQRPayload(
      repo: repo,
      callSign: (_, __) async => {'ok': true, 'signature': 'sig'},
    );

    final payload = jsonDecode(jsonString!) as Map<String, dynamic>;
    final keys = payload.keys.toList();
    final sortedKeys = List<String>.from(keys)..sort();
    expect(keys, equals(sortedKeys));
  });
}
