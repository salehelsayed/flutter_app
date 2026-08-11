import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

enum AccountMigrationImportPreconditionStatus {
  allowed,
  activeAccountExists,
  cleanupRequired,

  /// 360: this installation already holds linked-secondary authority.
  ///
  /// A linked secondary is a RESTRICTED role, not a second primary, so it can
  /// never be a Move destination. Importing an account here would leave one
  /// installation holding both a promoted primary identity and a transport
  /// credential that contacts have already bound device rows to.
  linkedSecondaryInstallation,
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

  static const linkedSecondaryInstallation =
      AccountMigrationImportPreconditionResult._(
        AccountMigrationImportPreconditionStatus.linkedSecondaryInstallation,
      );

  bool get canStartImport =>
      status == AccountMigrationImportPreconditionStatus.allowed;
}

Future<AccountMigrationImportPreconditionResult>
evaluateAccountMigrationImportPrecondition({
  required IdentityRepository identityRepository,
  required AccountMigrationAuthorityRepository authorityRepository,
  bool explicitErasePreconditionSatisfied = false,
  LinkedInstallationAuthority? linkedInstallationAuthority,
}) async {
  // 360: the linked-role check runs BEFORE the explicit-erase escape hatch.
  // Erasing the migrated-out account does not retire linked authority — only
  // an explicit linked reset does — so allowing the escape hatch to bypass
  // this would reopen exactly the case the status exists to refuse.
  if (linkedInstallationAuthority != null) {
    final snapshot = await linkedInstallationAuthority.load();
    if (snapshot.disposition != LinkedInstallationDisposition.primary) {
      return AccountMigrationImportPreconditionResult
          .linkedSecondaryInstallation;
    }
  }

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
