import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccountMigrationAuthorityState', () {
    test('contains the canonical proposal states in wire order', () {
      expect(
        AccountMigrationAuthorityState.values.map((state) => state.wireName),
        [
          'no_account',
          'migration_pairing',
          'migration_import_staging',
          'migration_verified_waiting_for_cutover',
          'active',
          'migration_failed_cleanup_required',
          'migration_exporting_network_paused',
          'migration_cutover_pending_blocked',
          'migrated_out',
          'migration_failed_active_restored',
        ],
      );
    });

    test('round trips wire names without aliases', () {
      for (final state in AccountMigrationAuthorityState.values) {
        expect(
          AccountMigrationAuthorityState.fromWireName(state.wireName),
          state,
        );
      }

      expect(
        AccountMigrationAuthorityState.fromWireName('migrated-out'),
        isNull,
      );
      expect(AccountMigrationAuthorityState.fromWireName('ACTIVE'), isNull);
    });

    test('classifies normal and blocked startup states', () {
      expect(
        AccountMigrationAuthorityState.noAccount.allowsNormalStartup,
        true,
      );
      expect(AccountMigrationAuthorityState.active.allowsNormalStartup, true);
      expect(
        AccountMigrationAuthorityState
            .migrationFailedActiveRestored
            .allowsNormalStartup,
        true,
      );

      for (final state in [
        AccountMigrationAuthorityState.migrationPairing,
        AccountMigrationAuthorityState.migrationImportStaging,
        AccountMigrationAuthorityState.migrationVerifiedWaitingForCutover,
        AccountMigrationAuthorityState.migrationFailedCleanupRequired,
        AccountMigrationAuthorityState.migrationExportingNetworkPaused,
        AccountMigrationAuthorityState.migrationCutoverPendingBlocked,
        AccountMigrationAuthorityState.migratedOut,
      ]) {
        expect(state.allowsNormalStartup, false, reason: state.wireName);
        expect(state.blocksNormalStartup, true, reason: state.wireName);
      }

      expect(
        AccountMigrationAuthorityState.migrationImportStaging.isImportStaging,
        true,
      );
      expect(
        AccountMigrationAuthorityState
            .migrationVerifiedWaitingForCutover
            .isImportStaging,
        true,
      );
      expect(AccountMigrationAuthorityState.migratedOut.isMigratedOut, true);
    });
  });

  group('AccountMigrationAuthorityRecord', () {
    test('serializes deterministically with explicit version and state', () {
      final record = AccountMigrationAuthorityRecord(
        state: AccountMigrationAuthorityState.migratedOut,
        accountPeerId: '12D3KooWMoved',
      );

      expect(
        record.toPersistedJson(),
        '{"version":1,"state":"migrated_out","accountPeerId":"12D3KooWMoved"}',
      );
      expect(
        AccountMigrationAuthorityRecord.fromPersistedJson(
          record.toPersistedJson(),
        ),
        record,
      );
    });

    test('omits optional peer id when identity-less staging is stored', () {
      final record = AccountMigrationAuthorityRecord(
        state: AccountMigrationAuthorityState.migrationImportStaging,
      );

      expect(
        record.toPersistedJson(),
        '{"version":1,"state":"migration_import_staging"}',
      );
      expect(
        AccountMigrationAuthorityRecord.fromPersistedJson(
          record.toPersistedJson(),
        ),
        record,
      );
    });

    test('fails closed for malformed JSON, unknown states, and versions', () {
      for (final raw in [
        '{',
        '[]',
        '{"version":1,"state":"unknown"}',
        '{"version":2,"state":"active"}',
        '{"version":1,"state":"active","accountPeerId":7}',
      ]) {
        final parsed = AccountMigrationAuthorityRecord.fromPersistedJson(raw);

        expect(
          parsed.state,
          AccountMigrationAuthorityState.migrationFailedCleanupRequired,
          reason: raw,
        );
        expect(parsed.isFailClosed, true, reason: raw);
        expect(parsed.blocksNormalStartup, true, reason: raw);
      }
    });
  });
}
