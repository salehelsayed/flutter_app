import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository_impl.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';

class CountingSecureKeyStore implements SecureKeyStore {
  final SecureKeyStore _delegate;

  int readCount = 0;
  int writeCount = 0;
  int deleteCount = 0;
  int containsKeyCount = 0;

  CountingSecureKeyStore(this._delegate);

  @override
  Future<String?> read(String key) async {
    readCount++;
    return _delegate.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    await _delegate.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    deleteCount++;
    await _delegate.delete(key);
  }

  @override
  Future<bool> containsKey(String key) async {
    containsKeyCount++;
    return _delegate.containsKey(key);
  }
}

void main() {
  late FakeSecureKeyStore backingSecureKeyStore;
  late CountingSecureKeyStore secureKeyStore;
  late Map<String, Object?>? storedRow;
  late Map<String, Object?>? lastUpsertedRow;
  late int loadCallCount;
  late int upsertCallCount;
  late bool shouldFailUpsert;
  late IdentityRepositoryImpl repo;

  const testPeerId = '12D3KooWTestPeerIdABCDEF';
  const testPublicKey = 'pubkey-base64';
  const testPrivateKey = 'privkey-base64';
  const testMnemonic = 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12';
  const testMlKemPk = 'mlkem-pk-base64';
  const testMlKemSk = 'mlkem-sk-base64';
  const testCreatedAt = '2026-01-01T00:00:00.000Z';
  const testUpdatedAt = '2026-01-02T00:00:00.000Z';

  Map<String, Object?> makeDbRow({
    String? privateKey,
    String? mnemonic12,
    String? mlKemSecretKey,
    String? mlKemPublicKey,
    Uint8List? avatarBlob,
    String? avatarVersion,
  }) {
    return {
      'peer_id': testPeerId,
      'public_key': testPublicKey,
      'private_key': privateKey,
      'mnemonic12': mnemonic12,
      'ml_kem_public_key': mlKemPublicKey ?? testMlKemPk,
      'ml_kem_secret_key': mlKemSecretKey,
      'username': 'TestUser',
      'avatar_blob': avatarBlob,
      'avatar_version': avatarVersion,
      'created_at': testCreatedAt,
      'updated_at': testUpdatedAt,
    };
  }

  Future<void> seedIdentitySecrets({
    String privateKey = testPrivateKey,
    String mnemonic12 = testMnemonic,
    String? mlKemSecretKey = testMlKemSk,
  }) async {
    await backingSecureKeyStore.write('identity_private_key', privateKey);
    await backingSecureKeyStore.write('identity_mnemonic12', mnemonic12);
    if (mlKemSecretKey != null) {
      await backingSecureKeyStore.write('identity_ml_kem_secret_key', mlKemSecretKey);
    }
  }

  setUp(() {
    backingSecureKeyStore = FakeSecureKeyStore();
    secureKeyStore = CountingSecureKeyStore(backingSecureKeyStore);
    storedRow = null;
    lastUpsertedRow = null;
    loadCallCount = 0;
    upsertCallCount = 0;
    shouldFailUpsert = false;

    repo = IdentityRepositoryImpl(
      dbLoadIdentityRow: () async {
        loadCallCount++;
        return storedRow;
      },
      dbUpsertIdentityRow: (row) async {
        upsertCallCount++;
        lastUpsertedRow = row;
        if (shouldFailUpsert) {
          throw StateError('forced db failure');
        }
      },
      secureKeyStore: secureKeyStore,
    );
  });

  group('loadIdentity', () {
    test('returns null when no DB row exists', () async {
      storedRow = null;
      final result = await repo.loadIdentity();
      expect(result, isNull);
      expect(loadCallCount, 1);
    });

    test('caches repeated null loads without re-reading the DB', () async {
      storedRow = null;

      final first = await repo.loadIdentity();
      final second = await repo.loadIdentity();

      expect(first, isNull);
      expect(second, isNull);
      expect(loadCallCount, 1);
      expect(secureKeyStore.readCount, 0);
    });

    test('reads secrets from secure storage', () async {
      storedRow = makeDbRow();
      await seedIdentitySecrets();

      final result = await repo.loadIdentity();

      expect(result, isNotNull);
      expect(result!.peerId, testPeerId);
      expect(result.privateKey, testPrivateKey);
      expect(result.mnemonic12, testMnemonic);
      expect(result.mlKemSecretKey, testMlKemSk);
      expect(result.mlKemPublicKey, testMlKemPk);
    });

    test('returns cached identity on repeat load without re-reading storage', () async {
      storedRow = makeDbRow();
      await seedIdentitySecrets();

      final first = await repo.loadIdentity();
      final second = await repo.loadIdentity();

      expect(first, equals(second));
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(loadCallCount, 1);
      expect(secureKeyStore.readCount, 3);
    });

    test('falls back to DB columns for pre-migration data', () async {
      storedRow = makeDbRow(
        privateKey: 'db-privkey',
        mnemonic12: 'db-mnemonic',
        mlKemSecretKey: 'db-mlkem-sk',
      );
      // No secrets in secure storage → falls back to DB

      final result = await repo.loadIdentity();

      expect(result, isNotNull);
      expect(result!.privateKey, 'db-privkey');
      expect(result.mnemonic12, 'db-mnemonic');
      expect(result.mlKemSecretKey, 'db-mlkem-sk');
    });

    test('returns null when privateKey is missing from both stores', () async {
      storedRow = makeDbRow(); // null secrets in DB, none in secure storage

      final result = await repo.loadIdentity();
      expect(result, isNull);
      expect(secureKeyStore.readCount, 3);
    });

    test('returns null when mnemonic12 is missing from both stores', () async {
      storedRow = makeDbRow();
      await backingSecureKeyStore.write('identity_private_key', testPrivateKey);
      // mnemonic12 missing from both

      final result = await repo.loadIdentity();
      expect(result, isNull);
    });

    test('mlKemSecretKey can be null and still returns identity', () async {
      storedRow = makeDbRow();
      await backingSecureKeyStore.write('identity_private_key', testPrivateKey);
      await backingSecureKeyStore.write('identity_mnemonic12', testMnemonic);
      // No mlKemSecretKey in either store

      final result = await repo.loadIdentity();
      expect(result, isNotNull);
      expect(result!.mlKemSecretKey, isNull);
    });

    test('reads avatarBlob from DB row', () async {
      final blob = Uint8List.fromList([1, 2, 3, 4]);
      storedRow = makeDbRow(avatarBlob: blob);
      await backingSecureKeyStore.write('identity_private_key', testPrivateKey);
      await backingSecureKeyStore.write('identity_mnemonic12', testMnemonic);

      final result = await repo.loadIdentity();
      expect(result!.avatarBlob, blob);
    });

    test('reads avatarVersion from DB row', () async {
      storedRow = makeDbRow(avatarVersion: '2026-01-15T00:00:00.000Z');
      await backingSecureKeyStore.write('identity_private_key', testPrivateKey);
      await backingSecureKeyStore.write('identity_mnemonic12', testMnemonic);

      final result = await repo.loadIdentity();
      expect(result!.avatarVersion, '2026-01-15T00:00:00.000Z');
    });
  });

  group('saveIdentity', () {
    test('writes secrets to secure storage', () async {
      final identity = IdentityModel(
        peerId: testPeerId,
        publicKey: testPublicKey,
        privateKey: testPrivateKey,
        mnemonic12: testMnemonic,
        mlKemPublicKey: testMlKemPk,
        mlKemSecretKey: testMlKemSk,
        createdAt: testCreatedAt,
        updatedAt: testUpdatedAt,
      );

      await repo.saveIdentity(identity);

      expect(await backingSecureKeyStore.read('identity_private_key'), testPrivateKey);
      expect(await backingSecureKeyStore.read('identity_mnemonic12'), testMnemonic);
      expect(await backingSecureKeyStore.read('identity_ml_kem_secret_key'), testMlKemSk);
    });

    test('DB row has null secret columns', () async {
      final identity = IdentityModel(
        peerId: testPeerId,
        publicKey: testPublicKey,
        privateKey: testPrivateKey,
        mnemonic12: testMnemonic,
        createdAt: testCreatedAt,
        updatedAt: testUpdatedAt,
      );

      await repo.saveIdentity(identity);

      expect(lastUpsertedRow, isNotNull);
      expect(lastUpsertedRow!['private_key'], isNull);
      expect(lastUpsertedRow!['mnemonic12'], isNull);
      expect(lastUpsertedRow!['ml_kem_secret_key'], isNull);
      expect(lastUpsertedRow!['peer_id'], testPeerId);
      expect(lastUpsertedRow!['public_key'], testPublicKey);
    });

    test('skips mlKemSecretKey write when null', () async {
      final identity = IdentityModel(
        peerId: testPeerId,
        publicKey: testPublicKey,
        privateKey: testPrivateKey,
        mnemonic12: testMnemonic,
        createdAt: testCreatedAt,
        updatedAt: testUpdatedAt,
      );

      await repo.saveIdentity(identity);

      expect(await backingSecureKeyStore.containsKey('identity_ml_kem_secret_key'), isFalse);
    });

    test('calls dbUpsertIdentityRow with correct non-secret fields', () async {
      final blob = Uint8List.fromList([5, 6, 7]);
      final identity = IdentityModel(
        peerId: testPeerId,
        publicKey: testPublicKey,
        privateKey: testPrivateKey,
        mnemonic12: testMnemonic,
        mlKemPublicKey: testMlKemPk,
        username: 'MyUser',
        avatarBlob: blob,
        avatarVersion: '2026-02-01T00:00:00.000Z',
        createdAt: testCreatedAt,
        updatedAt: testUpdatedAt,
      );

      await repo.saveIdentity(identity);

      expect(upsertCallCount, 1);
      expect(lastUpsertedRow!['ml_kem_public_key'], testMlKemPk);
      expect(lastUpsertedRow!['username'], 'MyUser');
      expect(lastUpsertedRow!['avatar_blob'], blob);
      expect(lastUpsertedRow!['avatar_version'], '2026-02-01T00:00:00.000Z');
      expect(lastUpsertedRow!['created_at'], testCreatedAt);
      expect(lastUpsertedRow!['updated_at'], testUpdatedAt);
    });

    test('refreshes the cache after a successful save', () async {
      storedRow = null;
      final identity = IdentityModel(
        peerId: testPeerId,
        publicKey: testPublicKey,
        privateKey: testPrivateKey,
        mnemonic12: testMnemonic,
        mlKemPublicKey: testMlKemPk,
        mlKemSecretKey: testMlKemSk,
        createdAt: testCreatedAt,
        updatedAt: testUpdatedAt,
      );

      await repo.saveIdentity(identity);
      final reloaded = await repo.loadIdentity();

      expect(reloaded, isNotNull);
      expect(reloaded, equals(identity));
      expect(loadCallCount, 0);
      expect(secureKeyStore.readCount, 0);
    });

    test('replaces a cached null after saveIdentity', () async {
      storedRow = null;
      final identity = IdentityModel(
        peerId: testPeerId,
        publicKey: testPublicKey,
        privateKey: testPrivateKey,
        mnemonic12: testMnemonic,
        mlKemPublicKey: testMlKemPk,
        mlKemSecretKey: testMlKemSk,
        createdAt: testCreatedAt,
        updatedAt: testUpdatedAt,
      );

      final initialLoad = await repo.loadIdentity();
      expect(initialLoad, isNull);
      expect(loadCallCount, 1);
      expect(secureKeyStore.readCount, 0);

      await repo.saveIdentity(identity);
      final reloaded = await repo.loadIdentity();

      expect(reloaded, equals(identity));
      expect(loadCallCount, 1);
      expect(secureKeyStore.readCount, 0);
    });

    test('failed saveIdentity does not poison a warm cache', () async {
      final warmIdentity = IdentityModel(
        peerId: testPeerId,
        publicKey: testPublicKey,
        privateKey: testPrivateKey,
        mnemonic12: testMnemonic,
        mlKemPublicKey: testMlKemPk,
        mlKemSecretKey: testMlKemSk,
        username: 'TestUser',
        createdAt: testCreatedAt,
        updatedAt: testUpdatedAt,
      );
      final failingIdentity = IdentityModel(
        peerId: '12D3KooWNewPeerIdABCDEF',
        publicKey: 'new-pubkey-base64',
        privateKey: 'new-privkey-base64',
        mnemonic12: 'new word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11',
        mlKemPublicKey: 'new-mlkem-pk-base64',
        mlKemSecretKey: 'new-mlkem-sk-base64',
        createdAt: '2026-02-03T00:00:00.000Z',
        updatedAt: '2026-02-04T00:00:00.000Z',
      );

      storedRow = makeDbRow();
      await seedIdentitySecrets();

      final warmed = await repo.loadIdentity();
      expect(warmed, equals(warmIdentity));
      expect(loadCallCount, 1);
      expect(secureKeyStore.readCount, 3);

      shouldFailUpsert = true;

      await expectLater(repo.saveIdentity(failingIdentity), throwsStateError);

      final reloaded = await repo.loadIdentity();

      expect(reloaded, equals(warmIdentity));
      expect(reloaded, isNot(equals(failingIdentity)));
      expect(loadCallCount, 1);
      expect(upsertCallCount, 1);
    });
  });
}
