import 'dart:io';

import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_pairing_session_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('migration secure-storage source audit', () {
    test(
      'current fixed app-owned secure-store literals are registry-classified',
      () {
        final libText = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .map((file) => file.readAsStringSync())
            .join('\n');
        final registryFixed = MigrationSecureStorageRegistry.fixedKeys
            .where((key) => key.scope == MigrationSecureStoreScope.primary)
            .map((key) => key.activeKey)
            .toSet();

        const expectedFixedKeys = {
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
        };

        for (final key in expectedFixedKeys) {
          expect(
            libText,
            contains(key),
            reason: 'source literal disappeared: $key',
          );
          expect(
            registryFixed,
            contains(key),
            reason: 'registry missing: $key',
          );
        }
        expect(
          registryFixed,
          contains(
            SecureKeyStoreAccountMigrationAuthorityRepository.storageKey,
          ),
        );
        expect(
          registryFixed,
          contains(SecureKeyStoreMigrationPairingSessionRepository.storageKey),
        );
      },
    );
  });
}
