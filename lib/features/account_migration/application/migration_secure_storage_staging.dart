import 'dart:convert';

import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';

class MigrationSecureStoragePromotionResult {
  final List<MigrationSecureStorageKey> promotedKeys;

  const MigrationSecureStoragePromotionResult({required this.promotedKeys});
}

class MigrationSecureStorageStaging {
  static const stagingPrefix = 'account_migration:staging:v1:';
  static const promotedJournalPrefix = 'account_migration:promoted:v1:';

  final SecureKeyStore primaryStore;
  final SecureKeyStore? sharedStore;

  const MigrationSecureStorageStaging({
    required this.primaryStore,
    this.sharedStore,
  });

  static String stagingKeyFor({
    required String sessionId,
    required MigrationSecureStorageKey key,
  }) {
    return '$stagingPrefix${Uri.encodeComponent(sessionId)}:'
        '${key.scope.name}:${Uri.encodeComponent(key.activeKey)}';
  }

  static String promotedJournalKey(String sessionId) {
    return '$promotedJournalPrefix${Uri.encodeComponent(sessionId)}';
  }

  Future<void> stageValue({
    required String sessionId,
    required MigrationSecureStorageKey key,
    required String value,
  }) {
    return _storeFor(
      key.scope,
    ).write(stagingKeyFor(sessionId: sessionId, key: key), value);
  }

  Future<String?> readStagedValue({
    required String sessionId,
    required MigrationSecureStorageKey key,
  }) {
    return _storeFor(
      key.scope,
    ).read(stagingKeyFor(sessionId: sessionId, key: key));
  }

  Future<MigrationSecureStoragePromotionResult> promote({
    required String sessionId,
    required Iterable<MigrationSecureStorageKey> registryKeys,
  }) async {
    final keys = MigrationSecureStorageRegistry.deduplicateAndSort(
      registryKeys,
    );
    await _validateRequiredStagedValues(sessionId: sessionId, keys: keys);
    final promoted = <MigrationSecureStorageKey>[];
    for (final key in keys) {
      switch (key.policy) {
        case MigrationSecureStorageKeyPolicy.migrate:
          final stagedValue = await readStagedValue(
            sessionId: sessionId,
            key: key,
          );
          if (stagedValue == null) {
            continue;
          }
          await _storeFor(key.scope).write(key.activeKey, stagedValue);
          promoted.add(key);
          await _recordPromoted(sessionId, promoted);
          break;
        case MigrationSecureStorageKeyPolicy.clearRegenerate:
          await _storeFor(key.scope).delete(key.activeKey);
          break;
        case MigrationSecureStorageKeyPolicy.derivedOnPromotion:
          await _promoteDerivedKey(sessionId: sessionId, key: key);
          promoted.add(key);
          await _recordPromoted(sessionId, promoted);
          break;
        case MigrationSecureStorageKeyPolicy.deviceLocal:
          break;
      }
    }
    return MigrationSecureStoragePromotionResult(
      promotedKeys: List.unmodifiable(promoted),
    );
  }

  Future<void> rollbackPromoted({required String sessionId}) async {
    final entries = await _loadPromotedEntries(sessionId);
    for (final entry in entries.reversed) {
      await _storeFor(entry.scope).delete(entry.activeKey);
    }
    await clearPromotionJournal(sessionId: sessionId);
  }

  Future<void> deleteStagingValues({
    required String sessionId,
    required Iterable<MigrationSecureStorageKey> registryKeys,
  }) async {
    for (final key in MigrationSecureStorageRegistry.deduplicateAndSort(
      registryKeys,
    )) {
      await _storeFor(
        key.scope,
      ).delete(stagingKeyFor(sessionId: sessionId, key: key));
    }
  }

  Future<void> clearPromotionJournal({required String sessionId}) {
    return primaryStore.delete(promotedJournalKey(sessionId));
  }

  Future<void> _validateRequiredStagedValues({
    required String sessionId,
    required Iterable<MigrationSecureStorageKey> keys,
  }) async {
    final missing = <String>[];
    for (final key in keys) {
      if (!key.requiresStagedValueForPromotion) {
        continue;
      }
      final stagedValue = await readStagedValue(sessionId: sessionId, key: key);
      if (stagedValue == null || stagedValue.isEmpty) {
        missing.add(key.sortKey);
      }
    }
    if (missing.isNotEmpty) {
      throw StateError(
        'Cannot promote account-migration secure storage; missing staged '
        'critical keys: ${missing.join(', ')}',
      );
    }
  }

  Future<void> _promoteDerivedKey({
    required String sessionId,
    required MigrationSecureStorageKey key,
  }) async {
    if (key.category !=
        MigrationSecureStorageKeyCategory.secretsMigratedSentinel) {
      throw StateError(
        'Unsupported derived secure-storage key: ${key.activeKey}',
      );
    }
    await _storeFor(key.scope).write(key.activeKey, 'true');
  }

  Future<void> _recordPromoted(
    String sessionId,
    List<MigrationSecureStorageKey> promoted,
  ) async {
    final payload = promoted
        .map((key) => {'scope': key.scope.name, 'activeKey': key.activeKey})
        .toList(growable: false);
    await primaryStore.write(
      promotedJournalKey(sessionId),
      jsonEncode(payload),
    );
  }

  Future<List<_PromotedEntry>> _loadPromotedEntries(String sessionId) async {
    final raw = await primaryStore.read(promotedJournalKey(sessionId));
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map>()
        .map((entry) => _PromotedEntry.fromJson(entry.cast<String, Object?>()))
        .whereType<_PromotedEntry>()
        .toList(growable: false);
  }

  SecureKeyStore _storeFor(MigrationSecureStoreScope scope) {
    switch (scope) {
      case MigrationSecureStoreScope.primary:
        return primaryStore;
      case MigrationSecureStoreScope.iosSharedAccessGroup:
        final store = sharedStore;
        if (store == null) {
          throw StateError('iOS shared access-group secure store is required');
        }
        return store;
    }
  }
}

class _PromotedEntry {
  final MigrationSecureStoreScope scope;
  final String activeKey;

  const _PromotedEntry({required this.scope, required this.activeKey});

  static _PromotedEntry? fromJson(Map<String, Object?> json) {
    final scopeName = json['scope'] as String?;
    final activeKey = json['activeKey'] as String?;
    if (scopeName == null || activeKey == null) {
      return null;
    }
    MigrationSecureStoreScope? scope;
    for (final value in MigrationSecureStoreScope.values) {
      if (value.name == scopeName) {
        scope = value;
        break;
      }
    }
    if (scope == null) {
      return null;
    }
    return _PromotedEntry(scope: scope, activeKey: activeKey);
  }
}
