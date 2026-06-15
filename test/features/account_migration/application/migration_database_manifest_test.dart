import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_schema_inventory.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MigrationDatabaseManifest', () {
    test(
      'serializes protocol, app, db, checksum, cipher, and inventory data',
      () {
        final inventory = MigrationDatabaseSchemaInventory.fromTables({
          'identity': const ['id', 'peer_id', 'private_key', 'mnemonic12'],
          'group_messages': const ['id', 'logical_delivery_id'],
        });
        final manifest = MigrationDatabaseManifest.current(
          sourceAppVersion: '1.2.3',
          sourceBuildNumber: '456',
          schemaInventory: inventory,
          databaseChecksumSha256: 'a' * 64,
          cipherMetadata: const MigrationDatabaseCipherMetadata(
            cipherVersion: '4.6.0',
            kdfIter: 256000,
            cipherPageSize: 4096,
            policy: MigrationDatabaseCipherPolicy.compatible,
          ),
        );

        final json = manifest.toJson();

        expect(
          json['protocol_version'],
          MigrationDatabaseManifest.protocolVersion,
        );
        expect(json['source_app_version'], '1.2.3');
        expect(json['source_build_number'], '456');
        expect(json['minimum_importer_protocol_version'], 1);
        expect(json['database_version'], currentIdentityDatabaseVersion);
        expect(json['schema_hash'], inventory.schemaHash);
        expect(json['database_checksum_sha256'], 'a' * 64);
        expect(json['cipher_metadata'], isA<Map<String, Object?>>());
        expect(json['schema_inventory'], isA<Map<String, Object?>>());
      },
    );

    test('rejects incompatible protocol, importer, and database versions', () {
      final inventory = MigrationDatabaseSchemaInventory.fromTables({
        'identity': const ['id', 'peer_id'],
      });
      final manifest = MigrationDatabaseManifest.current(
        sourceAppVersion: MigrationDatabaseManifest.unknownAppVersion,
        sourceBuildNumber: MigrationDatabaseManifest.unknownBuildNumber,
        schemaInventory: inventory,
        databaseChecksumSha256: 'b' * 64,
        cipherMetadata: const MigrationDatabaseCipherMetadata(
          cipherVersion: '4.6.0',
          policy: MigrationDatabaseCipherPolicy.compatible,
        ),
      );

      expect(manifest.compatibility().isAccepted, isTrue);
      expect(
        manifest
            .copyWith(protocolVersion: 999)
            .compatibility()
            .hasError(
              MigrationDatabaseManifestError.unsupportedProtocolVersion,
            ),
        isTrue,
      );
      expect(
        manifest
            .copyWith(minimumImporterProtocolVersion: 999)
            .compatibility()
            .hasError(MigrationDatabaseManifestError.importerTooOld),
        isTrue,
      );
      expect(
        manifest
            .copyWith(databaseVersion: currentIdentityDatabaseVersion + 1)
            .compatibility()
            .hasError(
              MigrationDatabaseManifestError.unsupportedDatabaseVersion,
            ),
        isTrue,
      );
    });
  });
}
