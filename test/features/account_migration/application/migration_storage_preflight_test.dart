import 'package:flutter_app/features/account_migration/application/migration_storage_preflight.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_file_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MigrationStoragePreflight', () {
    test(
      'accepts when available bytes cover required bytes plus headroom',
      () async {
        final preflight = MigrationStoragePreflight(
          availableBytesProvider: () async => 2000,
          stagingOverheadBytes: 100,
          headroomBytes: 250,
        );

        final result = await preflight.evaluate(
          manifest: MigrationFileManifest(
            items: [
              _item(path: 'media/a.jpg', size: 400),
              _item(
                path: 'media/a.thumb.jpg',
                size: 50,
                criticality: MigrationFileCriticality.nonCriticalCache,
              ),
            ],
          ),
        );

        expect(result.isAccepted, isTrue);
        expect(result.requiredBytes, 400);
        expect(result.optionalBytes, 50);
        expect(result.totalRequiredWithHeadroom, 750);
        expect(result.availableBytes, 2000);
      },
    );

    test('fails closed when storage is insufficient', () async {
      final preflight = MigrationStoragePreflight(
        availableBytesProvider: () async => 700,
        stagingOverheadBytes: 100,
        headroomBytes: 250,
      );

      final result = await preflight.evaluate(
        manifest: MigrationFileManifest(items: [_item(size: 400)]),
      );

      expect(result.isAccepted, isFalse);
      expect(
        result.reason,
        MigrationStoragePreflightReason.storageInsufficient,
      );
      expect(result.totalRequiredWithHeadroom, 750);
    });

    test('fails closed when available bytes cannot be read', () async {
      final preflight = MigrationStoragePreflight(
        availableBytesProvider: () async =>
            throw StateError('disk unavailable'),
      );

      final result = await preflight.evaluate(
        manifest: MigrationFileManifest(items: [_item(size: 1)]),
      );

      expect(result.isAccepted, isFalse);
      expect(result.reason, MigrationStoragePreflightReason.storageUnavailable);
    });
  });

  group('MigrationStoragePreflight.evaluateTransfer (P0-5)', () {
    MigrationTransferManifest transferManifest({required int totalBytes}) {
      return MigrationTransferManifest.legacyV1(
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        segmentSize: 1024,
        totalBytes: totalBytes,
        manifestSha256: 'manifest-hash',
        segments: const [],
      );
    }

    test(
      'v1 import requirement amplifies manifest total bytes by the named '
      'factor (segments dir + staged DB + final copies), plus headroom',
      () async {
        final preflight = MigrationStoragePreflight(
          availableBytesProvider: () async => 10000,
          stagingOverheadBytes: 100,
          headroomBytes: 200,
        );

        final result = await preflight.evaluateTransfer(
          manifest: transferManifest(totalBytes: 3000),
        );

        expect(
          MigrationStoragePreflight.v1ProtocolImportAmplificationFactor,
          greaterThanOrEqualTo(2),
          reason:
              'plaintext segment files, the staged DB, and final media copies '
              'all coexist on disk during a v1 import',
        );
        expect(
          result.requiredBytes,
          3000 * MigrationStoragePreflight.v1ProtocolImportAmplificationFactor,
        );
        expect(
          result.totalRequiredWithHeadroom,
          result.requiredBytes + 100 + 200,
        );
        expect(result.isAccepted, isTrue);
        expect(result.availableBytes, 10000);
      },
    );

    test('fails closed when amplified bytes exceed available space', () async {
      final preflight = MigrationStoragePreflight(
        availableBytesProvider: () async =>
            3000 *
                MigrationStoragePreflight.v1ProtocolImportAmplificationFactor +
            299,
        stagingOverheadBytes: 100,
        headroomBytes: 200,
      );

      final result = await preflight.evaluateTransfer(
        manifest: transferManifest(totalBytes: 3000),
      );

      expect(result.isAccepted, isFalse);
      expect(result.reason, MigrationStoragePreflightReason.storageInsufficient);
    });

    test('fails closed as storageUnavailable when the provider throws', () async {
      final preflight = MigrationStoragePreflight(
        availableBytesProvider: () async => throw StateError('no disk api'),
      );

      final result = await preflight.evaluateTransfer(
        manifest: transferManifest(totalBytes: 1),
      );

      expect(result.isAccepted, isFalse);
      expect(result.reason, MigrationStoragePreflightReason.storageUnavailable);
      expect(result.availableBytes, isNull);
    });

    test(
      'entry-streamed v2 manifests use the shrunken amplification factor',
      () async {
        // Protocol v2 stages each entry once and finalizes by rename, so the
        // v1 segments-plus-decoded-copies amplification no longer applies.
        final preflight = MigrationStoragePreflight(
          availableBytesProvider: () async => 100000,
        );

        final result = await preflight.evaluateTransfer(
          manifest: MigrationTransferManifest.v2(
            sessionId: 'session-1',
            bundleId: 'bundle-1',
            totalBytes: 3000,
            manifestSha256: 'manifest-hash',
            sessionKem: const MigrationTransferSessionKem(
              algorithm: 'ml-kem-768-hkdf-sha256-aes-256-gcm',
              direction: 'old_to_new',
            ),
            entries: const [
              MigrationTransferEntryDescriptor(
                entryId: 'database',
                kind: MigrationTransferEntryKind.database,
                sizeBytes: 3000,
                sha256: 'db-sha',
                chunkSize: 1024,
                chunkCount: 3,
              ),
            ],
          ),
        );

        expect(
          MigrationStoragePreflight.v2ProtocolImportAmplificationFactor,
          lessThan(MigrationStoragePreflight.v1ProtocolImportAmplificationFactor),
        );
        expect(
          result.requiredBytes,
          3000 * MigrationStoragePreflight.v2ProtocolImportAmplificationFactor,
        );
      },
    );
  });
}

MigrationFileManifestItem _item({
  String path = 'media/a.jpg',
  int size = 1,
  MigrationFileCriticality criticality = MigrationFileCriticality.critical,
}) {
  return MigrationFileManifestItem(
    kind: MigrationFileManifestItemKind.chatMedia,
    criticality: criticality,
    relativePath: path,
    sizeBytes: size,
    sha256: 'a' * 64,
    sourceTable: 'media_attachments',
    sourceId: 'blob',
  );
}
