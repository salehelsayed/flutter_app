import 'package:flutter_app/core/notifications/canonical_recovery_authority_storage_keys.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';

class SecureKeyStoreAccountMigrationAuthorityRepository
    implements AccountMigrationAuthorityRepository {
  static const storageKeyPrefix = accountMigrationAuthorityStorageKeyPrefix;
  static const storageKey = accountMigrationAuthorityStorageKey;

  final SecureKeyStore _secureKeyStore;

  const SecureKeyStoreAccountMigrationAuthorityRepository({
    required SecureKeyStore secureKeyStore,
  }) : _secureKeyStore = secureKeyStore;

  @override
  Future<AccountMigrationAuthorityRecord?> loadAuthority() async {
    final raw = await _secureKeyStore.read(storageKey);
    if (raw == null) {
      return null;
    }
    return AccountMigrationAuthorityRecord.fromPersistedJson(raw);
  }

  @override
  Future<void> saveAuthority(AccountMigrationAuthorityRecord record) {
    return _secureKeyStore.write(storageKey, record.toPersistedJson());
  }

  @override
  Future<void> clearAuthority() {
    return _secureKeyStore.delete(storageKey);
  }
}
