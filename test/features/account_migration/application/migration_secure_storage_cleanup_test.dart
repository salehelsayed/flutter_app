import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_cleanup.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

class _RecordingEraseStore extends FakeSecureKeyStore {
  _RecordingEraseStore(this.scope, this.deletions);

  final String scope;
  final List<String> deletions;

  @override
  Future<void> delete(String key) async {
    deletions.add('$scope:$key');
    await super.delete(key);
  }
}

class _FailingEraseStore extends FakeSecureKeyStore {
  _FailingEraseStore(this.failure);

  final String failure;

  @override
  Future<Map<String, String>> readAll() {
    if (failure == 'inventory') throw StateError('inventory unavailable');
    return super.readAll();
  }

  @override
  Future<void> delete(String key) async {
    if (key == 'identity_private_key') {
      if (failure == 'silent') return;
      if (failure == 'delete') throw StateError('deletion unavailable');
    }
    await super.delete(key);
  }
}

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

    test('explicit reset deletes database key then authority last', () async {
      final deletions = <String>[];
      final primary = _RecordingEraseStore('primary', deletions);
      final shared = _RecordingEraseStore('shared', deletions);
      const authorityKey =
          SecureKeyStoreAccountMigrationAuthorityRepository.storageKey;
      const databaseKey = MigrationSecureStorageRegistry.dbEncryptionKey;
      // Seed authority first so inventory order alone cannot satisfy the test.
      await primary.write(authorityKey, 'blocked-authority-fixture');
      await primary.write(databaseKey, 'database-key-fixture');
      await primary.write('identity_private_key', 'private-key-fixture');
      await shared.write('group_key:fixture', 'group-key-fixture');

      await MigrationSecureStorageCleanup(
        staging: MigrationSecureStorageStaging(
          primaryStore: primary,
          sharedStore: shared,
        ),
      ).eraseAccount(
        registryKeys: MigrationSecureStorageRegistry.resolve(),
        explicitLocalReset: true,
      );

      expect(deletions, hasLength(4));
      expect(deletions.toSet(), {
        'primary:identity_private_key',
        'shared:group_key:fixture',
        'primary:$databaseKey',
        'primary:$authorityKey',
      });
      expect(deletions[deletions.length - 2], 'primary:$databaseKey');
      expect(deletions.last, 'primary:$authorityKey');
      expect(await primary.readAll(), isEmpty);
      expect(await shared.readAll(), isEmpty);
    });

    test(
      'explicit reset erases unregistered account secrets and preserves app preferences',
      () async {
        const accountKeys = [
          'identity_ml_kem_secret_key_ring',
          'fdc09_wake_tokens',
          'fdc09_received_wake_tokens',
          'vc2_issued_call_wake_handles_v1',
          'vc2_received_call_wake_handles_v1',
          'mlkem_reannounce_pending',
          'wake_token_pending',
          'wake_token_distribution_scheduled_v1',
          'group_device_announce_pending',
          'push_registration_transport_peer_id',
          'account_migration_cutover:v1',
          'group_secrets_scrubbed',
          'group_key_material:orphan-group:2',
          'media_attachment_encryption_key:orphan-media',
          'account_migration:staging:v1:old-session:primary:identity_private_key',
          'account_migration:promoted:v1:old-session',
          'future_account_secret',
        ];
        const preferences = [
          'background_preference',
          'image_quality_preference',
          'video_quality_preference',
          'orbit_geometry_prefs_v1',
          'media_download_preferences',
          'settings_always_relay_calls',
        ];
        for (final name in accountKeys) {
          await primaryStore.write(name, 'retired-account-fixture');
        }
        for (final name in preferences) {
          await primaryStore.write(name, 'app-preference-fixture');
        }
        await sharedStore.write(
          'group_key:orphan-group:2',
          'group-key-fixture',
        );
        await sharedStore.write('group_muted:orphan-group', '1');

        await cleanup.eraseAccount(
          registryKeys: MigrationSecureStorageRegistry.resolve(),
          explicitLocalReset: true,
        );

        for (final name in accountKeys) {
          expect(await primaryStore.read(name), isNull, reason: name);
        }
        for (final name in preferences) {
          expect(
            await primaryStore.read(name),
            'app-preference-fixture',
            reason: name,
          );
        }
        expect(await sharedStore.read('group_key:orphan-group:2'), isNull);
        expect(await sharedStore.read('group_muted:orphan-group'), isNull);
        expect(
          (await primaryStore.readAll()).keys.toSet(),
          preferences.toSet(),
        );
        expect(await sharedStore.readAll(), isEmpty);
      },
    );

    for (final failure in ['inventory', 'delete', 'silent']) {
      test(
        'explicit reset retains blocked authority after $failure failure',
        () async {
          final store = _FailingEraseStore(failure);
          final authorityKey =
              SecureKeyStoreAccountMigrationAuthorityRepository.storageKey;
          await store.write(authorityKey, 'blocked-authority-fixture');
          await store.write('db_encryption_key', 'database-key-fixture');
          await store.write('identity_private_key', 'private-key-fixture');

          await expectLater(
            MigrationSecureStorageCleanup(
              staging: MigrationSecureStorageStaging(primaryStore: store),
            ).eraseAccount(
              registryKeys: MigrationSecureStorageRegistry.resolve(),
              explicitLocalReset: true,
            ),
            throwsStateError,
          );

          expect(await store.read(authorityKey), 'blocked-authority-fixture');
          expect(await store.read('db_encryption_key'), 'database-key-fixture');
          expect(
            await store.read('identity_private_key'),
            'private-key-fixture',
          );
        },
      );
    }

    test('shared inventory failure occurs before primary deletion', () async {
      await primaryStore.write('identity_private_key', 'private-key-fixture');
      await expectLater(
        MigrationSecureStorageCleanup(
          staging: MigrationSecureStorageStaging(
            primaryStore: primaryStore,
            sharedStore: _FailingEraseStore('inventory'),
          ),
        ).eraseAccount(
          registryKeys: MigrationSecureStorageRegistry.resolve(),
          explicitLocalReset: true,
        ),
        throwsStateError,
      );
      expect(
        await primaryStore.read('identity_private_key'),
        'private-key-fixture',
      );
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
            key.scope == MigrationSecureStoreScope.primary &&
                    MigrationSecureStorageRegistry
                        .accountErasePreservedPrimaryKeys
                        .contains(key.activeKey)
                ? 'active:${key.activeKey}'
                : isNull,
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
