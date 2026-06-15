import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';

class _FakeAuthorityRepository implements AccountMigrationAuthorityRepository {
  AccountMigrationAuthorityRecord? record;

  @override
  Future<AccountMigrationAuthorityRecord?> loadAuthority() async => record;

  @override
  Future<void> saveAuthority(AccountMigrationAuthorityRecord record) async {
    this.record = record;
  }

  @override
  Future<void> clearAuthority() async {
    record = null;
  }
}

void main() {
  group('AccountMigrationRuntimeNetworkGate', () {
    late _FakeAuthorityRepository repository;
    late AccountMigrationRuntimeNetworkGate gate;

    setUp(() {
      repository = _FakeAuthorityRepository();
      gate = AccountMigrationRuntimeNetworkGate(
        authorityRepository: repository,
      );
    });

    test('allows missing legacy authority records', () async {
      expect(
        await gate.allowsAccountNetworkSideEffects(operation: 'test'),
        isTrue,
      );
    });

    test('allows active and restored-active authority', () async {
      for (final state in [
        AccountMigrationAuthorityState.active,
        AccountMigrationAuthorityState.migrationFailedActiveRestored,
      ]) {
        repository.record = AccountMigrationAuthorityRecord(state: state);

        expect(
          await gate.allowsAccountNetworkSideEffects(operation: state.wireName),
          isTrue,
        );
      }
    });

    test('blocks migrated-out and in-progress migration states', () async {
      final blockedStates = AccountMigrationAuthorityState.values.where(
        (state) =>
            state != AccountMigrationAuthorityState.noAccount &&
            state != AccountMigrationAuthorityState.active &&
            state !=
                AccountMigrationAuthorityState.migrationFailedActiveRestored,
      );

      for (final state in blockedStates) {
        repository.record = AccountMigrationAuthorityRecord(state: state);

        expect(
          await gate.allowsAccountNetworkSideEffects(operation: state.wireName),
          isFalse,
          reason: state.wireName,
        );
      }
    });

    test('blocks fail-closed and peer-mismatched records', () async {
      repository.record = AccountMigrationAuthorityRecord.failClosed();
      expect(
        await gate.allowsAccountNetworkSideEffects(operation: 'test'),
        isFalse,
      );

      repository.record = const AccountMigrationAuthorityRecord(
        state: AccountMigrationAuthorityState.active,
        accountPeerId: 'peer-a',
      );
      expect(
        await gate.allowsAccountNetworkSideEffects(
          peerId: 'peer-b',
          operation: 'test',
        ),
        isFalse,
      );
    });

    test(
      'notification display stays allowed during an export pause',
      () async {
        // Display has no relay side effects; an active Move Account export
        // must not blank incoming notifications on the old phone.
        final displayAllowed = [
          AccountMigrationAuthorityState.noAccount,
          AccountMigrationAuthorityState.active,
          AccountMigrationAuthorityState.migrationFailedActiveRestored,
          AccountMigrationAuthorityState.migrationExportingNetworkPaused,
        ];

        for (final state in AccountMigrationAuthorityState.values) {
          repository.record = AccountMigrationAuthorityRecord(state: state);

          expect(
            await gate.allowsAccountNotificationDisplay(),
            displayAllowed.contains(state),
            reason: state.wireName,
          );
        }

        // But network side effects remain denied while export-paused.
        repository.record = const AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.migrationExportingNetworkPaused,
        );
        expect(
          await gate.allowsAccountNetworkSideEffects(operation: 'test'),
          isFalse,
        );

        // Fail-closed records never display.
        repository.record = AccountMigrationAuthorityRecord.failClosed();
        expect(await gate.allowsAccountNotificationDisplay(), isFalse);
      },
    );
  });
}
