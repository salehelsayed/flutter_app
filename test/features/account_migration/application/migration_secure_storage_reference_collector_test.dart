import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_reference_collector.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MigrationSecureStorageReferenceCollector', () {
    test(
      'collects committed group, pending group, and media secure references',
      () {
        final collector = MigrationSecureStorageReferenceCollector();

        final discovered = collector.collectDiscoveredKeys(
          committedGroupKeyRows: [
            {
              'group_id': 'group raw/1',
              'key_generation': 4,
              'encrypted_key': secureStoreReferenceForKey(
                groupKeyMaterialStoreName('group raw/1', 4),
              ),
            },
          ],
          pendingGroupKeyRows: [
            {
              'group_id': 'pending group',
              'key_generation': 9,
              'encrypted_key': secureStoreReferenceForKey(
                groupKeyMaterialStoreName('pending group', 9),
              ),
            },
          ],
          mediaAttachmentRows: [
            {
              'id': 'photo 1',
              'encryption_key_base64': secureStoreReferenceForKey(
                mediaAttachmentEncryptionKeyStoreName('photo 1'),
              ),
            },
          ],
        );

        final ids = discovered
            .map((key) => '${key.scope.name}:${key.activeKey}')
            .toSet();

        expect(ids, contains('primary:group_key_material:group%20raw%2F1:4'));
        expect(ids, contains('primary:group_key_material:pending%20group:9'));
        expect(
          ids,
          contains('primary:media_attachment_encryption_key:photo%201'),
        );
        expect(ids, contains('iosSharedAccessGroup:group_key:group raw/1:4'));
        expect(
          ids,
          isNot(contains('iosSharedAccessGroup:group_key:pending group:9')),
        );
      },
    );

    test('merges DB-discovered references with fixed registry entries', () {
      final collector = MigrationSecureStorageReferenceCollector();
      final discovered = collector.collectDiscoveredKeys(
        mediaAttachmentRows: [
          {
            'id': 'blob-1',
            'encryption_key_base64': secureStoreReferenceForKey(
              mediaAttachmentEncryptionKeyStoreName('blob-1'),
            ),
          },
        ],
      );

      final resolved = MigrationSecureStorageRegistry.resolve(
        discoveredKeys: discovered,
      );

      expect(
        resolved,
        contains(
          isA<MigrationSecureStorageKey>().having(
            (key) => key.activeKey,
            'activeKey',
            'db_encryption_key',
          ),
        ),
      );
      expect(
        resolved,
        contains(
          isA<MigrationSecureStorageKey>().having(
            (key) => key.activeKey,
            'activeKey',
            'media_attachment_encryption_key:blob-1',
          ),
        ),
      );
    });
  });
}
