import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';

enum MigrationSecureStoreScope { primary, iosSharedAccessGroup }

enum MigrationSecureStorageKeyCategory {
  dbEncryptionKey,
  identityPrivateKey,
  identityMnemonic12,
  identityMlKemSecretKey,
  secretsMigratedSentinel,
  backgroundPreference,
  imageQualityPreference,
  videoQualityPreference,
  pushFcmToken,
  pushFcmPlatform,
  accountMigrationAuthority,
  accountMigrationPairingSession,
  groupKeyMaterial,
  mediaAttachmentEncryptionKey,
}

enum MigrationSecureStorageKeyPolicy {
  migrate,
  clearRegenerate,
  derivedOnPromotion,
  deviceLocal,
}

enum MigrationSecureStorageKeyCriticality { critical, optional, cleanupOnly }

class MigrationSecureStorageKey {
  final MigrationSecureStoreScope scope;
  final String activeKey;
  final MigrationSecureStorageKeyCategory category;
  final MigrationSecureStorageKeyPolicy policy;
  final MigrationSecureStorageKeyCriticality criticality;
  final bool includeInExportPayload;

  const MigrationSecureStorageKey({
    required this.scope,
    required this.activeKey,
    required this.category,
    required this.policy,
    required this.criticality,
    bool? includeInExportPayload,
  }) : includeInExportPayload =
           includeInExportPayload ??
           policy == MigrationSecureStorageKeyPolicy.migrate;

  String? get appleAccessGroup =>
      scope == MigrationSecureStoreScope.iosSharedAccessGroup
      ? mknoonSharedAppleAccessGroup
      : null;

  bool get requiresStagedValueForPromotion =>
      policy == MigrationSecureStorageKeyPolicy.migrate &&
      criticality == MigrationSecureStorageKeyCriticality.critical;

  String get sortKey => '${scope.name}:$activeKey';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MigrationSecureStorageKey &&
            other.scope == scope &&
            other.activeKey == activeKey;
  }

  @override
  int get hashCode => Object.hash(scope, activeKey);

  @override
  String toString() => 'MigrationSecureStorageKey($sortKey)';
}
