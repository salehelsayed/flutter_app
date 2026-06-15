import 'dart:io';

import 'package:flutter_app/features/account_migration/application/migration_transfer_checkpoint_store.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileMigrationTransferCheckpointStore', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mig_checkpoint_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('persists verified segments across repository reload', () async {
      final path = '${tempDir.path}/checkpoints.json';
      final firstStore = FileMigrationTransferCheckpointStore(filePath: path);
      final segment = const MigrationVerifiedSegment(
        index: 0,
        plaintextLength: 4,
        plaintextSha256: 'plain-sha',
        ciphertextSha256: 'cipher-sha',
      );

      expect(
        await firstStore.markVerified(
          sessionId: 'session-1',
          bundleId: 'bundle-1',
          segment: segment,
        ),
        MigrationCheckpointWriteResult.recorded,
      );

      final reloadedStore = FileMigrationTransferCheckpointStore(
        filePath: path,
      );
      expect(
        await reloadedStore.loadVerified(
          sessionId: 'session-1',
          bundleId: 'bundle-1',
        ),
        hasLength(1),
      );
      expect(
        (await migrationMissingSegmentIndexes(
          checkpointStore: reloadedStore,
          manifest: MigrationTransferManifest.legacyV1(
            sessionId: 'session-1',
            bundleId: 'bundle-1',
            segmentSize: 4,
            totalBytes: 8,
            manifestSha256: 'manifest-hash',
            segments: [
              const MigrationTransferSegmentDescriptor(
                index: 0,
                offset: 0,
                plaintextLength: 4,
                plaintextSha256: 'plain-sha',
                ciphertextSha256: 'cipher-sha',
                nonce: 'nonce-0',
              ),
              const MigrationTransferSegmentDescriptor(
                index: 1,
                offset: 4,
                plaintextLength: 4,
                plaintextSha256: 'plain-sha-1',
                ciphertextSha256: 'cipher-sha-1',
                nonce: 'nonce-1',
              ),
            ],
          ),
        )),
        [1],
      );
    });

    test('rejects conflicting duplicate verified segment', () async {
      final store = InMemoryMigrationTransferCheckpointStore();
      const original = MigrationVerifiedSegment(
        index: 0,
        plaintextLength: 4,
        plaintextSha256: 'plain-sha',
        ciphertextSha256: 'cipher-sha',
      );
      const conflict = MigrationVerifiedSegment(
        index: 0,
        plaintextLength: 4,
        plaintextSha256: 'different',
        ciphertextSha256: 'cipher-sha',
      );

      await store.markVerified(
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        segment: original,
      );

      expect(
        await store.markVerified(
          sessionId: 'session-1',
          bundleId: 'bundle-1',
          segment: original,
        ),
        MigrationCheckpointWriteResult.alreadyVerified,
      );
      expect(
        await store.markVerified(
          sessionId: 'session-1',
          bundleId: 'bundle-1',
          segment: conflict,
        ),
        MigrationCheckpointWriteResult.conflict,
      );
    });
  });

  group('FileMigrationTransferLedgerStore', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mig_ledger_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('persists per-entry offsets and verified entries for resume', () async {
      final path = '${tempDir.path}/ledger.json';
      final store = FileMigrationTransferLedgerStore(filePath: path);
      const manifest = MigrationTransferManifest(
        protocolVersionValue: MigrationTransferManifest.protocolVersion,
        minimumImporterProtocolVersion:
            MigrationTransferManifest.protocolVersion,
        sessionId: 'session-1',
        bundleId: 'bundle-1',
        segmentSize: 1024,
        totalBytes: 6,
        manifestSha256: 'manifest-hash',
        sessionKem: MigrationTransferSessionKem(
          algorithm: 'ml-kem-768-hkdf-sha256-aes-256-gcm',
          direction: 'old_to_new',
        ),
        entries: [
          MigrationTransferEntryDescriptor(
            entryId: 'database',
            kind: MigrationTransferEntryKind.database,
            sizeBytes: 4,
            sha256: 'db-sha',
            chunkSize: 2,
            chunkCount: 2,
          ),
          MigrationTransferEntryDescriptor(
            entryId: 'file-1',
            kind: MigrationTransferEntryKind.file,
            relativePath: 'media/file.jpg',
            sizeBytes: 2,
            sha256: 'file-sha',
            chunkSize: 2,
            chunkCount: 1,
          ),
        ],
        segments: [],
      );

      await store.recordProgress(
        manifest: manifest,
        entryId: 'database',
        verifiedOffset: 2,
        incrementalSha256: 'partial-sha',
      );
      await store.markEntryVerified(
        manifest: manifest,
        entryId: 'database',
        sizeBytes: 4,
        sha256: 'db-sha',
      );

      final reloaded = FileMigrationTransferLedgerStore(filePath: path);
      final status = await reloaded.status(manifest);

      expect(status.nextEntryId, 'file-1');
      expect(status.nextOffset, 0);
      expect(status.verifiedEntryIds, ['database']);
      expect(status.entryOffsets['database'], 4);
      expect(await reloaded.missingEntryCount(manifest), 1);
    });
  });
}
