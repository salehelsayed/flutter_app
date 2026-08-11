import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_pairing_session_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MigrationSecureStorageRegistry', () {
    test(
      'classifies every fixed primary-store key with an explicit policy',
      () {
        final fixed = MigrationSecureStorageRegistry.fixedKeys;
        final byKey = {
          for (final key in fixed.where(
            (key) => key.scope == MigrationSecureStoreScope.primary,
          ))
            key.activeKey: key,
        };

        expect(
          byKey.keys,
          containsAll({
            'db_encryption_key',
            'identity_private_key',
            'identity_mnemonic12',
            'identity_ml_kem_secret_key',
            'secrets_migrated',
            'background_preference',
            'image_quality_preference',
            'video_quality_preference',
            'push_fcm_token',
            'push_fcm_platform',
            'push_registration_health_v1',
            PendingConversationNotificationOverlayStore.secureStorageKey,
            canonicalRuntimeInstallationIdStorageKey,
            canonicalRuntimeAccountBindingStorageKey,
            SecureKeyStoreAccountMigrationAuthorityRepository.storageKey,
            SecureKeyStoreMigrationPairingSessionRepository.storageKey,
            // 198 TC-198-37 — the sculpt geometry key is Move-registered.
            OrbitGeometryPrefs.storageKey,
          }),
        );

        expect(
          byKey['db_encryption_key']!.policy,
          MigrationSecureStorageKeyPolicy.migrate,
        );
        expect(
          byKey['identity_private_key']!.criticality,
          MigrationSecureStorageKeyCriticality.critical,
        );
        expect(
          byKey['identity_mnemonic12']!.policy,
          MigrationSecureStorageKeyPolicy.migrate,
        );
        expect(
          byKey['identity_ml_kem_secret_key']!.criticality,
          MigrationSecureStorageKeyCriticality.critical,
        );
        expect(
          byKey['secrets_migrated']!.policy,
          MigrationSecureStorageKeyPolicy.derivedOnPromotion,
        );
        expect(
          byKey['background_preference']!.policy,
          MigrationSecureStorageKeyPolicy.migrate,
        );
        expect(
          byKey['image_quality_preference']!.criticality,
          MigrationSecureStorageKeyCriticality.optional,
        );
        expect(
          byKey['video_quality_preference']!.policy,
          MigrationSecureStorageKeyPolicy.migrate,
        );
        expect(
          byKey['push_fcm_token']!.policy,
          MigrationSecureStorageKeyPolicy.clearRegenerate,
        );
        expect(byKey['push_fcm_platform']!.includeInExportPayload, isFalse);
        expect(
          byKey['push_registration_health_v1']!.category,
          MigrationSecureStorageKeyCategory.pushRegistrationHealth,
        );
        expect(
          byKey['push_registration_health_v1']!.policy,
          MigrationSecureStorageKeyPolicy.clearRegenerate,
        );
        expect(
          byKey['push_registration_health_v1']!.includeInExportPayload,
          isFalse,
        );
        final pendingOverlay =
            byKey[PendingConversationNotificationOverlayStore
                .secureStorageKey]!;
        expect(
          pendingOverlay.category,
          MigrationSecureStorageKeyCategory
              .pendingConversationNotificationOverlay,
        );
        expect(
          pendingOverlay.policy,
          MigrationSecureStorageKeyPolicy.clearRegenerate,
        );
        expect(
          pendingOverlay.criticality,
          MigrationSecureStorageKeyCriticality.cleanupOnly,
        );
        expect(pendingOverlay.includeInExportPayload, isFalse);
        for (final deviceBindingKey in <String>[
          canonicalRuntimeInstallationIdStorageKey,
          canonicalRuntimeAccountBindingStorageKey,
        ]) {
          expect(
            byKey[deviceBindingKey]!.policy,
            MigrationSecureStorageKeyPolicy.clearRegenerate,
          );
          expect(byKey[deviceBindingKey]!.includeInExportPayload, isFalse);
        }
        expect(
          byKey[SecureKeyStoreAccountMigrationAuthorityRepository.storageKey]!
              .policy,
          MigrationSecureStorageKeyPolicy.deviceLocal,
        );
        expect(
          byKey[SecureKeyStoreMigrationPairingSessionRepository.storageKey]!
              .includeInExportPayload,
          isFalse,
        );
        // 198 TC-198-37 — migrate + optional (critical would break every Move
        // from a never-sculpted phone) + exported (migrate ⇒ payload).
        expect(
          byKey[OrbitGeometryPrefs.storageKey]!.category,
          MigrationSecureStorageKeyCategory.orbitGeometryPreferences,
        );
        expect(
          byKey[OrbitGeometryPrefs.storageKey]!.policy,
          MigrationSecureStorageKeyPolicy.migrate,
        );
        expect(
          byKey[OrbitGeometryPrefs.storageKey]!.criticality,
          MigrationSecureStorageKeyCriticality.optional,
        );
        expect(
          byKey[OrbitGeometryPrefs.storageKey]!.includeInExportPayload,
          isTrue,
        );
      },
    );

    test('classifies iOS shared access-group identity and group mirrors', () {
      final sharedFixed = MigrationSecureStorageRegistry.fixedKeys.where(
        (key) => key.scope == MigrationSecureStoreScope.iosSharedAccessGroup,
      );

      expect(sharedFixed.single.activeKey, 'identity_ml_kem_secret_key');
      expect(sharedFixed.single.appleAccessGroup, mknoonSharedAppleAccessGroup);

      final groupMirror = MigrationSecureStorageRegistry.sharedGroupMirror(
        groupId: 'group/raw:1',
        generation: 7,
      );

      expect(groupMirror.scope, MigrationSecureStoreScope.iosSharedAccessGroup);
      expect(groupMirror.activeKey, 'group_key:group/raw:1:7');
      expect(groupMirror.policy, MigrationSecureStorageKeyPolicy.migrate);
      expect(
        groupMirror.criticality,
        MigrationSecureStorageKeyCriticality.critical,
      );
      expect(groupMirror.includeInExportPayload, isTrue);
    });

    test('merges fixed and DB-discovered keys deterministically', () {
      final media = MigrationSecureStorageRegistry.primaryMediaAttachmentKey(
        attachmentId: 'photo 1',
      );
      final group = MigrationSecureStorageRegistry.primaryGroupKeyMaterial(
        groupId: 'group/1',
        generation: 3,
      );

      final resolved = MigrationSecureStorageRegistry.resolve(
        discoveredKeys: [media, group, media],
      );
      final resolvedIds = resolved
          .map((key) => '${key.scope.name}:${key.activeKey}')
          .toList();

      expect(
        resolvedIds.where(
          (id) => id == 'primary:media_attachment_encryption_key:photo%201',
        ),
        hasLength(1),
      );
      expect(resolvedIds, contains('primary:group_key_material:group%2F1:3'));
      expect(resolvedIds, equals(resolvedIds.toList()..sort()));
    });

    test('TC-360-01b v112 remote roster migrates while linked installation '
        'authority cannot move', () {
      // The linked role marker and the transport credential are DEVICE-LOCAL
      // authority, never account data. Marking them `migrate` would let a
      // Move clone one installation's transport identity onto a second
      // device — exactly the shared-mailbox failure Plan 360 exists to
      // prevent — and would put raw Ed25519 private key material into an
      // exported bundle.
      for (final activeKey in const <String>[
        linkedInstallationRoleStorageKey,
        linkedInstallationTransportCredentialStorageKey,
      ]) {
        final key = MigrationSecureStorageRegistry.fixedKey(
          scope: MigrationSecureStoreScope.primary,
          activeKey: activeKey,
        );
        expect(key, isNotNull, reason: activeKey);
        expect(
          key!.policy,
          MigrationSecureStorageKeyPolicy.deviceLocal,
          reason: activeKey,
        );
        expect(
          key.includeInExportPayload,
          isFalse,
          reason: '$activeKey must never enter an exported/staged bundle',
        );
        expect(
          key.criticality,
          MigrationSecureStorageKeyCriticality.cleanupOnly,
          reason: activeKey,
        );
        expect(
          key.requiresStagedValueForPromotion,
          isFalse,
          reason: '$activeKey is never promoted on the destination',
        );
      }

      // Registered exactly once each, and absent from the export payload set.
      final exported = MigrationSecureStorageRegistry.fixedKeys
          .where((key) => key.includeInExportPayload)
          .map((key) => key.activeKey)
          .toSet();
      expect(exported, isNot(contains(linkedInstallationRoleStorageKey)));
      expect(
        exported,
        isNot(contains(linkedInstallationTransportCredentialStorageKey)),
      );
      for (final activeKey in const <String>[
        linkedInstallationRoleStorageKey,
        linkedInstallationTransportCredentialStorageKey,
      ]) {
        expect(
          MigrationSecureStorageRegistry.fixedKeys.where(
            (key) => key.activeKey == activeKey,
          ),
          hasLength(1),
          reason: activeKey,
        );
      }
    });
  });
}
