import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';

abstract class AccountMigrationAuthorityRepository {
  Future<AccountMigrationAuthorityRecord?> loadAuthority();

  Future<void> saveAuthority(AccountMigrationAuthorityRecord record);

  Future<void> clearAuthority();
}
