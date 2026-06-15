import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_segmented_transfer_service.dart';
import 'package:flutter_app/features/account_migration/application/migration_transfer_checkpoint_store.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MigrationSegmentedTransferService', () {
    test('exports and imports missing verified segments only', () async {
      final crypto = _DeterministicSegmentCrypto();
      final checkpointStore = InMemoryMigrationTransferCheckpointStore();
      final service = MigrationSegmentedTransferService(
        crypto: crypto,
        checkpointStore: checkpointStore,
      );
      final plaintextSegments = {
        0: Uint8List.fromList(utf8.encode('aaaa')),
        1: Uint8List.fromList(utf8.encode('bbbb')),
      };
      final manifest = _manifestFor(plaintextSegments, crypto);
      final sent = <MigrationEncryptedSegment>[];

      final exportResult = await service.exportSegments(
        manifest: manifest,
        plaintextSegments: plaintextSegments,
        recipientMlKemPublicKey: 'new-phone-mlkem-public',
        localPathAvailable: true,
        sendLocalSegment: (segment) async {
          sent.add(segment);
          return true;
        },
      );

      expect(exportResult.code, MigrationTransferResultCode.success);
      expect(sent, hasLength(2));

      final firstImport = await service.importSegments(
        manifest: manifest,
        encryptedSegments: [sent.first],
        ownMlKemSecretKey: 'new-phone-mlkem-secret',
      );
      expect(firstImport.code, MigrationTransferResultCode.missingSegment);
      expect(firstImport.missingSegmentIndexes, [1]);

      final secondImport = await service.importSegments(
        manifest: manifest,
        encryptedSegments: [sent.last],
        ownMlKemSecretKey: 'new-phone-mlkem-secret',
      );
      expect(secondImport.code, MigrationTransferResultCode.success);
      expect(
        await migrationMissingSegmentIndexes(
          checkpointStore: checkpointStore,
          manifest: manifest,
        ),
        isEmpty,
      );
    });

    test(
      'rejects relay fallback and missing local path before sending',
      () async {
        final crypto = _DeterministicSegmentCrypto();
        final service = MigrationSegmentedTransferService(
          crypto: crypto,
          checkpointStore: InMemoryMigrationTransferCheckpointStore(),
        );
        final plaintextSegments = {0: Uint8List.fromList(utf8.encode('aaaa'))};
        final manifest = _manifestFor(plaintextSegments, crypto);

        final relayResult = await service.exportSegments(
          manifest: manifest,
          plaintextSegments: plaintextSegments,
          recipientMlKemPublicKey: 'new-phone-mlkem-public',
          localPathAvailable: true,
          relayOrCloudFallbackRequested: true,
          sendLocalSegment: (_) async => throw StateError('must not send'),
        );
        expect(
          relayResult.code,
          MigrationTransferResultCode.relayOrCloudForbidden,
        );

        final noLocalResult = await service.exportSegments(
          manifest: manifest,
          plaintextSegments: plaintextSegments,
          recipientMlKemPublicKey: 'new-phone-mlkem-public',
          localPathAvailable: false,
          sendLocalSegment: (_) async => throw StateError('must not send'),
        );
        expect(noLocalResult.code, MigrationTransferResultCode.noLocalPath);
      },
    );

    test('rejects tampered wrong-session encrypted segment', () async {
      final crypto = _DeterministicSegmentCrypto();
      final service = MigrationSegmentedTransferService(
        crypto: crypto,
        checkpointStore: InMemoryMigrationTransferCheckpointStore(),
      );
      final plaintextSegments = {0: Uint8List.fromList(utf8.encode('aaaa'))};
      final manifest = _manifestFor(plaintextSegments, crypto);
      final aad = _aadFor(manifest, manifest.segments.single);
      final encrypted = await crypto.encryptSegment(
        plaintext: plaintextSegments[0]!,
        recipientMlKemPublicKey: 'new-phone-mlkem-public',
        associatedData: aad,
      );

      final result = await service.importSegments(
        manifest: manifest.copyWith(sessionId: 'other-session'),
        encryptedSegments: [encrypted],
        ownMlKemSecretKey: 'new-phone-mlkem-secret',
      );

      expect(result.code, MigrationTransferResultCode.cryptoRejected);
    });
  });
}

class _DeterministicSegmentCrypto implements MigrationSegmentCrypto {
  @override
  Future<MigrationEncryptedSegment> encryptSegment({
    required Uint8List plaintext,
    required String recipientMlKemPublicKey,
    required MigrationSegmentAssociatedData associatedData,
  }) async {
    final ciphertext =
        'ct:${associatedData.segmentIndex}:${base64Encode(plaintext)}:${associatedData.sha256Hex}';
    return MigrationEncryptedSegment(
      index: associatedData.segmentIndex,
      kem: 'kem-${associatedData.segmentIndex}',
      ciphertext: ciphertext,
      nonce: 'nonce-${associatedData.segmentIndex}',
      plaintextSha256: migrationTransferSha256Hex(plaintext),
      ciphertextSha256: migrationTransferStringSha256Hex(ciphertext),
      associatedDataSha256: associatedData.sha256Hex,
    );
  }

  @override
  Future<Uint8List> decryptSegment({
    required MigrationEncryptedSegment encryptedSegment,
    required String ownMlKemSecretKey,
    required MigrationSegmentAssociatedData associatedData,
  }) async {
    if (encryptedSegment.associatedDataSha256 != associatedData.sha256Hex) {
      throw const MigrationSegmentCryptoException('wrong aad');
    }
    final parts = encryptedSegment.ciphertext.split(':');
    if (parts.length != 4 || parts[3] != associatedData.sha256Hex) {
      throw const MigrationSegmentCryptoException('tampered ciphertext');
    }
    return Uint8List.fromList(base64Decode(parts[2]));
  }
}

MigrationTransferManifest _manifestFor(
  Map<int, Uint8List> plaintextSegments,
  _DeterministicSegmentCrypto crypto,
) {
  const sessionId = 'session-1';
  const bundleId = 'bundle-1';
  const manifestSha256 = 'manifest-hash';
  final descriptors = <MigrationTransferSegmentDescriptor>[];
  var offset = 0;
  for (final entry in plaintextSegments.entries) {
    final aad = MigrationSegmentAssociatedData(
      sessionId: sessionId,
      bundleId: bundleId,
      segmentIndex: entry.key,
      offset: offset,
      plaintextLength: entry.value.length,
      manifestSha256: manifestSha256,
    );
    final ciphertext =
        'ct:${entry.key}:${base64Encode(entry.value)}:${aad.sha256Hex}';
    descriptors.add(
      MigrationTransferSegmentDescriptor(
        index: entry.key,
        offset: offset,
        plaintextLength: entry.value.length,
        plaintextSha256: migrationTransferSha256Hex(entry.value),
        ciphertextSha256: migrationTransferStringSha256Hex(ciphertext),
        nonce: 'nonce-${entry.key}',
      ),
    );
    offset += entry.value.length;
  }
  return MigrationTransferManifest.legacyV1(
    sessionId: sessionId,
    bundleId: bundleId,
    segmentSize: 4,
    totalBytes: offset,
    manifestSha256: manifestSha256,
    segments: descriptors,
  );
}

MigrationSegmentAssociatedData _aadFor(
  MigrationTransferManifest manifest,
  MigrationTransferSegmentDescriptor descriptor,
) {
  return MigrationSegmentAssociatedData(
    sessionId: manifest.sessionId,
    bundleId: manifest.bundleId,
    segmentIndex: descriptor.index,
    offset: descriptor.offset,
    plaintextLength: descriptor.plaintextLength,
    manifestSha256: manifest.manifestSha256,
  );
}
