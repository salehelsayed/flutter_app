import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_pairing_session_repository_impl.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/push/infrastructure/push_token_store_impl.dart';
import 'package:flutter_app/features/push/infrastructure/push_registration_health_store.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

class MigrationSecureStorageRegistry {
  static const dbEncryptionKey = 'db_encryption_key';
  static const identityPrivateKey = 'identity_private_key';
  static const identityMnemonic12 = 'identity_mnemonic12';
  static const identityMlKemSecretKey = 'identity_ml_kem_secret_key';
  static const secretsMigrated = 'secrets_migrated';

  static const List<MigrationSecureStorageKey> _fixedKeys = [
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: dbEncryptionKey,
      category: MigrationSecureStorageKeyCategory.dbEncryptionKey,
      policy: MigrationSecureStorageKeyPolicy.migrate,
      criticality: MigrationSecureStorageKeyCriticality.critical,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: identityPrivateKey,
      category: MigrationSecureStorageKeyCategory.identityPrivateKey,
      policy: MigrationSecureStorageKeyPolicy.migrate,
      criticality: MigrationSecureStorageKeyCriticality.critical,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: identityMnemonic12,
      category: MigrationSecureStorageKeyCategory.identityMnemonic12,
      policy: MigrationSecureStorageKeyPolicy.migrate,
      criticality: MigrationSecureStorageKeyCriticality.critical,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: identityMlKemSecretKey,
      category: MigrationSecureStorageKeyCategory.identityMlKemSecretKey,
      policy: MigrationSecureStorageKeyPolicy.migrate,
      criticality: MigrationSecureStorageKeyCriticality.critical,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: secretsMigrated,
      category: MigrationSecureStorageKeyCategory.secretsMigratedSentinel,
      policy: MigrationSecureStorageKeyPolicy.derivedOnPromotion,
      criticality: MigrationSecureStorageKeyCriticality.critical,
      includeInExportPayload: false,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: BackgroundPreference.storageKey,
      category: MigrationSecureStorageKeyCategory.backgroundPreference,
      policy: MigrationSecureStorageKeyPolicy.migrate,
      criticality: MigrationSecureStorageKeyCriticality.optional,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: ImageQualityPreference.storageKey,
      category: MigrationSecureStorageKeyCategory.imageQualityPreference,
      policy: MigrationSecureStorageKeyPolicy.migrate,
      criticality: MigrationSecureStorageKeyCriticality.optional,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: ImageQualityPreference.videoStorageKey,
      category: MigrationSecureStorageKeyCategory.videoQualityPreference,
      policy: MigrationSecureStorageKeyPolicy.migrate,
      criticality: MigrationSecureStorageKeyCriticality.optional,
    ),
    // 198 — the Orbit sculpt geometry knobs. OPTIONAL is forced: critical would
    // break every Move from a phone that never sculpted (no stored value).
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: OrbitGeometryPrefs.storageKey,
      category: MigrationSecureStorageKeyCategory.orbitGeometryPreferences,
      policy: MigrationSecureStorageKeyPolicy.migrate,
      criticality: MigrationSecureStorageKeyCriticality.optional,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: pushFcmTokenSecureStorageKey,
      category: MigrationSecureStorageKeyCategory.pushFcmToken,
      policy: MigrationSecureStorageKeyPolicy.clearRegenerate,
      criticality: MigrationSecureStorageKeyCriticality.cleanupOnly,
      includeInExportPayload: false,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: pushFcmPlatformSecureStorageKey,
      category: MigrationSecureStorageKeyCategory.pushFcmPlatform,
      policy: MigrationSecureStorageKeyPolicy.clearRegenerate,
      criticality: MigrationSecureStorageKeyCriticality.cleanupOnly,
      includeInExportPayload: false,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: pushRegistrationHealthSecureStorageKey,
      category: MigrationSecureStorageKeyCategory.pushRegistrationHealth,
      policy: MigrationSecureStorageKeyPolicy.clearRegenerate,
      criticality: MigrationSecureStorageKeyCriticality.cleanupOnly,
      includeInExportPayload: false,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: PendingConversationNotificationOverlayStore.secureStorageKey,
      category: MigrationSecureStorageKeyCategory
          .pendingConversationNotificationOverlay,
      policy: MigrationSecureStorageKeyPolicy.clearRegenerate,
      criticality: MigrationSecureStorageKeyCriticality.cleanupOnly,
      includeInExportPayload: false,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: canonicalRuntimeInstallationIdStorageKey,
      category:
          MigrationSecureStorageKeyCategory.canonicalRuntimeInstallationId,
      policy: MigrationSecureStorageKeyPolicy.clearRegenerate,
      criticality: MigrationSecureStorageKeyCriticality.cleanupOnly,
      includeInExportPayload: false,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: canonicalRuntimeAccountBindingStorageKey,
      category:
          MigrationSecureStorageKeyCategory.canonicalRuntimeAccountBinding,
      policy: MigrationSecureStorageKeyPolicy.clearRegenerate,
      criticality: MigrationSecureStorageKeyCriticality.cleanupOnly,
      includeInExportPayload: false,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: SecureKeyStoreAccountMigrationAuthorityRepository.storageKey,
      category: MigrationSecureStorageKeyCategory.accountMigrationAuthority,
      policy: MigrationSecureStorageKeyPolicy.deviceLocal,
      criticality: MigrationSecureStorageKeyCriticality.cleanupOnly,
      includeInExportPayload: false,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: SecureKeyStoreMigrationPairingSessionRepository.storageKey,
      category:
          MigrationSecureStorageKeyCategory.accountMigrationPairingSession,
      policy: MigrationSecureStorageKeyPolicy.deviceLocal,
      criticality: MigrationSecureStorageKeyCriticality.cleanupOnly,
      includeInExportPayload: false,
    ),
    // 360: the linked-secondary installation role and its transport
    // credential are DEVICE-LOCAL authority, never account data.
    //
    // `deviceLocal` + `includeInExportPayload: false` is load-bearing twice
    // over. It keeps raw transport key material out of every exported and
    // staged bundle, and it makes the incumbent explicit local reset
    // (`eraseAccount(explicitLocalReset: true)`) delete the marker, the
    // credential, and the canonical runtime installation ID together — the
    // only sanctioned way to retire linked authority. Marking them `migrate`
    // would let an account Move clone one installation's transport identity
    // onto a second device, which is exactly the shared-mailbox failure this
    // plan exists to prevent.
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: linkedInstallationRoleStorageKey,
      category: MigrationSecureStorageKeyCategory.linkedInstallationRole,
      policy: MigrationSecureStorageKeyPolicy.deviceLocal,
      criticality: MigrationSecureStorageKeyCriticality.cleanupOnly,
      includeInExportPayload: false,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: linkedInstallationTransportCredentialStorageKey,
      category: MigrationSecureStorageKeyCategory
          .linkedInstallationTransportCredential,
      policy: MigrationSecureStorageKeyPolicy.deviceLocal,
      criticality: MigrationSecureStorageKeyCriticality.cleanupOnly,
      includeInExportPayload: false,
    ),
    MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.iosSharedAccessGroup,
      activeKey: identityMlKemSecretKey,
      category: MigrationSecureStorageKeyCategory.identityMlKemSecretKey,
      policy: MigrationSecureStorageKeyPolicy.migrate,
      criticality: MigrationSecureStorageKeyCriticality.critical,
    ),
  ];

  static List<MigrationSecureStorageKey> get fixedKeys =>
      List.unmodifiable(_fixedKeys);

  static MigrationSecureStorageKey? fixedKey({
    required MigrationSecureStoreScope scope,
    required String activeKey,
  }) {
    for (final key in _fixedKeys) {
      if (key.scope == scope && key.activeKey == activeKey) {
        return key;
      }
    }
    return null;
  }

  static MigrationSecureStorageKey primaryGroupKeyMaterial({
    required String groupId,
    required int generation,
  }) {
    return MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: groupKeyMaterialStoreName(groupId, generation),
      category: MigrationSecureStorageKeyCategory.groupKeyMaterial,
      policy: MigrationSecureStorageKeyPolicy.migrate,
      criticality: MigrationSecureStorageKeyCriticality.critical,
    );
  }

  static MigrationSecureStorageKey primaryMediaAttachmentKey({
    required String attachmentId,
  }) {
    return MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: mediaAttachmentEncryptionKeyStoreName(attachmentId),
      category: MigrationSecureStorageKeyCategory.mediaAttachmentEncryptionKey,
      policy: MigrationSecureStorageKeyPolicy.migrate,
      criticality: MigrationSecureStorageKeyCriticality.critical,
    );
  }

  static MigrationSecureStorageKey primarySecureReference({
    required String secureReference,
    required MigrationSecureStorageKeyCategory category,
  }) {
    final activeKey = isSecureStoreReference(secureReference)
        ? secureStoreKeyFromReference(secureReference)
        : secureReference;
    return MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: activeKey,
      category: category,
      policy: MigrationSecureStorageKeyPolicy.migrate,
      criticality: MigrationSecureStorageKeyCriticality.critical,
    );
  }

  static MigrationSecureStorageKey sharedGroupMirror({
    required String groupId,
    required int generation,
  }) {
    return MigrationSecureStorageKey(
      scope: MigrationSecureStoreScope.iosSharedAccessGroup,
      activeKey: 'group_key:$groupId:$generation',
      category: MigrationSecureStorageKeyCategory.groupKeyMaterial,
      policy: MigrationSecureStorageKeyPolicy.migrate,
      criticality: MigrationSecureStorageKeyCriticality.critical,
    );
  }

  static List<MigrationSecureStorageKey> resolve({
    Iterable<MigrationSecureStorageKey> discoveredKeys = const [],
  }) {
    return deduplicateAndSort([..._fixedKeys, ...discoveredKeys]);
  }

  static List<MigrationSecureStorageKey> deduplicateAndSort(
    Iterable<MigrationSecureStorageKey> keys,
  ) {
    final byId = <String, MigrationSecureStorageKey>{};
    for (final key in keys) {
      byId[key.sortKey] = key;
    }
    final sorted = byId.values.toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return List.unmodifiable(sorted);
  }
}
