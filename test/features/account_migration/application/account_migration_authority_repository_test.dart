import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_repository_impl.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_cutover_record.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('SecureKeyStoreAccountMigrationAuthorityRepository', () {
    late FakeSecureKeyStore secureKeyStore;
    late SecureKeyStoreAccountMigrationAuthorityRepository repository;

    setUp(() {
      secureKeyStore = FakeSecureKeyStore();
      repository = SecureKeyStoreAccountMigrationAuthorityRepository(
        secureKeyStore: secureKeyStore,
      );
    });

    test('missing records load as absent device-local authority', () async {
      expect(await repository.loadAuthority(), isNull);
    });

    test(
      'persists authority only through the dedicated secure-store key',
      () async {
        final record = AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.active,
          accountPeerId: '12D3KooWLocal',
        );

        await repository.saveAuthority(record);

        expect(
          await secureKeyStore.read(
            SecureKeyStoreAccountMigrationAuthorityRepository.storageKey,
          ),
          '{"version":1,"state":"active","accountPeerId":"12D3KooWLocal"}',
        );
        expect(await repository.loadAuthority(), record);
      },
    );

    test(
      'supports identity-less staging records without a database row',
      () async {
        final record = AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.migrationImportStaging,
        );

        await repository.saveAuthority(record);

        expect(
          await secureKeyStore.read(
            SecureKeyStoreAccountMigrationAuthorityRepository.storageKey,
          ),
          '{"version":1,"state":"migration_import_staging"}',
        );
        expect(await repository.loadAuthority(), record);
      },
    );

    test(
      'malformed persisted authority fails closed instead of active',
      () async {
        await secureKeyStore.write(
          SecureKeyStoreAccountMigrationAuthorityRepository.storageKey,
          '{"version":1,"state":"not_real"}',
        );

        final loaded = await repository.loadAuthority();

        expect(loaded, isNotNull);
        expect(
          loaded!.state,
          AccountMigrationAuthorityState.migrationFailedCleanupRequired,
        );
        expect(loaded.blocksNormalStartup, true);
      },
    );

    test('clearing authority restores missing-record behavior', () async {
      await repository.saveAuthority(
        AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.migratedOut,
          accountPeerId: '12D3KooWOld',
        ),
      );

      await repository.clearAuthority();

      expect(
        await secureKeyStore.containsKey(
          SecureKeyStoreAccountMigrationAuthorityRepository.storageKey,
        ),
        false,
      );
      expect(await repository.loadAuthority(), isNull);
    });
  });

  group('SecureKeyStoreMigrationCutoverRepository', () {
    late FakeSecureKeyStore secureKeyStore;
    late SecureKeyStoreMigrationCutoverRepository repository;

    setUp(() {
      secureKeyStore = FakeSecureKeyStore();
      repository = SecureKeyStoreMigrationCutoverRepository(
        secureKeyStore: secureKeyStore,
      );
    });

    test('persists cutover records outside database-backed state', () async {
      final now = DateTime.utc(2026, 6, 7, 16);
      final record =
          MigrationCutoverRecord.initial(
            sessionId: 'session-cutover',
            accountPeerId: '12D3KooWAccount',
            devicePeerId: '12D3KooWOld',
            deviceRole: MigrationCutoverDeviceRole.oldPhone,
            now: now,
          ).copyWith(
            oldNetworkBlocked: true,
            oldNetworkBlockedAt: now,
            updatedAt: now,
          );

      await repository.saveCutover(record);

      expect(
        await secureKeyStore.containsKey(
          SecureKeyStoreMigrationCutoverRepository.storageKey,
        ),
        true,
      );
      expect(await repository.loadCutover(), record);
    });

    test('malformed cutover record fails closed', () async {
      await secureKeyStore.write(
        SecureKeyStoreMigrationCutoverRepository.storageKey,
        '{"version":1,"phase":"unknown"}',
      );

      final loaded = await repository.loadCutover();

      expect(loaded, isNotNull);
      expect(loaded!.isFailClosed, isTrue);
      expect(loaded.phase, MigrationCutoverPhase.failed);
    });
  });
}
