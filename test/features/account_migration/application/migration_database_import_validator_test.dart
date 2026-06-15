import 'package:flutter_app/features/account_migration/application/migration_database_import_validator.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('MigrationDatabaseImportValidator', () {
    late Database db;
    late FakeSecureKeyStore primaryStore;
    late FakeSecureKeyStore sharedStore;
    late MigrationSecureStorageStaging staging;

    setUp(() async {
      db = await openDatabase(inMemoryDatabasePath, version: 1);
      primaryStore = FakeSecureKeyStore();
      sharedStore = FakeSecureKeyStore();
      staging = MigrationSecureStorageStaging(
        primaryStore: primaryStore,
        sharedStore: sharedStore,
      );
      await db.execute('''
CREATE TABLE identity (
  id INTEGER PRIMARY KEY,
  peer_id TEXT NOT NULL,
  public_key TEXT NOT NULL,
  private_key TEXT,
  mnemonic12 TEXT,
  ml_kem_secret_key TEXT
)
''');
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'accepts null DB secret columns with required staged secrets present',
      () async {
        await _insertIdentity(
          db,
          privateKey: null,
          mnemonic: null,
          mlKem: null,
        );
        for (final key in _requiredSecretKeys()) {
          await staging.stageValue(
            sessionId: 'session-1',
            key: key,
            value: 'staged:${key.activeKey}',
          );
        }
        final validator = MigrationDatabaseImportValidator(
          secureStorageStaging: staging,
        );

        final result = await validator.validate(
          sessionId: 'session-1',
          stagedDb: db,
          requiredSecretKeys: _requiredSecretKeys(),
        );

        expect(result.isAccepted, isTrue);
        expect(
          result.residuals,
          contains(MigrationDatabaseImportResidual.mlKemChallengeUnsupported),
        );
        expect(await primaryStore.read('secrets_migrated'), isNull);
      },
    );

    test(
      'rejects DB-resident secrets and missing staged required secrets',
      () async {
        await _insertIdentity(
          db,
          privateKey: 'db-private',
          mnemonic: null,
          mlKem: null,
        );
        final validator = MigrationDatabaseImportValidator(
          secureStorageStaging: staging,
        );

        var result = await validator.validate(
          sessionId: 'session-2',
          stagedDb: db,
          requiredSecretKeys: _requiredSecretKeys(),
        );
        expect(result.isAccepted, isFalse);
        expect(
          result.hasError(
            MigrationDatabaseImportError.identitySecretColumnsNotNull,
          ),
          isTrue,
        );

        await db.delete('identity');
        await _insertIdentity(
          db,
          privateKey: null,
          mnemonic: null,
          mlKem: null,
        );
        await staging.stageValue(
          sessionId: 'session-2',
          key: _requiredSecretKeys().first,
          value: 'only-one-secret',
        );

        result = await validator.validate(
          sessionId: 'session-2',
          stagedDb: db,
          requiredSecretKeys: _requiredSecretKeys(),
        );
        expect(result.isAccepted, isFalse);
        expect(
          result.hasError(MigrationDatabaseImportError.missingStagedSecret),
          isTrue,
        );
        expect(await primaryStore.read('secrets_migrated'), isNull);
      },
    );
  });
}

Future<void> _insertIdentity(
  Database db, {
  required String? privateKey,
  required String? mnemonic,
  required String? mlKem,
}) {
  return db.insert('identity', {
    'id': 1,
    'peer_id': 'peer-1',
    'public_key': 'pub',
    'private_key': privateKey,
    'mnemonic12': mnemonic,
    'ml_kem_secret_key': mlKem,
  });
}

List<MigrationSecureStorageKey> _requiredSecretKeys() {
  return [
    MigrationSecureStorageRegistry.fixedKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: MigrationSecureStorageRegistry.dbEncryptionKey,
    )!,
    MigrationSecureStorageRegistry.fixedKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: MigrationSecureStorageRegistry.identityPrivateKey,
    )!,
    MigrationSecureStorageRegistry.fixedKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: MigrationSecureStorageRegistry.identityMnemonic12,
    )!,
    MigrationSecureStorageRegistry.fixedKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: MigrationSecureStorageRegistry.identityMlKemSecretKey,
    )!,
    MigrationSecureStorageRegistry.fixedKey(
      scope: MigrationSecureStoreScope.iosSharedAccessGroup,
      activeKey: MigrationSecureStorageRegistry.identityMlKemSecretKey,
    )!,
  ];
}
