import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('MigrationSecureStorageStaging', () {
    late RecordingSecureKeyStore primaryStore;
    late RecordingSecureKeyStore sharedStore;
    late MigrationSecureStorageStaging staging;

    setUp(() {
      primaryStore = RecordingSecureKeyStore();
      sharedStore = RecordingSecureKeyStore();
      staging = MigrationSecureStorageStaging(
        primaryStore: primaryStore,
        sharedStore: sharedStore,
      );
    });

    test('stages values under session-scoped non-active keys', () async {
      final dbKey = MigrationSecureStorageRegistry.fixedKey(
        scope: MigrationSecureStoreScope.primary,
        activeKey: 'db_encryption_key',
      )!;
      final sharedMlKem = MigrationSecureStorageRegistry.fixedKey(
        scope: MigrationSecureStoreScope.iosSharedAccessGroup,
        activeKey: 'identity_ml_kem_secret_key',
      )!;

      await primaryStore.write('db_encryption_key', 'old-db');
      await sharedStore.write('identity_ml_kem_secret_key', 'old-shared');

      await staging.stageValue(
        sessionId: 'session-1',
        key: dbKey,
        value: 'new-db',
      );
      await staging.stageValue(
        sessionId: 'session-1',
        key: sharedMlKem,
        value: 'new-shared',
      );

      expect(await primaryStore.read('db_encryption_key'), 'old-db');
      expect(
        await sharedStore.read('identity_ml_kem_secret_key'),
        'old-shared',
      );
      expect(
        await staging.readStagedValue(sessionId: 'session-1', key: dbKey),
        'new-db',
      );
      expect(
        await staging.readStagedValue(sessionId: 'session-1', key: sharedMlKem),
        'new-shared',
      );
      expect(
        MigrationSecureStorageStaging.stagingKeyFor(
          sessionId: 'session-1',
          key: dbKey,
        ),
        isNot('db_encryption_key'),
      );
    });

    test(
      'promotion refuses missing critical staged keys before active writes',
      () async {
        final keys = _promotionKeys();
        await staging.stageValue(
          sessionId: 'session-2',
          key: keys.firstWhere((key) => key.activeKey == 'db_encryption_key'),
          value: 'new-db',
        );

        await expectLater(
          staging.promote(sessionId: 'session-2', registryKeys: keys),
          throwsA(isA<StateError>()),
        );
        expect(primaryStore.activeWrites, isEmpty);
        expect(await primaryStore.read('secrets_migrated'), isNull);
      },
    );

    test(
      'promotion writes active keys deterministically and can roll them back',
      () async {
        final keys = _promotionKeys();
        for (final key in keys.where(
          (key) => key.policy == MigrationSecureStorageKeyPolicy.migrate,
        )) {
          await staging.stageValue(
            sessionId: 'session-3',
            key: key,
            value: 'value:${key.scope.name}:${key.activeKey}',
          );
        }

        final result = await staging.promote(
          sessionId: 'session-3',
          registryKeys: keys.reversed,
        );

        expect(
          result.promotedKeys.map(
            (key) => '${key.scope.name}:${key.activeKey}',
          ),
          [
            'iosSharedAccessGroup:identity_ml_kem_secret_key',
            'primary:db_encryption_key',
            'primary:identity_ml_kem_secret_key',
            'primary:identity_mnemonic12',
            'primary:identity_private_key',
            'primary:secrets_migrated',
          ],
        );
        expect(await primaryStore.read('secrets_migrated'), 'true');
        expect(
          primaryStore.activeWrites,
          containsAllInOrder([
            'db_encryption_key',
            'identity_ml_kem_secret_key',
            'identity_mnemonic12',
            'identity_private_key',
            'secrets_migrated',
          ]),
        );

        await staging.rollbackPromoted(sessionId: 'session-3');

        for (final key in result.promotedKeys) {
          final store = key.scope == MigrationSecureStoreScope.primary
              ? primaryStore
              : sharedStore;
          expect(await store.read(key.activeKey), isNull);
        }
      },
    );
  });
}

List<MigrationSecureStorageKey> _promotionKeys() {
  return [
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
}

class RecordingSecureKeyStore extends FakeSecureKeyStore {
  final activeWrites = <String>[];

  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    if (!key.startsWith(MigrationSecureStorageStaging.stagingPrefix) &&
        !key.startsWith(MigrationSecureStorageStaging.promotedJournalPrefix)) {
      activeWrites.add(key);
    }
  }
}
