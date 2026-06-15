import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';

class MigrationSecureStorageReferenceCollector {
  List<MigrationSecureStorageKey> collectDiscoveredKeys({
    Iterable<Map<String, Object?>> committedGroupKeyRows = const [],
    Iterable<Map<String, Object?>> pendingGroupKeyRows = const [],
    Iterable<Map<String, Object?>> mediaAttachmentRows = const [],
  }) {
    final keys = <MigrationSecureStorageKey>[];
    for (final row in committedGroupKeyRows) {
      _addPrimaryGroupKeyReference(keys, row);
      final groupId = row['group_id'] as String?;
      final generation = _intValue(row['key_generation']);
      if (groupId != null && generation != null) {
        keys.add(
          MigrationSecureStorageRegistry.sharedGroupMirror(
            groupId: groupId,
            generation: generation,
          ),
        );
      }
    }
    for (final row in pendingGroupKeyRows) {
      _addPrimaryGroupKeyReference(keys, row);
    }
    for (final row in mediaAttachmentRows) {
      final reference = row['encryption_key_base64'] as String?;
      if (!isSecureStoreReference(reference)) {
        continue;
      }
      keys.add(
        MigrationSecureStorageRegistry.primarySecureReference(
          secureReference: reference!,
          category:
              MigrationSecureStorageKeyCategory.mediaAttachmentEncryptionKey,
        ),
      );
    }
    return MigrationSecureStorageRegistry.deduplicateAndSort(keys);
  }

  void _addPrimaryGroupKeyReference(
    List<MigrationSecureStorageKey> keys,
    Map<String, Object?> row,
  ) {
    final reference = row['encrypted_key'] as String?;
    if (!isSecureStoreReference(reference)) {
      return;
    }
    keys.add(
      MigrationSecureStorageRegistry.primarySecureReference(
        secureReference: reference!,
        category: MigrationSecureStorageKeyCategory.groupKeyMaterial,
      ),
    );
  }

  int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}
