import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

enum AccountMigrationImportPreconditionStatus {
  allowed,
  activeAccountExists,
  cleanupRequired,
}

class AccountMigrationImportPreconditionResult {
  final AccountMigrationImportPreconditionStatus status;

  const AccountMigrationImportPreconditionResult._(this.status);

  static const allowed = AccountMigrationImportPreconditionResult._(
    AccountMigrationImportPreconditionStatus.allowed,
  );

  static const activeAccountExists = AccountMigrationImportPreconditionResult._(
    AccountMigrationImportPreconditionStatus.activeAccountExists,
  );

  static const cleanupRequired = AccountMigrationImportPreconditionResult._(
    AccountMigrationImportPreconditionStatus.cleanupRequired,
  );

  bool get canStartImport =>
      status == AccountMigrationImportPreconditionStatus.allowed;
}

Future<AccountMigrationImportPreconditionResult>
evaluateAccountMigrationImportPrecondition({
  required IdentityRepository identityRepository,
  required AccountMigrationAuthorityRepository authorityRepository,
  bool explicitErasePreconditionSatisfied = false,
}) async {
  if (explicitErasePreconditionSatisfied) {
    return AccountMigrationImportPreconditionResult.allowed;
  }

  final identity = await identityRepository.loadIdentity();
  if (identity != null) {
    return AccountMigrationImportPreconditionResult.activeAccountExists;
  }

  final authority = await authorityRepository.loadAuthority();
  if (authority == null) {
    return AccountMigrationImportPreconditionResult.allowed;
  }

  if (authority.isFailClosed || authority.blocksNormalStartup) {
    if (authority.state.isImportStaging) {
      return AccountMigrationImportPreconditionResult.allowed;
    }
    return AccountMigrationImportPreconditionResult.cleanupRequired;
  }

  if (authority.state.isActiveAccountAuthority) {
    return AccountMigrationImportPreconditionResult.activeAccountExists;
  }

  return AccountMigrationImportPreconditionResult.allowed;
}
