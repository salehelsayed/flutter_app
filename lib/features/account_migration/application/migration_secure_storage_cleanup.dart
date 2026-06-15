import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
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
    final keys = MigrationSecureStorageRegistry.deduplicateAndSort(
      registryKeys,
    );
    for (final key in keys) {
      if (key.policy == MigrationSecureStorageKeyPolicy.deviceLocal &&
          !explicitLocalReset) {
        continue;
      }
      await _storeFor(key.scope).delete(key.activeKey);
    }
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
