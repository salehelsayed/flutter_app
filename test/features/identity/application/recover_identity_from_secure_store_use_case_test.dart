import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/application/recover_identity_from_secure_store_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

class _FakeIdentityRepo implements IdentityRepository {
  IdentityModel? savedIdentity;

  @override
  Future<IdentityModel?> loadIdentity() async => savedIdentity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    savedIdentity = identity;
  }
}

const _storedMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

void main() {
  late FakeSecureKeyStore secureKeyStore;
  late _FakeIdentityRepo identityRepository;
  late int restoreCallCount;
  late int mlKemCallCount;
  late String? lastRestoreInput;

  const restoredIdentityJson = {
    'peerId': '12D3KooWRecovered',
    'publicKey': 'restored-public-key',
    'privateKey': 'restored-private-key',
    'mnemonic12': _storedMnemonic,
    'createdAt': '2026-03-24T08:00:00.000Z',
    'updatedAt': '2026-03-24T08:00:00.000Z',
  };

  setUp(() {
    secureKeyStore = FakeSecureKeyStore();
    identityRepository = _FakeIdentityRepo();
    restoreCallCount = 0;
    mlKemCallCount = 0;
    lastRestoreInput = null;
  });

  test(
    'returns noStoredMnemonic when secure storage has no mnemonic',
    () async {
      final result = await recoverIdentityFromSecureStore(
        secureKeyStore: secureKeyStore,
        repo: identityRepository,
        callRestore: (mnemonic) async {
          restoreCallCount++;
          lastRestoreInput = mnemonic;
          return {'ok': true, 'identity': restoredIdentityJson};
        },
        callMlKemKeygen: () async {
          mlKemCallCount++;
          return {
            'ok': true,
            'publicKey': 'generated-mlkem-public',
            'secretKey': 'generated-mlkem-secret',
          };
        },
      );

      expect(result, SecureStoreIdentityRecoveryResult.noStoredMnemonic);
      expect(restoreCallCount, 0);
      expect(mlKemCallCount, 0);
      expect(lastRestoreInput, isNull);
      expect(identityRepository.savedIdentity, isNull);
    },
  );

  test(
    'restores identity from stored mnemonic when secure storage survives',
    () async {
      await secureKeyStore.write('identity_mnemonic12', _storedMnemonic);

      final result = await recoverIdentityFromSecureStore(
        secureKeyStore: secureKeyStore,
        repo: identityRepository,
        callRestore: (mnemonic) async {
          restoreCallCount++;
          lastRestoreInput = mnemonic;
          return {'ok': true, 'identity': restoredIdentityJson};
        },
        callMlKemKeygen: () async {
          mlKemCallCount++;
          return {
            'ok': true,
            'publicKey': 'generated-mlkem-public',
            'secretKey': 'generated-mlkem-secret',
          };
        },
      );

      expect(result, SecureStoreIdentityRecoveryResult.restored);
      expect(restoreCallCount, 1);
      expect(mlKemCallCount, 1);
      expect(lastRestoreInput, _storedMnemonic);
      expect(identityRepository.savedIdentity, isNotNull);
      expect(identityRepository.savedIdentity!.peerId, '12D3KooWRecovered');
      expect(
        identityRepository.savedIdentity!.mlKemPublicKey,
        'generated-mlkem-public',
      );
      expect(
        identityRepository.savedIdentity!.mlKemSecretKey,
        'generated-mlkem-secret',
      );
    },
  );

  test(
    'returns restoreFailed when stored mnemonic cannot be restored',
    () async {
      await secureKeyStore.write('identity_mnemonic12', _storedMnemonic);

      final result = await recoverIdentityFromSecureStore(
        secureKeyStore: secureKeyStore,
        repo: identityRepository,
        callRestore: (mnemonic) async {
          restoreCallCount++;
          lastRestoreInput = mnemonic;
          return {
            'ok': false,
            'errorCode': 'INVALID_MNEMONIC',
            'errorMessage': 'invalid',
          };
        },
        callMlKemKeygen: () async {
          mlKemCallCount++;
          return {
            'ok': true,
            'publicKey': 'generated-mlkem-public',
            'secretKey': 'generated-mlkem-secret',
          };
        },
      );

      expect(result, SecureStoreIdentityRecoveryResult.restoreFailed);
      expect(restoreCallCount, 1);
      expect(mlKemCallCount, 1);
      expect(lastRestoreInput, _storedMnemonic);
      expect(identityRepository.savedIdentity, isNull);
    },
  );
}
