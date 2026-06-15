import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_import_precondition.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  group('evaluateAccountMigrationImportPrecondition', () {
    late FakeIdentityRepository identityRepository;
    late SecureKeyStoreAccountMigrationAuthorityRepository authorityRepository;

    setUp(() {
      identityRepository = FakeIdentityRepository();
      authorityRepository = SecureKeyStoreAccountMigrationAuthorityRepository(
        secureKeyStore: FakeSecureKeyStore(),
      );
    });

    test('allows import when no local identity or authority exists', () async {
      final result = await evaluateAccountMigrationImportPrecondition(
        identityRepository: identityRepository,
        authorityRepository: authorityRepository,
      );

      expect(result.canStartImport, true);
      expect(result.status, AccountMigrationImportPreconditionStatus.allowed);
    });

    test(
      'allows import when authority explicitly records no account',
      () async {
        await authorityRepository.saveAuthority(
          AccountMigrationAuthorityRecord(
            state: AccountMigrationAuthorityState.noAccount,
          ),
        );

        final result = await evaluateAccountMigrationImportPrecondition(
          identityRepository: identityRepository,
          authorityRepository: authorityRepository,
        );

        expect(result.canStartImport, true);
        expect(result.status, AccountMigrationImportPreconditionStatus.allowed);
      },
    );

    test('rejects import when a local identity already exists', () async {
      identityRepository.seed(FakeIdentityRepository.makeIdentity());

      final result = await evaluateAccountMigrationImportPrecondition(
        identityRepository: identityRepository,
        authorityRepository: authorityRepository,
      );

      expect(result.canStartImport, false);
      expect(
        result.status,
        AccountMigrationImportPreconditionStatus.activeAccountExists,
      );
    });

    test('rejects import when active authority already exists', () async {
      await authorityRepository.saveAuthority(
        AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.active,
          accountPeerId: '12D3KooWExisting',
        ),
      );

      final result = await evaluateAccountMigrationImportPrecondition(
        identityRepository: identityRepository,
        authorityRepository: authorityRepository,
      );

      expect(result.canStartImport, false);
      expect(
        result.status,
        AccountMigrationImportPreconditionStatus.activeAccountExists,
      );
    });

    test(
      'allows later explicit erase/reset precondition to override active account',
      () async {
        identityRepository.seed(FakeIdentityRepository.makeIdentity());
        await authorityRepository.saveAuthority(
          AccountMigrationAuthorityRecord(
            state: AccountMigrationAuthorityState.active,
            accountPeerId: '12D3KooWExisting',
          ),
        );

        final result = await evaluateAccountMigrationImportPrecondition(
          identityRepository: identityRepository,
          authorityRepository: authorityRepository,
          explicitErasePreconditionSatisfied: true,
        );

        expect(result.canStartImport, true);
        expect(result.status, AccountMigrationImportPreconditionStatus.allowed);
      },
    );

    test(
      'requires cleanup before import when authority failed closed',
      () async {
        await authorityRepository.saveAuthority(
          AccountMigrationAuthorityRecord(
            state:
                AccountMigrationAuthorityState.migrationFailedCleanupRequired,
          ),
        );

        final result = await evaluateAccountMigrationImportPrecondition(
          identityRepository: identityRepository,
          authorityRepository: authorityRepository,
        );

        expect(result.canStartImport, false);
        expect(
          result.status,
          AccountMigrationImportPreconditionStatus.cleanupRequired,
        );
      },
    );
  });
}
