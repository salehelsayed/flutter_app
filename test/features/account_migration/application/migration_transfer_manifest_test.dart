import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MigrationTransferManifest', () {
    test('serializes protocol v2 entry manifest metadata', () {
      final manifest = MigrationTransferManifest(
        protocolVersionValue: MigrationTransferManifest.protocolVersion,
        minimumImporterProtocolVersion:
            MigrationTransferManifest.protocolVersion,
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        segmentSize: 1024,
        totalBytes: 1536,
        manifestSha256: 'manifest-hash',
        sessionKem: const MigrationTransferSessionKem(
          algorithm: 'ml-kem-768-hkdf-sha256-aes-256-gcm',
          direction: 'old_to_new',
        ),
        entries: const [
          MigrationTransferEntryDescriptor(
            entryId: 'database',
            kind: MigrationTransferEntryKind.database,
            sizeBytes: 1024,
            sha256: 'db-sha',
            chunkSize: 1024,
            chunkCount: 1,
          ),
          MigrationTransferEntryDescriptor(
            entryId: 'file-1',
            kind: MigrationTransferEntryKind.file,
            relativePath: 'media/photo.jpg',
            sizeBytes: 512,
            sha256: 'file-sha',
            chunkSize: 1024,
            chunkCount: 1,
          ),
        ],
        segments: const [],
      );

      final json = manifest.toJson();

      expect(json['protocol_version'], MigrationTransferManifest.protocolVersion);
      expect(json['minimum_importer_protocol_version'], 2);
      expect(json['session_kem'], isA<Map>());
      expect(json['segments'], isEmpty);
      expect((json['entries'] as List).map((entry) => entry['entry_id']), [
        'database',
        'file-1',
      ]);
      expect(manifest.compatibility().isAccepted, isTrue);
    });

    test('fails closed across v1 and v2 importer mismatches', () {
      final v2Manifest = MigrationTransferManifest.v2(
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        totalBytes: 1,
        manifestSha256: 'manifest-hash',
        sessionKem: const MigrationTransferSessionKem(
          algorithm: 'ml-kem-768-hkdf-sha256-aes-256-gcm',
          direction: 'old_to_new',
        ),
        entries: const [
          MigrationTransferEntryDescriptor(
            entryId: 'database',
            kind: MigrationTransferEntryKind.database,
            sizeBytes: 1,
            sha256: 'db-sha',
            chunkSize: 1024,
            chunkCount: 1,
          ),
        ],
      );
      final v1Manifest = MigrationTransferManifest.legacyV1(
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        segmentSize: 1,
        totalBytes: 1,
        manifestSha256: 'manifest-hash',
        segments: [_descriptor(0, Uint8List.fromList([1]), offset: 0)],
      );

      expect(
        v2Manifest
            .compatibility(importerProtocolVersion: 1)
            .hasError(MigrationTransferManifestError.importerTooOld),
        isTrue,
      );
      expect(
        v1Manifest
            .compatibility(importerProtocolVersion: 2)
            .hasError(MigrationTransferManifestError.senderTooOld),
        isTrue,
      );
    });

    test('serializes transfer and segment metadata', () {
      final first = _descriptor(0, Uint8List.fromList([1, 2]));
      final second = _descriptor(1, Uint8List.fromList([3]));
      final manifest = MigrationTransferManifest.legacyV1(
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        segmentSize: 2,
        totalBytes: 3,
        manifestSha256: 'manifest-hash',
        segments: [second, first],
      );

      final json = manifest.toJson();

      expect(
        json['protocol_version'],
        MigrationTransferManifest.legacyProtocolVersion,
      );
      expect(json['session_id'], 'session-1');
      expect(json['bundle_id'], 'bundle-1');
      expect(json['segment_size'], 2);
      expect(json['total_bytes'], 3);
      expect(json['manifest_sha256'], 'manifest-hash');
      expect((json['segments'] as List).map((entry) => entry['index']), [0, 1]);
      expect(manifest.compatibility().isAccepted, isTrue);
    });

    test('rejects unsupported versions and malformed segment manifests', () {
      final first = _descriptor(0, Uint8List.fromList([1, 2]));
      final duplicateIndex = _descriptor(
        0,
        Uint8List.fromList([3]),
        offset: 2,
        nonce: 'other-nonce',
      );
      final duplicateNonce = _descriptor(
        1,
        Uint8List.fromList([3]),
        offset: 2,
        nonce: first.nonce,
      );

      final incompatible = MigrationTransferManifest.legacyV1(
        protocolVersionValue: 99,
        minimumImporterProtocolVersion: 99,
        sessionId: '',
        bundleId: '',
        segmentSize: 0,
        totalBytes: 3,
        manifestSha256: '',
        segments: [first, duplicateIndex, duplicateNonce],
      ).compatibility();

      expect(
        incompatible.hasError(
          MigrationTransferManifestError.unsupportedProtocolVersion,
        ),
        isTrue,
      );
      expect(
        incompatible.hasError(MigrationTransferManifestError.importerTooOld),
        isTrue,
      );
      expect(
        incompatible.hasError(MigrationTransferManifestError.emptySessionId),
        isTrue,
      );
      expect(
        incompatible.hasError(MigrationTransferManifestError.emptyBundleId),
        isTrue,
      );
      expect(
        incompatible.hasError(
          MigrationTransferManifestError.invalidSegmentSize,
        ),
        isTrue,
      );
      expect(
        incompatible.hasError(
          MigrationTransferManifestError.missingManifestHash,
        ),
        isTrue,
      );
      expect(
        incompatible.hasError(
          MigrationTransferManifestError.duplicateSegmentIndex,
        ),
        isTrue,
      );
      expect(
        incompatible.hasError(MigrationTransferManifestError.duplicateNonce),
        isTrue,
      );
    });

    test('reports missing indexes from verified progress', () {
      final manifest = MigrationTransferManifest.legacyV1(
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        segmentSize: 2,
        totalBytes: 4,
        manifestSha256: 'manifest-hash',
        segments: [
          _descriptor(0, Uint8List.fromList([1, 2])),
          _descriptor(1, Uint8List.fromList([3, 4]), offset: 2),
        ],
      );

      expect(manifest.missingIndexes({0}), [1]);
    });

    test('rejects non-contiguous segment indexes', () {
      final compatibility = MigrationTransferManifest.legacyV1(
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        segmentSize: 2,
        totalBytes: 3,
        manifestSha256: 'manifest-hash',
        segments: [
          _descriptor(1, Uint8List.fromList([1, 2]), offset: 0),
          _descriptor(2, Uint8List.fromList([3]), offset: 2),
        ],
      ).compatibility();

      expect(
        compatibility.hasError(
          MigrationTransferManifestError.segmentIndexMismatch,
        ),
        isTrue,
      );
    });
  });
}

MigrationTransferSegmentDescriptor _descriptor(
  int index,
  Uint8List plaintext, {
  int? offset,
  String? nonce,
}) {
  final ciphertext = 'ct:${base64Encode(plaintext)}';
  return MigrationTransferSegmentDescriptor(
    index: index,
    offset: offset ?? index * 2,
    plaintextLength: plaintext.length,
    plaintextSha256: migrationTransferSha256Hex(plaintext),
    ciphertextSha256: migrationTransferStringSha256Hex(ciphertext),
    nonce: nonce ?? 'nonce-$index',
  );
}
