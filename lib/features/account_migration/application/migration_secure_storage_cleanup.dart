import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';

class MigrationSecureStorageCleanup {
  final MigrationSecureStorageStaging staging;

  const MigrationSecureStorageCleanup({required this.staging});

  Future<void> eraseAccount({
    required Iterable<MigrationSecureStorageKey> registryKeys,
    required bool explicitLocalReset,
  }) async {
    if (explicitLocalReset) {
      await _eraseExplicitLocalAccount();
      return;
    }
    final keys = MigrationSecureStorageRegistry.deduplicateAndSort(
      registryKeys,
    );
    for (final key in keys) {
      if (key.policy == MigrationSecureStorageKeyPolicy.deviceLocal) {
        continue;
      }
      await _storeFor(key.scope).delete(key.activeKey);
    }
  }

  Future<void> _eraseExplicitLocalAccount() async {
    final removals = <(SecureKeyStore, String)>[];
    // Inventory every available scope before deleting anything. Failure to
    // enumerate must retain the database key and blocked-account authority.
    for (final (scope, store) in [
      (MigrationSecureStoreScope.primary, staging.primaryStore),
      if (staging.sharedStore != null)
        (MigrationSecureStoreScope.iosSharedAccessGroup, staging.sharedStore!),
    ]) {
      if (store is! SecureKeyStoreInventory) {
        throw StateError('Secure storage inventory is unavailable');
      }
      final entries = await (store as SecureKeyStoreInventory).readAll();
      for (final key in entries.keys) {
        if (scope == MigrationSecureStoreScope.primary &&
            MigrationSecureStorageRegistry.accountErasePreservedPrimaryKeys
                .contains(key)) {
          continue;
        }
        removals.add((store, key));
      }
    }
    // The database has already been removed by the caller. Keep its key and
    // retired authority until all other account entries are deleted/read back.
    removals.sort(
      (a, b) => _erasePriority(a.$2).compareTo(_erasePriority(b.$2)),
    );
    for (final (store, key) in removals) {
      await store.delete(key);
      if (await store.containsKey(key)) {
        throw StateError('Account secure-storage erasure incomplete');
      }
    }
  }

  int _erasePriority(String key) {
    if (key == SecureKeyStoreAccountMigrationAuthorityRepository.storageKey) {
      return 2;
    }
    if (key == MigrationSecureStorageRegistry.dbEncryptionKey) return 1;
    return 0;
  }

  Future<void> successfulImportCleanup({
    required String sessionId,
    required Iterable<MigrationSecureStorageKey> registryKeys,
  }) async {
    await staging.deleteStagingValues(
      sessionId: sessionId,
      registryKeys: registryKeys,
    );
    await staging.clearPromotionJournal(sessionId: sessionId);
  }

  Future<void> cancelledImportCleanup({
    required String sessionId,
    required Iterable<MigrationSecureStorageKey> registryKeys,
  }) async {
    await staging.deleteStagingValues(
      sessionId: sessionId,
      registryKeys: registryKeys,
    );
    await staging.clearPromotionJournal(sessionId: sessionId);
  }

  Future<void> failedImportCleanup({
    required String sessionId,
    required Iterable<MigrationSecureStorageKey> registryKeys,
  }) async {
    await staging.rollbackPromoted(sessionId: sessionId);
    await staging.deleteStagingValues(
      sessionId: sessionId,
      registryKeys: registryKeys,
    );
    await staging.clearPromotionJournal(sessionId: sessionId);
  }

  SecureKeyStore _storeFor(MigrationSecureStoreScope scope) {
    switch (scope) {
      case MigrationSecureStoreScope.primary:
        return staging.primaryStore;
      case MigrationSecureStoreScope.iosSharedAccessGroup:
        final store = staging.sharedStore;
        if (store == null) {
          throw StateError('iOS shared access-group secure store is required');
        }
        return store;
    }
  }
}
