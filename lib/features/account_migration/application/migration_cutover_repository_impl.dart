import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_cutover_record.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_cutover_repository.dart';

class SecureKeyStoreMigrationCutoverRepository
    implements MigrationCutoverRepository {
  static const storageKeyPrefix = 'account_migration_cutover';
  static const storageKey = '$storageKeyPrefix:v1';

  final SecureKeyStore _secureKeyStore;

  const SecureKeyStoreMigrationCutoverRepository({
    required SecureKeyStore secureKeyStore,
  }) : _secureKeyStore = secureKeyStore;

  @override
  Future<MigrationCutoverRecord?> loadCutover() async {
    final raw = await _secureKeyStore.read(storageKey);
    if (raw == null) return null;
    return MigrationCutoverRecord.fromPersistedJson(raw);
  }

  @override
  Future<void> saveCutover(MigrationCutoverRecord record) {
    return _secureKeyStore.write(storageKey, record.toPersistedJson());
  }

  @override
  Future<void> clearCutover() {
    return _secureKeyStore.delete(storageKey);
  }
}
