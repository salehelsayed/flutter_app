import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_cleanup.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('MigrationSecureStorageCleanup', () {
    late FakeSecureKeyStore primaryStore;
    late FakeSecureKeyStore sharedStore;
    late MigrationSecureStorageStaging staging;
    late MigrationSecureStorageCleanup cleanup;

    setUp(() {
      primaryStore = FakeSecureKeyStore();
      sharedStore = FakeSecureKeyStore();
      staging = MigrationSecureStorageStaging(
        primaryStore: primaryStore,
        sharedStore: sharedStore,
      );
      cleanup = MigrationSecureStorageCleanup(staging: staging);
    });

    test(
      'explicit account erase/reset deletes registry-owned active keys',
      () async {
        final dynamicKeys = [
          MigrationSecureStorageRegistry.primaryGroupKeyMaterial(
            groupId: 'group-1',
            generation: 2,
          ),
          MigrationSecureStorageRegistry.sharedGroupMirror(
            groupId: 'group-1',
            generation: 2,
          ),
          MigrationSecureStorageRegistry.primaryMediaAttachmentKey(
            attachmentId: 'media-1',
          ),
        ];
        final registry = MigrationSecureStorageRegistry.resolve(
          discoveredKeys: dynamicKeys,
        );

        for (final key in registry) {
          final store = key.scope == MigrationSecureStoreScope.primary
              ? primaryStore
              : sharedStore;
          await store.write(key.activeKey, 'active:${key.activeKey}');
        }

        await cleanup.eraseAccount(
          registryKeys: registry,
          explicitLocalReset: true,
        );

        for (final key in registry) {
          final store = key.scope == MigrationSecureStoreScope.primary
              ? primaryStore
              : sharedStore;
          expect(
            await store.read(key.activeKey),
            isNull,
            reason: key.activeKey,
          );
        }
      },
    );

    test(
      'device-local authority is preserved unless erase/reset is explicit',
      () async {
        final registry = MigrationSecureStorageRegistry.fixedKeys;
        await primaryStore.write(
          SecureKeyStoreAccountMigrationAuthorityRepository.storageKey,
          'authority',
        );

        await cleanup.eraseAccount(
          registryKeys: registry,
          explicitLocalReset: false,
        );

        expect(
          await primaryStore.read(
            SecureKeyStoreAccountMigrationAuthorityRepository.storageKey,
          ),
          'authority',
        );
      },
    );

    test(
      'success and cancellation cleanup remove staging without active loss',
      () async {
        final dbKey = MigrationSecureStorageRegistry.fixedKey(
          scope: MigrationSecureStoreScope.primary,
          activeKey: 'db_encryption_key',
        )!;
        await primaryStore.write(dbKey.activeKey, 'active-db');
        await staging.stageValue(
          sessionId: 'session-4',
          key: dbKey,
          value: 'staged-db',
        );

        await cleanup.successfulImportCleanup(
          sessionId: 'session-4',
          registryKeys: [dbKey],
        );

        expect(await primaryStore.read(dbKey.activeKey), 'active-db');
        expect(
          await staging.readStagedValue(sessionId: 'session-4', key: dbKey),
          isNull,
        );

        await staging.stageValue(
          sessionId: 'session-5',
          key: dbKey,
          value: 'staged-db-again',
        );
        await cleanup.cancelledImportCleanup(
          sessionId: 'session-5',
          registryKeys: [dbKey],
        );

        expect(await primaryStore.read(dbKey.activeKey), 'active-db');
        expect(
          await staging.readStagedValue(sessionId: 'session-5', key: dbKey),
          isNull,
        );
      },
    );

    test(
      'failed import cleanup deletes staging and already-promoted keys',
      () async {
        final keys = [
          MigrationSecureStorageRegistry.fixedKey(
            scope: MigrationSecureStoreScope.primary,
            activeKey: 'db_encryption_key',
          )!,
          MigrationSecureStorageRegistry.fixedKey(
            scope: MigrationSecureStoreScope.primary,
            activeKey: 'identity_private_key',
          )!,
          MigrationSecureStorageRegistry.fixedKey(
            scope: MigrationSecureStoreScope.primary,
            activeKey: 'identity_mnemonic12',
          )!,
          MigrationSecureStorageRegistry.fixedKey(
            scope: MigrationSecureStoreScope.primary,
            activeKey: 'identity_ml_kem_secret_key',
          )!,
          MigrationSecureStorageRegistry.fixedKey(
            scope: MigrationSecureStoreScope.iosSharedAccessGroup,
            activeKey: 'identity_ml_kem_secret_key',
          )!,
          MigrationSecureStorageRegistry.fixedKey(
            scope: MigrationSecureStoreScope.primary,
            activeKey: 'secrets_migrated',
          )!,
        ];

        for (final key in keys.where(
          (key) => key.policy == MigrationSecureStorageKeyPolicy.migrate,
        )) {
          await staging.stageValue(
            sessionId: 'session-6',
            key: key,
            value: 'staged:${key.activeKey}',
          );
        }
        final result = await staging.promote(
          sessionId: 'session-6',
          registryKeys: keys,
        );

        await cleanup.failedImportCleanup(
          sessionId: 'session-6',
          registryKeys: keys,
        );

        for (final key in result.promotedKeys) {
          final store = key.scope == MigrationSecureStoreScope.primary
              ? primaryStore
              : sharedStore;
          expect(
            await store.read(key.activeKey),
            isNull,
            reason: key.activeKey,
          );
          expect(
            await staging.readStagedValue(sessionId: 'session-6', key: key),
            isNull,
          );
        }
      },
    );
  });
}
