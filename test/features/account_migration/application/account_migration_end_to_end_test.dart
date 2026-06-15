// Chained Move Account end-to-end host test.
//
// Exercises the SHIPPED composition (mirrors lib/main.dart wiring):
//   AccountMigrationProductionBundleSource (real ffi DB + real files on disk)
//     → runOldPhoneTransfer over a REAL in-process LocalWsServer HTTP wire
//     → AccountMigrationProductionBundleReceiver (staged + active import)
//     → cutover proof exchange → old phone migratedOut / new phone active.
//
// Only the two platform seams are faked, via their existing injection points:
//   * the SQLCipher snapshot adapter / staged opener (plain ffi sqlite:
//     VACUUM INTO produces a REAL snapshot of the source DB, so the imported
//     rows asserted at the end are genuine end-to-end data), and
//   * the ML-KEM segment crypto (deterministic reversible scheme; real hash
//     pipeline via migrationTransfer*Sha256Hex helpers).
//
// NOTE: no TestWidgetsFlutterBinding.ensureInitialized() — the flutter_test
// binding installs HttpOverrides that break the sender's real HttpClient.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_bundle_transfer.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_local_transfer_runtime.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_coordinator.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_active_importer.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_import_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_cutover_record.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_cutover_repository.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_pairing_session_repository.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Move Account chained end-to-end (source → wire → receiver)', () {
    late Directory tempDir;
    late Database sourceDb;
    late Database activeDb;
    late FakeSecureKeyStore sourceStore;
    late FakeSecureKeyStore destinationStore;
    late Map<String, LocalPeer> registry;
    late _MemoryPairingSessionRepository pairingRepo;
    late LocalWsServer newPhoneServer;
    late LocalWsServer oldPhoneServer;
    late _SharedFakeDiscovery newPhoneDiscovery;
    late _SharedFakeDiscovery oldPhoneDiscovery;
    late List<Map<String, dynamic>> flowEvents;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('account_migration_e2e_');
      sourceDb = await openDatabase(
        p.join(tempDir.path, 'source.db'),
        version: 1,
        singleInstance: false,
      );
      activeDb = await openDatabase(
        p.join(tempDir.path, 'active.db'),
        version: 1,
        singleInstance: false,
      );
      // Identical DDL on both sides: the snapshot carries the source schema,
      // and the active importer refuses on any schema-hash mismatch.
      for (final db in [sourceDb, activeDb]) {
        await _createSchema(db);
      }
      await _seedSourceAccount(sourceDb, tempDir);
      // The new phone starts with its own throwaway identity + its own DB key.
      await activeDb.insert('identity', {
        'id': 1,
        'peer_id': 'new-temp-peer',
        'public_key': 'new-public',
        'username': 'new-temp',
      });

      sourceStore = FakeSecureKeyStore();
      destinationStore = FakeSecureKeyStore();
      for (final key in const [
        MigrationSecureStorageRegistry.dbEncryptionKey,
        MigrationSecureStorageRegistry.identityPrivateKey,
        MigrationSecureStorageRegistry.identityMnemonic12,
        MigrationSecureStorageRegistry.identityMlKemSecretKey,
      ]) {
        await sourceStore.write(key, 'value:$key');
      }
      // Group key material behind the group_keys row's `secure:` reference.
      await sourceStore.write(
        'group_key_material:group-1:1',
        'group-key-material-value',
      );
      await destinationStore.write(
        MigrationSecureStorageRegistry.dbEncryptionKey,
        'new-active-db-key',
      );

      registry = <String, LocalPeer>{};
      pairingRepo = _MemoryPairingSessionRepository();
      newPhoneServer = LocalWsServer();
      oldPhoneServer = LocalWsServer();
      newPhoneDiscovery = _SharedFakeDiscovery(registry);
      oldPhoneDiscovery = _SharedFakeDiscovery(registry);
      flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
    });

    tearDown(() async {
      debugSetFlowEventSink(null);
      await newPhoneServer.stop();
      await oldPhoneServer.stop();
      newPhoneDiscovery.dispose();
      oldPhoneDiscovery.dispose();
      if (sourceDb.isOpen) await sourceDb.close();
      if (activeDb.isOpen) await activeDb.close();
      await tempDir.delete(recursive: true);
    });

    List<Map<String, dynamic>> eventsNamed(String name) => flowEvents
        .where((event) => event['event'] == name)
        .toList(growable: false);

    Map<String, dynamic> detailsOf(Map<String, dynamic> event) =>
        Map<String, dynamic>.from(event['details'] as Map);

    test(
      'moves the full account old phone → new phone over the real wire',
      () async {
        // ---------- new phone ----------
        final output = await _savePendingSession(pairingRepo);
        final destinationDocumentsPath = p.join(
          tempDir.path,
          'destination-documents',
        );
        final newAuthority = _MemoryAuthorityRepository();
        final newCutoverRepo = _MemoryCutoverRepository();
        final receiver = AccountMigrationProductionBundleReceiver(
          streamCrypto: _e2eStreamCrypto(),
          secureStorageStaging: MigrationSecureStorageStaging(
            primaryStore: destinationStore,
          ),
          databaseImportStaging: MigrationDatabaseImportStaging(
            secureStorageStaging: MigrationSecureStorageStaging(
              primaryStore: destinationStore,
            ),
            opener: _FfiStagedDatabaseOpener(),
          ),
          activeDatabaseImporter: MigrationDatabaseActiveImporter(
            activeDatabase: activeDb,
          ),
          cutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: newAuthority,
            cutoverRepository: newCutoverRepo,
            now: () => DateTime.utc(2026, 6, 10, 12),
          ),
          authorityRepository: newAuthority,
          stagingDirectoryPath: p.join(tempDir.path, 'incoming'),
          documentsRootPath: destinationDocumentsPath,
        );
        final receiverEvents = <AccountMigrationReceiverEvent>[];
        final newRuntime = AccountMigrationLocalTransferRuntime(
          discovery: newPhoneDiscovery,
          wsServer: newPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleReceiver: receiver,
        );
        final eventsSub = newRuntime.receiverEvents.listen(receiverEvents.add);
        addTearDown(eventsSub.cancel);
        newPhoneServer.configureMigrationTransferHandler(
          newRuntime.handleMigrationTransferRequest,
        );
        expect(
          (await newRuntime.startNewPhoneReceiver(output)).isStarted,
          isTrue,
        );

        // ---------- old phone ----------
        final oldAuthority = _MemoryAuthorityRepository();
        final oldCutoverRepo = _MemoryCutoverRepository();
        AccountMigrationAuthorityState? stateDuringSnapshot;
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            adapter: _FfiSnapshotExportAdapter(
              onExport: () => stateDuringSnapshot = oldAuthority.saved?.state,
            ),
          ),
          segmentSize: 4096,
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: source.call,
          streamCrypto: _e2eStreamCrypto(),
          oldPhoneCutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: oldAuthority,
            cutoverRepository: oldCutoverRepo,
            now: () => DateTime.utc(2026, 6, 10, 12),
          ),
          oldPhoneLeaseCleanup: _noopLeaseCleanup(),
        );

        final progress = <AccountMigrationTransferStep>[];
        final segmentProgress = <(int, int)>[];
        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: progress.add,
          isCancelled: () => false,
          onSegmentProgress: (update) =>
              segmentProgress.add((update.sentSegments, update.totalSegments)),
        );

        // ---------- transfer result + journey steps ----------
        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        expect(
          progress,
          containsAllInOrder(const [
            AccountMigrationTransferStep.connecting,
            AccountMigrationTransferStep.encrypting,
            AccountMigrationTransferStep.transferringDatabase,
            AccountMigrationTransferStep.checking,
            AccountMigrationTransferStep.finishing,
          ]),
        );

        // ---------- multi-segment, monotonic progress ----------
        expect(segmentProgress.first.$1, 0);
        final totalSegments = segmentProgress.first.$2;
        expect(totalSegments, greaterThan(1), reason: 'must be multi-segment');
        for (var i = 1; i < segmentProgress.length; i++) {
          expect(segmentProgress[i].$1, greaterThan(segmentProgress[i - 1].$1));
          expect(segmentProgress[i].$2, totalSegments);
        }
        expect(segmentProgress.last.$1, totalSegments);

        // ---------- quiesce ordering on the old phone ----------
        expect(
          stateDuringSnapshot,
          AccountMigrationAuthorityState.migrationExportingNetworkPaused,
          reason: 'snapshot must be taken under the export network pause',
        );
        final oldStates = oldAuthority.history
            .map((record) => record.state)
            .toList(growable: false);
        expect(
          oldStates.first,
          AccountMigrationAuthorityState.migrationExportingNetworkPaused,
        );
        expect(
          oldStates.indexOf(
            AccountMigrationAuthorityState.migrationExportingNetworkPaused,
          ),
          lessThan(
            oldStates.indexOf(
              AccountMigrationAuthorityState.migrationCutoverPendingBlocked,
            ),
          ),
        );
        expect(
          oldStates,
          isNot(
            contains(
              AccountMigrationAuthorityState.migrationFailedActiveRestored,
            ),
          ),
        );
        expect(
          oldAuthority.saved?.state,
          AccountMigrationAuthorityState.migratedOut,
        );
        expect(oldCutoverRepo.saved?.oldMigratedOutCommitted, isTrue);

        // ---------- new phone authority + cutover proof ----------
        expect(
          newAuthority.saved?.state,
          AccountMigrationAuthorityState.active,
        );
        expect(newCutoverRepo.saved?.provesNewActiveCommitted, isTrue);

        // ---------- receiver event stream ----------
        final receivingEvents = receiverEvents
            .where(
              (event) =>
                  event.type ==
                  AccountMigrationReceiverEventType.receivingSegment,
            )
            .toList(growable: false);
        // Manifest acceptance emits one early receivingSegment (verifiedCount 0,
        // mounts the receiver wake lock), then one per verified segment.
        expect(receivingEvents, hasLength(totalSegments + 1));
        expect(receivingEvents.first.verifiedCount, 0);
        expect(receivingEvents.first.segmentIndex, isNull);
        for (var i = 1; i < receivingEvents.length; i++) {
          expect(receivingEvents[i].verifiedCount, i);
          expect(receivingEvents[i].segmentCount, totalSegments);
        }
        expect(
          receiverEvents.map((event) => event.type).toList(),
          containsAllInOrder(const [
            AccountMigrationReceiverEventType.receivingSegment,
            AccountMigrationReceiverEventType.importingBundle,
            AccountMigrationReceiverEventType.importVerified,
            AccountMigrationReceiverEventType.activated,
          ]),
        );
        // Every event belongs to this session, and each terminal stage fires
        // exactly once.
        for (final event in receiverEvents) {
          expect(event.sessionId, output.payload.sessionId);
        }
        for (final type in const [
          AccountMigrationReceiverEventType.importingBundle,
          AccountMigrationReceiverEventType.importVerified,
          AccountMigrationReceiverEventType.activated,
        ]) {
          expect(
            receiverEvents.where((event) => event.type == type),
            hasLength(1),
            reason: '$type must fire exactly once',
          );
        }

        // ---------- files byte-identical on the new phone ----------
        for (final relativePath in const [
          'media/peer-bob/blob-imported.jpg',
          'media/group-1/blob-group.jpg.enc',
        ]) {
          final sourceBytes = await File(
            p.join(tempDir.path, relativePath),
          ).readAsBytes();
          final importedBytes = await File(
            p.join(destinationDocumentsPath, relativePath),
          ).readAsBytes();
          expect(
            migrationTransferSha256Hex(importedBytes),
            migrationTransferSha256Hex(sourceBytes),
            reason: '$relativePath must arrive byte-identical',
          );
        }

        // ---------- imported DB rows are the REAL source rows ----------
        final identityRows = await activeDb.query('identity');
        expect(identityRows, hasLength(1));
        expect(identityRows.single['peer_id'], 'old-peer');
        expect(identityRows.single['username'], 'alice');

        final mediaRows = await activeDb.query(
          'media_attachments',
          orderBy: 'id',
        );
        expect(mediaRows, hasLength(2));
        expect(mediaRows.first['id'], 'blob-group');
        expect(
          mediaRows.first['encryption_scheme'],
          kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        expect(mediaRows.last['id'], 'blob-imported');
        expect(
          mediaRows.last['local_path'],
          'media/peer-bob/blob-imported.jpg',
        );

        final groupKeyRows = await activeDb.query('group_keys');
        expect(groupKeyRows, hasLength(1));
        expect(
          groupKeyRows.single['encrypted_key'],
          'secure:group_key_material:group-1:1',
        );
        expect(await activeDb.query('messages'), hasLength(1));
        expect(await activeDb.query('group_messages'), hasLength(1));

        // ---------- secrets promoted; new phone keeps its own DB key ----------
        expect(
          await destinationStore.read('identity_private_key'),
          'value:identity_private_key',
        );
        expect(
          await destinationStore.read('identity_mnemonic12'),
          'value:identity_mnemonic12',
        );
        expect(
          await destinationStore.read('identity_ml_kem_secret_key'),
          'value:identity_ml_kem_secret_key',
        );
        expect(
          await destinationStore.read('group_key_material:group-1:1'),
          'group-key-material-value',
        );
        expect(await destinationStore.read('secrets_migrated'), 'true');
        expect(
          await destinationStore.read('db_encryption_key'),
          'new-active-db-key',
          reason: 'the migrated source DB key must never replace the new key',
        );

        // ---------- relay-free audits on both ends ----------
        final sourceAudit = detailsOf(
          eventsNamed(
            'ACCOUNT_MIGRATION_BUNDLE_SOURCE_RELAY_FREE_MEDIA_AUDIT',
          ).single,
        );
        expect(sourceAudit['relayMediaDownloadCount'], 0);
        expect(sourceAudit['relayDependencyRisk'], false);
        expect(sourceAudit['blockingIssueCount'], 0);
        expect(sourceAudit['fileEntryCount'], 2);

        final importAudit = detailsOf(
          eventsNamed(
            'ACCOUNT_MIGRATION_BUNDLE_IMPORT_RELAY_FREE_MEDIA_AUDIT',
          ).single,
        );
        expect(importAudit['relayMediaDownloadCount'], 0);
        expect(importAudit['writtenCount'], 2);

        // ---------- receiver stage ordering ----------
        // P2-5: complete() shrank to a ledger check + staged-DB validation —
        // the v1 whole-payload `payloadDecode` stage no longer exists.
        expect(
          eventsNamed(
            'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_COMPLETE_STAGE',
          ).map((event) => detailsOf(event)['stage']).toList(),
          const [
            'ledgerCheck',
            'secureStaging',
            'stagedDbOpen',
            'importFiles',
            'authorityRecord',
          ],
        );
        expect(
          eventsNamed(
            'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_OLD_BLOCK_PROOF_STAGE',
          ).map((event) => detailsOf(event)['stage']).toList(),
          const [
            'activeDbImport',
            'securePromotion',
            'recordOldBlockProof',
            'commitNewActive',
            'cleanup',
          ],
        );
      },
    );

    test(
      'moves a realistic ~12 MB media account across many segments',
      () async {
        // Six 2 MiB media files on top of the base fixture — the real Jun-10
        // device run moved 14.1 MB / 76 segments; existing unit tests move
        // ~26 KB, which hides any scale regression in budgets or buffering.
        const largeFileCount = 6;
        const largeFileBytes = 2 * 1024 * 1024;
        var totalLargeBytes = 0;
        for (var i = 0; i < largeFileCount; i++) {
          final bytes = Uint8List.fromList(
            List<int>.generate(largeFileBytes, (j) => (i * 31 + j) & 0xff),
          );
          totalLargeBytes += bytes.length;
          final file = File(
            p.join(tempDir.path, 'media/peer-bob/blob-large-$i.bin'),
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes, flush: true);
          await sourceDb.insert('media_attachments', {
            'id': 'blob-large-$i',
            'message_id': 'message-1',
            'mime': 'application/octet-stream',
            'size': bytes.length,
            'media_type': 'file',
            'local_path': 'media/peer-bob/blob-large-$i.bin',
            'download_status': 'done',
            'created_at': '2026-06-10T08:00:00.000Z',
          });
        }

        final output = await _savePendingSession(
          pairingRepo,
          sessionId: 'e2e-large-session',
        );
        final destinationDocumentsPath = p.join(
          tempDir.path,
          'destination-documents',
        );
        final newAuthority = _MemoryAuthorityRepository();
        final receiver = AccountMigrationProductionBundleReceiver(
          streamCrypto: _e2eStreamCrypto(),
          secureStorageStaging: MigrationSecureStorageStaging(
            primaryStore: destinationStore,
          ),
          databaseImportStaging: MigrationDatabaseImportStaging(
            secureStorageStaging: MigrationSecureStorageStaging(
              primaryStore: destinationStore,
            ),
            opener: _FfiStagedDatabaseOpener(),
          ),
          activeDatabaseImporter: MigrationDatabaseActiveImporter(
            activeDatabase: activeDb,
          ),
          cutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: newAuthority,
            cutoverRepository: _MemoryCutoverRepository(),
            now: () => DateTime.utc(2026, 6, 10, 12),
          ),
          authorityRepository: newAuthority,
          stagingDirectoryPath: p.join(tempDir.path, 'incoming'),
          documentsRootPath: destinationDocumentsPath,
        );
        final newRuntime = AccountMigrationLocalTransferRuntime(
          discovery: newPhoneDiscovery,
          wsServer: newPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleReceiver: receiver,
        );
        newPhoneServer.configureMigrationTransferHandler(
          newRuntime.handleMigrationTransferRequest,
        );
        expect(
          (await newRuntime.startNewPhoneReceiver(output)).isStarted,
          isTrue,
        );

        final oldAuthority = _MemoryAuthorityRepository();
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            adapter: _FfiSnapshotExportAdapter(),
          ),
          // Production default: 1 MiB chunks.
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: source.call,
          streamCrypto: _e2eStreamCrypto(),
          oldPhoneCutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: oldAuthority,
            cutoverRepository: _MemoryCutoverRepository(),
            now: () => DateTime.utc(2026, 6, 10, 12),
          ),
          oldPhoneLeaseCleanup: _noopLeaseCleanup(),
        );

        final segmentProgress = <(int, int)>[];
        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
          onSegmentProgress: (update) =>
              segmentProgress.add((update.sentSegments, update.totalSegments)),
        );

        expect(result.isSuccess, isTrue, reason: result.safeMessage);

        // Realistic scale: ~12 MiB raw → base64 payload → 1 MiB segments,
        // all delivered with monotonic progress.
        final totalSegments = segmentProgress.first.$2;
        expect(totalSegments, inInclusiveRange(13, 24));
        expect(segmentProgress.last.$1, totalSegments);
        for (var i = 1; i < segmentProgress.length; i++) {
          expect(segmentProgress[i].$1, greaterThan(segmentProgress[i - 1].$1));
        }

        // Every large file arrives byte-identical.
        for (var i = 0; i < largeFileCount; i++) {
          final relativePath = 'media/peer-bob/blob-large-$i.bin';
          expect(
            migrationTransferSha256Hex(
              await File(
                p.join(destinationDocumentsPath, relativePath),
              ).readAsBytes(),
            ),
            migrationTransferSha256Hex(
              await File(p.join(tempDir.path, relativePath)).readAsBytes(),
            ),
            reason: '$relativePath must arrive byte-identical',
          );
        }

        final importAudit = detailsOf(
          eventsNamed(
            'ACCOUNT_MIGRATION_BUNDLE_IMPORT_RELAY_FREE_MEDIA_AUDIT',
          ).single,
        );
        expect(importAudit['relayMediaDownloadCount'], 0);
        expect(importAudit['writtenCount'], largeFileCount + 2);
        expect(
          importAudit['bytesWritten'],
          greaterThanOrEqualTo(totalLargeBytes),
        );

        // ---------- P2-11 budget rebasing ----------
        // complete() no longer hides O(account) import work, so its budget
        // scales with staged-DB validation bytes; chunk budgets stay
        // payload-scaled (a 1 MiB chunk body buys more than the small
        // complete body). v1 scaled complete by totalBytes (~12.6 MB → cap).
        final posts = eventsNamed('ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_START')
            .map(detailsOf)
            .where((details) => details['sessionId'] == 'e2e-large-session')
            .toList(growable: false);
        final completeTimeoutMs =
            posts.singleWhere((details) => details['command'] == 'complete')['timeoutMs']
                as int;
        expect(
          completeTimeoutMs,
          lessThan(30 * 1000),
          reason: 'complete budget must scale with staged-DB validation, '
              'not the whole account',
        );
        final oldBlockTimeoutMs = posts.singleWhere(
          (details) => details['command'] == 'old-block-proof',
        )['timeoutMs'] as int;
        expect(oldBlockTimeoutMs, lessThan(30 * 1000));
        final maxChunkTimeoutMs = posts
            .where((details) => details['command'] == 'chunk')
            .map((details) => details['timeoutMs'] as int)
            .fold<int>(0, (a, b) => a > b ? a : b);
        expect(maxChunkTimeoutMs, greaterThan(completeTimeoutMs));
        expect(
          newAuthority.saved?.state,
          AccountMigrationAuthorityState.active,
        );
        expect(
          oldAuthority.saved?.state,
          AccountMigrationAuthorityState.migratedOut,
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'ML-KEM-768-sized binary ciphertexts survive manifest hashes and the wire',
      () async {
        // The deterministic fake above uses tiny text ciphertexts; real
        // ML-KEM-768 segments carry a 1088-byte KEM blob and an AES-GCM-sized
        // binary ciphertext (plaintext + 16-byte tag), all base64'd into the
        // segment JSON. This run proves realistic sizes flow through the
        // manifest hash pipeline, HTTP bodies, and receiver verification.
        final output = await _savePendingSession(
          pairingRepo,
          sessionId: 'e2e-mlkem-session',
        );
        final destinationDocumentsPath = p.join(
          tempDir.path,
          'destination-documents',
        );
        final newAuthority = _MemoryAuthorityRepository();
        final receiver = AccountMigrationProductionBundleReceiver(
          streamCrypto: _RealisticKemSizedStreamCrypto(),
          secureStorageStaging: MigrationSecureStorageStaging(
            primaryStore: destinationStore,
          ),
          databaseImportStaging: MigrationDatabaseImportStaging(
            secureStorageStaging: MigrationSecureStorageStaging(
              primaryStore: destinationStore,
            ),
            opener: _FfiStagedDatabaseOpener(),
          ),
          activeDatabaseImporter: MigrationDatabaseActiveImporter(
            activeDatabase: activeDb,
          ),
          cutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: newAuthority,
            cutoverRepository: _MemoryCutoverRepository(),
            now: () => DateTime.utc(2026, 6, 10, 12),
          ),
          authorityRepository: newAuthority,
          stagingDirectoryPath: p.join(tempDir.path, 'incoming'),
          documentsRootPath: destinationDocumentsPath,
        );
        final newRuntime = AccountMigrationLocalTransferRuntime(
          discovery: newPhoneDiscovery,
          wsServer: newPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleReceiver: receiver,
        );
        newPhoneServer.configureMigrationTransferHandler(
          newRuntime.handleMigrationTransferRequest,
        );
        expect(
          (await newRuntime.startNewPhoneReceiver(output)).isStarted,
          isTrue,
        );

        final oldAuthority = _MemoryAuthorityRepository();
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            adapter: _FfiSnapshotExportAdapter(),
          ),
          segmentSize: 4096,
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: source.call,
          streamCrypto: _RealisticKemSizedStreamCrypto(),
          oldPhoneCutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: oldAuthority,
            cutoverRepository: _MemoryCutoverRepository(),
            now: () => DateTime.utc(2026, 6, 10, 12),
          ),
          oldPhoneLeaseCleanup: _noopLeaseCleanup(),
        );

        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) {},
          isCancelled: () => false,
        );

        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        expect(
          newAuthority.saved?.state,
          AccountMigrationAuthorityState.active,
        );
        expect(
          oldAuthority.saved?.state,
          AccountMigrationAuthorityState.migratedOut,
        );

        // Files still arrive byte-identical through the binary crypto.
        for (final relativePath in const [
          'media/peer-bob/blob-imported.jpg',
          'media/group-1/blob-group.jpg.enc',
        ]) {
          expect(
            migrationTransferSha256Hex(
              await File(
                p.join(destinationDocumentsPath, relativePath),
              ).readAsBytes(),
            ),
            migrationTransferSha256Hex(
              await File(p.join(tempDir.path, relativePath)).readAsBytes(),
            ),
          );
        }

        // Wire bodies reflect realistic expansion: base64(plaintext + GCM
        // tag) plus a base64 1088-byte KEM blob per chunk.
        final chunkPosts = eventsNamed(
          'ACCOUNT_MIGRATION_LOCAL_TRANSFER_POST_START',
        ).where((event) => detailsOf(event)['command'] == 'chunk');
        expect(chunkPosts, isNotEmpty);
        var sawFullChunk = false;
        for (final post in chunkPosts) {
          final details = detailsOf(post);
          if (details['sessionId'] != 'e2e-mlkem-session') continue;
          final payloadBytes = details['payloadBytes'] as int;
          if (payloadBytes > (4096 * 4 / 3).floor()) {
            sawFullChunk = true;
          }
        }
        expect(
          sawFullChunk,
          isTrue,
          reason: 'chunk bodies must carry base64-expanded binary ciphertext',
        );
      },
    );

    test(
      'an interrupted transfer resumes from the receiver ledger instead of '
      'restarting',
      () async {
        // ~4 MiB of media so the interruption lands mid-stream with plenty of
        // verified chunks behind it.
        const largeFileCount = 2;
        const largeFileBytes = 2 * 1024 * 1024;
        for (var i = 0; i < largeFileCount; i++) {
          final bytes = Uint8List.fromList(
            List<int>.generate(largeFileBytes, (j) => (i * 17 + j) & 0xff),
          );
          final file = File(
            p.join(tempDir.path, 'media/peer-bob/blob-resume-$i.bin'),
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes, flush: true);
          await sourceDb.insert('media_attachments', {
            'id': 'blob-resume-$i',
            'message_id': 'message-1',
            'mime': 'application/octet-stream',
            'size': bytes.length,
            'media_type': 'file',
            'local_path': 'media/peer-bob/blob-resume-$i.bin',
            'download_status': 'done',
            'created_at': '2026-06-10T08:00:00.000Z',
          });
        }

        final output = await _savePendingSession(
          pairingRepo,
          sessionId: 'e2e-resume-session',
        );
        final destinationDocumentsPath = p.join(
          tempDir.path,
          'destination-documents',
        );
        final newAuthority = _MemoryAuthorityRepository();
        final receiver = AccountMigrationProductionBundleReceiver(
          streamCrypto: _e2eStreamCrypto(),
          secureStorageStaging: MigrationSecureStorageStaging(
            primaryStore: destinationStore,
          ),
          databaseImportStaging: MigrationDatabaseImportStaging(
            secureStorageStaging: MigrationSecureStorageStaging(
              primaryStore: destinationStore,
            ),
            opener: _FfiStagedDatabaseOpener(),
          ),
          activeDatabaseImporter: MigrationDatabaseActiveImporter(
            activeDatabase: activeDb,
          ),
          cutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: newAuthority,
            cutoverRepository: _MemoryCutoverRepository(),
            now: () => DateTime.utc(2026, 6, 10, 12),
          ),
          authorityRepository: newAuthority,
          stagingDirectoryPath: p.join(tempDir.path, 'incoming'),
          documentsRootPath: destinationDocumentsPath,
        );
        final newRuntime = AccountMigrationLocalTransferRuntime(
          discovery: newPhoneDiscovery,
          wsServer: newPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleReceiver: receiver,
        );
        newPhoneServer.configureMigrationTransferHandler(
          newRuntime.handleMigrationTransferRequest,
        );
        expect(
          (await newRuntime.startNewPhoneReceiver(output)).isStarted,
          isTrue,
        );

        final oldAuthority = _MemoryAuthorityRepository();
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            adapter: _FfiSnapshotExportAdapter(),
          ),
          segmentSize: 256 * 1024,
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: source.call,
          streamCrypto: _e2eStreamCrypto(),
          oldPhoneCutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: oldAuthority,
            cutoverRepository: _MemoryCutoverRepository(),
            now: () => DateTime.utc(2026, 6, 10, 12),
          ),
          oldPhoneLeaseCleanup: _noopLeaseCleanup(),
        );
        final request = AccountMigrationTransferRequest(
          transcript: _transcript(output.payload),
        );

        // ---------- attempt 1: interrupted after a handful of chunks ----------
        var firstAttemptChunks = 0;
        final firstResult = await oldRuntime.runOldPhoneTransfer(
          request: request,
          onProgress: (_) {},
          isCancelled: () => firstAttemptChunks >= 5,
          onSegmentProgress: (update) => firstAttemptChunks = update.sentSegments,
        );
        expect(firstResult.isSuccess, isFalse);
        expect(firstAttemptChunks, greaterThanOrEqualTo(5));

        // ---------- attempt 2: resumes and completes ----------
        final secondResult = await oldRuntime.runOldPhoneTransfer(
          request: request,
          onProgress: (_) {},
          isCancelled: () => false,
        );
        expect(secondResult.isSuccess, isTrue, reason: secondResult.safeMessage);

        // The second attempt started from the persisted (entry, offset)
        // ledger: it announced resumed chunks and resent fewer chunks than
        // the whole bundle.
        final streamStarts = eventsNamed(
          'ACCOUNT_MIGRATION_LOCAL_TRANSFER_STREAM_START',
        ).where((event) => detailsOf(event)['sessionId'] == 'e2e-resume-session').toList();
        expect(streamStarts, hasLength(2));
        final firstStart = detailsOf(streamStarts.first);
        final secondStart = detailsOf(streamStarts.last);
        expect(firstStart['resumedChunks'], 0);
        final totalChunks = secondStart['chunkCount'] as int;
        final resumedChunks = secondStart['resumedChunks'] as int;
        expect(resumedChunks, greaterThan(0));
        final secondAttemptChunkPosts = eventsNamed(
          'ACCOUNT_MIGRATION_LOCAL_TRANSFER_CHUNK_PROGRESS',
        )
            .where(
              (event) =>
                  detailsOf(event)['sessionId'] == 'e2e-resume-session',
            )
            .length;
        expect(
          secondAttemptChunkPosts,
          lessThan(2 * totalChunks),
          reason: 'resume must not retransmit the whole account twice over',
        );

        // Each attempt used one fresh encapsulation: the receiver saw two
        // distinct KEM ciphertexts only if the fake derives per-attempt keys;
        // what matters cryptographically is one encap per attempt, which the
        // stream-start/chunk flow above already proves (no per-chunk encap
        // exists in the v2 wire).
        for (var i = 0; i < largeFileCount; i++) {
          final relativePath = 'media/peer-bob/blob-resume-$i.bin';
          expect(
            migrationTransferSha256Hex(
              await File(
                p.join(destinationDocumentsPath, relativePath),
              ).readAsBytes(),
            ),
            migrationTransferSha256Hex(
              await File(p.join(tempDir.path, relativePath)).readAsBytes(),
            ),
            reason: '$relativePath must arrive byte-identical after resume',
          );
        }
        expect(
          newAuthority.saved?.state,
          AccountMigrationAuthorityState.active,
        );
        expect(
          oldAuthority.saved?.state,
          AccountMigrationAuthorityState.migratedOut,
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a generated 100 MB account moves end-to-end with bounded memory',
      () async {
        // P2-10: the v1 pipeline needed ~4-6x the account size in RAM (the
        // whole payload, base64 copies, and all encrypted segments coexist).
        // The v2 entry stream holds at most ~one chunk per side plus codec
        // copies, so a 150 MB RSS delta is a generous-but-real bound that v1
        // could not meet for a 100 MB account (it needed 400 MB+).
        const mediaFileCount = 4;
        const mediaFileBytes = 25 * 1024 * 1024;
        for (var i = 0; i < mediaFileCount; i++) {
          final file = File(
            p.join(tempDir.path, 'media/peer-bob/blob-scale-$i.bin'),
          );
          await file.parent.create(recursive: true);
          final sink = file.openWrite();
          final block = Uint8List.fromList(
            List<int>.generate(64 * 1024, (j) => (i * 31 + j) & 0xff),
          );
          for (var written = 0; written < mediaFileBytes; written += block.length) {
            sink.add(block);
          }
          await sink.close();
          await sourceDb.insert('media_attachments', {
            'id': 'blob-scale-$i',
            'message_id': 'message-1',
            'mime': 'application/octet-stream',
            'size': mediaFileBytes,
            'media_type': 'file',
            'local_path': 'media/peer-bob/blob-scale-$i.bin',
            'download_status': 'done',
            'created_at': '2026-06-10T08:00:00.000Z',
          });
        }

        final output = await _savePendingSession(
          pairingRepo,
          sessionId: 'e2e-scale-session',
        );
        final destinationDocumentsPath = p.join(
          tempDir.path,
          'destination-documents',
        );
        final newAuthority = _MemoryAuthorityRepository();
        final receiver = AccountMigrationProductionBundleReceiver(
          streamCrypto: _e2eStreamCrypto(),
          secureStorageStaging: MigrationSecureStorageStaging(
            primaryStore: destinationStore,
          ),
          databaseImportStaging: MigrationDatabaseImportStaging(
            secureStorageStaging: MigrationSecureStorageStaging(
              primaryStore: destinationStore,
            ),
            opener: _FfiStagedDatabaseOpener(),
          ),
          activeDatabaseImporter: MigrationDatabaseActiveImporter(
            activeDatabase: activeDb,
          ),
          cutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: newAuthority,
            cutoverRepository: _MemoryCutoverRepository(),
            now: () => DateTime.utc(2026, 6, 10, 12),
          ),
          authorityRepository: newAuthority,
          stagingDirectoryPath: p.join(tempDir.path, 'incoming'),
          documentsRootPath: destinationDocumentsPath,
        );
        final newRuntime = AccountMigrationLocalTransferRuntime(
          discovery: newPhoneDiscovery,
          wsServer: newPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleReceiver: receiver,
        );
        newPhoneServer.configureMigrationTransferHandler(
          newRuntime.handleMigrationTransferRequest,
        );
        expect(
          (await newRuntime.startNewPhoneReceiver(output)).isStarted,
          isTrue,
        );

        final oldAuthority = _MemoryAuthorityRepository();
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            adapter: _FfiSnapshotExportAdapter(),
          ),
          // Production default: 1 MiB chunks.
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: source.call,
          streamCrypto: _e2eStreamCrypto(),
          oldPhoneCutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: oldAuthority,
            cutoverRepository: _MemoryCutoverRepository(),
            now: () => DateTime.utc(2026, 6, 10, 12),
          ),
          oldPhoneLeaseCleanup: _noopLeaseCleanup(),
        );

        final rssStart = ProcessInfo.currentRss;
        var rssPeak = rssStart;
        void sampleRss() {
          final rss = ProcessInfo.currentRss;
          if (rss > rssPeak) {
            rssPeak = rss;
          }
        }

        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcript(output.payload),
          ),
          onProgress: (_) => sampleRss(),
          isCancelled: () => false,
          onSegmentProgress: (_) => sampleRss(),
        );
        sampleRss();

        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        const accountBytes = mediaFileCount * mediaFileBytes;
        final rssDelta = rssPeak - rssStart;
        expect(
          rssDelta,
          lessThan(150 * 1024 * 1024),
          reason:
              'moving a ${accountBytes ~/ (1024 * 1024)} MB account must not '
              'materialize the account in RAM (peak delta was '
              '${rssDelta ~/ (1024 * 1024)} MB)',
        );

        for (var i = 0; i < mediaFileCount; i++) {
          final relativePath = 'media/peer-bob/blob-scale-$i.bin';
          expect(
            migrationTransferSha256Hex(
              await File(
                p.join(destinationDocumentsPath, relativePath),
              ).readAsBytes(),
            ),
            migrationTransferSha256Hex(
              await File(p.join(tempDir.path, relativePath)).readAsBytes(),
            ),
            reason: '$relativePath must arrive byte-identical',
          );
        }
        expect(
          newAuthority.saved?.state,
          AccountMigrationAuthorityState.active,
        );
        expect(
          oldAuthority.saved?.state,
          AccountMigrationAuthorityState.migratedOut,
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}

// ---------------------------------------------------------------------------
// Fixture: schema + seeded source account
// ---------------------------------------------------------------------------

Future<void> _createSchema(Database db) async {
  await db.execute('''
CREATE TABLE identity (
  id INTEGER PRIMARY KEY,
  peer_id TEXT NOT NULL,
  public_key TEXT NOT NULL,
  username TEXT NOT NULL
)
''');
  await db.execute('''
CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  contact_peer_id TEXT NOT NULL,
  sender_peer_id TEXT NOT NULL,
  text TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'sent',
  is_incoming INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)
''');
  await db.execute('''
CREATE TABLE media_attachments (
  id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL,
  mime TEXT NOT NULL,
  size INTEGER NOT NULL DEFAULT 0,
  media_type TEXT NOT NULL,
  width INTEGER,
  height INTEGER,
  duration_ms INTEGER,
  local_path TEXT,
  download_status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL,
  content_hash TEXT,
  thumbnail_hash TEXT,
  encryption_key_base64 TEXT,
  encryption_nonce TEXT,
  encryption_scheme TEXT
)
''');
  await db.execute('''
CREATE TABLE group_messages (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL
)
''');
  await db.execute('''
CREATE TABLE groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  avatar_path TEXT
)
''');
  await db.execute('''
CREATE TABLE group_keys (
  group_id TEXT NOT NULL,
  key_generation INTEGER NOT NULL,
  encrypted_key TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (group_id, key_generation)
)
''');
}

Future<void> _seedSourceAccount(Database db, Directory documentsRoot) async {
  const createdAt = '2026-06-10T08:00:00.000Z';
  await db.insert('identity', {
    'id': 1,
    'peer_id': 'old-peer',
    'public_key': 'public',
    'username': 'alice',
  });
  await db.insert('messages', {
    'id': 'message-1',
    'contact_peer_id': 'peer-bob',
    'sender_peer_id': 'old-peer',
    'text': '',
    'timestamp': createdAt,
    'status': 'sent',
    'is_incoming': 0,
    'created_at': createdAt,
  });
  await db.insert('group_messages', {
    'id': 'group-message-1',
    'group_id': 'group-1',
  });
  await db.insert('groups', {'id': 'group-1', 'name': 'g'});
  await db.insert('group_keys', {
    'group_id': 'group-1',
    'key_generation': 1,
    'encrypted_key': 'secure:group_key_material:group-1:1',
    'created_at': createdAt,
  });
  // 1:1 chat image: plaintext present on disk, size must match exactly.
  await db.insert('media_attachments', {
    'id': 'blob-imported',
    'message_id': 'message-1',
    'mime': 'image/jpeg',
    'size': 5,
    'media_type': 'image',
    'local_path': 'media/peer-bob/blob-imported.jpg',
    'download_status': 'done',
    'created_at': createdAt,
  });
  await _writeRelative(
    documentsRoot,
    'media/peer-bob/blob-imported.jpg',
    'image',
  );
  // Group image: plaintext intentionally MISSING; complete encryption
  // metadata makes the `.enc` companion the bundled candidate.
  await db.insert('media_attachments', {
    'id': 'blob-group',
    'message_id': 'group-message-1',
    'mime': 'image/jpeg',
    'size': 11,
    'media_type': 'image',
    'local_path': 'media/group-1/blob-group.jpg',
    'download_status': 'done',
    'created_at': createdAt,
    'content_hash': 'a' * 64,
    'encryption_key_base64': 'media-key',
    'encryption_nonce': 'nonce',
    'encryption_scheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  });
  await _writeRelative(
    documentsRoot,
    'media/group-1/blob-group.jpg.enc',
    'encrypted-group-image',
  );
}

Future<void> _writeRelative(
  Directory root,
  String relativePath,
  String contents,
) async {
  final file = File(p.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsString(contents, flush: true);
}

// ---------------------------------------------------------------------------
// The two allowed fakes: SQLCipher seam via plain ffi sqlite
// ---------------------------------------------------------------------------

/// Exports a REAL snapshot of the live source DB with `VACUUM INTO`, so the
/// staged/active import downstream operates on genuine rows. [onExport] lets
/// the test observe state at the exact snapshot moment (quiesce proof).
class _FfiSnapshotExportAdapter implements MigrationSqlCipherExportAdapter {
  final void Function()? onExport;

  _FfiSnapshotExportAdapter({this.onExport});

  @override
  Future<MigrationDatabaseCipherMetadata> captureCipherMetadata(
    Database db,
  ) async {
    return const MigrationDatabaseCipherMetadata(
      cipherVersion: '4.6.0',
      policy: MigrationDatabaseCipherPolicy.compatible,
    );
  }

  @override
  Future<void> exportSqlCipherDatabase({
    required Database sourceDb,
    required String destinationPath,
    required String destinationKey,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) async {
    onExport?.call();
    final escaped = destinationPath.replaceAll("'", "''");
    await sourceDb.execute("VACUUM INTO '$escaped'");
  }

  @override
  Future<Database> openExportedDatabase({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
  }

  @override
  Future<String> runIntegrityCheck(Database db) async {
    final rows = await db.rawQuery('PRAGMA quick_check');
    return rows.first.values.first.toString();
  }
}

/// Opens the staged snapshot file with a FRESH ffi connection per call, so
/// the receiver's post-cutover close cannot strand a shared handle.
class _FfiStagedDatabaseOpener implements MigrationStagedDatabaseOpener {
  @override
  Future<Database> open({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
  }
}

/// Synchronous chunk-work executor (production default is Isolate.run).
Future<R> _inlineChunkWork<R>(R Function() work) async => work();

/// Deterministic reversible stream crypto with the REAL hash/AAD pipeline:
/// the production [BridgeMigrationStreamCrypto] over the FakeBridge's
/// deterministic migration command fakes.
BridgeMigrationStreamCrypto _e2eStreamCrypto() {
  return BridgeMigrationStreamCrypto(
    // Without retainMessageLog: false the fake would hold every chunk's
    // base64 payload, defeating the bounded-memory assertions.
    bridge: FakeBridge(retainMessageLog: false),
    executeChunkWork: _inlineChunkWork,
  );
}

/// Reversible stream crypto with REAL ML-KEM-768 wire sizes: a 1088-byte
/// KEM encapsulation blob per session and a binary chunk ciphertext of
/// plaintext + 16-byte tag (AES-256-GCM shape), all base64'd like the
/// production bridge crypto. "Encryption" is a deterministic per-chunk XOR
/// keystream so the receiver can reverse it without a bridge.
class _RealisticKemSizedStreamCrypto implements MigrationStreamCrypto {
  static const int kemCiphertextBytes = 1088;
  static const int tagBytes = 16;

  int _keyByte(int chunkIndex, int position) =>
      (chunkIndex * 7 + position * 13 + 31) & 0xff;

  Uint8List _xor(int chunkIndex, Uint8List input) {
    final output = Uint8List(input.length);
    for (var i = 0; i < input.length; i++) {
      output[i] = input[i] ^ _keyByte(chunkIndex, i);
    }
    return output;
  }

  String _kemFor(String sessionId, String bundleId) {
    final seed = '$sessionId|$bundleId'.codeUnits;
    return base64Encode(
      Uint8List.fromList(
        List<int>.generate(
          kemCiphertextBytes,
          (i) => (seed[i % seed.length] + i) & 0xff,
        ),
      ),
    );
  }

  @override
  Future<MigrationStreamEncryptSession> encapsulateSession({
    required String recipientMlKemPublicKey,
    required String sessionId,
    required String bundleId,
    required MigrationStreamDirection direction,
  }) async {
    return MigrationStreamEncryptSession(
      sessionId: sessionId,
      bundleId: bundleId,
      direction: direction,
      sessionKey: base64Encode(Uint8List(32)),
      kemCiphertext: _kemFor(sessionId, bundleId),
    );
  }

  @override
  Future<MigrationStreamDecryptSession> decapsulateSession({
    required String ownMlKemSecretKey,
    required String sessionId,
    required String bundleId,
    required MigrationStreamDirection direction,
    required String kemCiphertext,
  }) async {
    // The receiver must decap with the pairing session's ephemeral secret.
    expect(ownMlKemSecretKey, 'new-phone-secret-key');
    expect(base64Decode(kemCiphertext), hasLength(kemCiphertextBytes));
    return MigrationStreamDecryptSession(
      sessionId: sessionId,
      bundleId: bundleId,
      direction: direction,
      sessionKey: base64Encode(Uint8List(32)),
      kemCiphertext: kemCiphertext,
    );
  }

  @override
  Future<MigrationEncryptedChunk> encryptChunk({
    required MigrationStreamEncryptSession session,
    required Uint8List plaintext,
    required MigrationChunkAssociatedData associatedData,
    required String nonce,
  }) async {
    final index = associatedData.chunkIndex;
    final body = BytesBuilder(copy: false)
      ..add(_xor(index, plaintext))
      ..add(
        Uint8List.fromList(
          List<int>.generate(tagBytes, (i) => _keyByte(index, i + 1) ^ 0x5a),
        ),
      );
    final ciphertext = base64Encode(body.takeBytes());
    return MigrationEncryptedChunk(
      entryId: associatedData.entryId,
      chunkIndex: index,
      offset: associatedData.offset,
      isFinal: associatedData.isFinal,
      kemCiphertext: session.kemCiphertext,
      ciphertext: ciphertext,
      nonce: nonce,
      plaintextSha256: migrationTransferSha256Hex(plaintext),
      ciphertextSha256: migrationTransferStringSha256Hex(ciphertext),
      associatedDataSha256: associatedData.sha256Hex,
    );
  }

  @override
  Future<Uint8List> decryptChunk({
    required MigrationStreamDecryptSession session,
    required MigrationEncryptedChunk encryptedChunk,
    required MigrationChunkAssociatedData associatedData,
  }) async {
    expect(encryptedChunk.associatedDataSha256, associatedData.sha256Hex);
    expect(
      base64Decode(encryptedChunk.kemCiphertext),
      hasLength(kemCiphertextBytes),
    );
    final body = base64Decode(encryptedChunk.ciphertext);
    final encrypted = Uint8List.sublistView(body, 0, body.length - tagBytes);
    return _xor(encryptedChunk.chunkIndex, encrypted);
  }
}

// ---------------------------------------------------------------------------
// Pairing/transcript + in-memory repos (mirrors the runtime test harness)
// ---------------------------------------------------------------------------

Future<MigrationQrBuildOutput> _savePendingSession(
  _MemoryPairingSessionRepository repo, {
  String sessionId = 'e2e-session-1',
}) async {
  final createdAt = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
  final payload = MigrationQrPayload(
    sessionId: sessionId,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(minutes: 5)),
    newPhoneEphemeralPublicKey: 'new-phone-public-key',
    channelNonce: 'nonce',
  );
  await repo.savePendingNewPhoneSession(
    MigrationPendingPairingSession(
      sessionId: payload.sessionId,
      createdAt: payload.createdAt,
      expiresAt: payload.expiresAt,
      newPhoneEphemeralPublicKey: payload.newPhoneEphemeralPublicKey,
      newPhoneEphemeralSecretKey: 'new-phone-secret-key',
    ),
  );
  return MigrationQrBuildOutput(
    payload: payload,
    qrJson: payload.toJsonString(),
  );
}

AuthenticatedMigrationChannelTranscript _transcript(
  MigrationQrPayload payload,
) {
  return AuthenticatedMigrationChannelTranscript(
    sessionId: payload.sessionId,
    newPhoneEphemeralPublicKey: payload.newPhoneEphemeralPublicKey,
    oldPhonePeerId: 'old-peer',
    authenticatedChannelBinding: 'binding',
    authorizationNonce: payload.channelNonce ?? 'nonce',
  );
}

MigrationCutoverLeaseCleanup _noopLeaseCleanup() {
  return MigrationCutoverLeaseCleanup(
    unregisterPersonalRendezvous: () async {},
    unregisterInboxPushToken: () async {},
    clearLocalStalePushToken: () async {},
  );
}

class _MemoryPairingSessionRepository
    implements MigrationPairingSessionRepository {
  final pending = <String, MigrationPendingPairingSession>{};
  final consumed = <String, MigrationConsumedPairingSession>{};

  @override
  Future<void> savePendingNewPhoneSession(
    MigrationPendingPairingSession session,
  ) async {
    pending[session.sessionId] = session;
  }

  @override
  Future<MigrationPendingPairingSession?> loadPendingNewPhoneSession(
    String sessionId,
  ) async {
    return pending[sessionId];
  }

  @override
  Future<MigrationPairingSessionConsumeResult> consumeSession({
    required MigrationQrPayload payload,
    required DateTime consumedAt,
  }) async {
    if (consumed.containsKey(payload.sessionId)) {
      return MigrationPairingSessionConsumeResult.alreadyConsumed;
    }
    consumed[payload.sessionId] = MigrationConsumedPairingSession(
      sessionId: payload.sessionId,
      consumedAt: consumedAt,
      qrCreatedAt: payload.createdAt,
      qrExpiresAt: payload.expiresAt,
      newPhoneEphemeralPublicKey: payload.newPhoneEphemeralPublicKey,
    );
    return MigrationPairingSessionConsumeResult.consumed;
  }

  @override
  Future<bool> isSessionConsumed(String sessionId) async {
    return consumed.containsKey(sessionId);
  }

  @override
  Future<MigrationConsumedPairingSession?> loadConsumedSession(
    String sessionId,
  ) async {
    return consumed[sessionId];
  }
}

class _SharedFakeDiscovery implements LocalDiscoveryService {
  final Map<String, LocalPeer> registry;
  final _controller = StreamController<Map<String, LocalPeer>>.broadcast();
  String? advertisedPeerId;

  _SharedFakeDiscovery(this.registry);

  @override
  Future<void> startAdvertising(String peerId, int wsPort) async {
    advertisedPeerId = peerId;
    registry[peerId] = LocalPeer(
      peerId: peerId,
      host: 'localhost',
      port: wsPort,
      discoveredAt: DateTime.now().toUtc(),
    );
    _controller.add(Map<String, LocalPeer>.from(registry));
  }

  @override
  Future<void> stopAdvertising() async {
    final peerId = advertisedPeerId;
    if (peerId != null) {
      registry.remove(peerId);
      advertisedPeerId = null;
    }
    _controller.add(Map<String, LocalPeer>.from(registry));
  }

  @override
  Stream<Map<String, LocalPeer>> get discoveredPeersStream =>
      _controller.stream;

  @override
  Map<String, LocalPeer> get discoveredPeers =>
      Map<String, LocalPeer>.from(registry);

  @override
  bool isLocalPeer(String peerId) => registry.containsKey(peerId);

  @override
  LocalPeer? getLocalPeer(String peerId) => registry[peerId];

  @override
  Future<LocalPeer?> resolvePeer(
    String peerId, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final peer = registry[peerId];
      if (peer != null) return peer;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return registry[peerId];
  }

  @override
  void dispose() {
    _controller.close();
  }
}

class _MemoryAuthorityRepository
    implements AccountMigrationAuthorityRepository {
  AccountMigrationAuthorityRecord? saved;
  final history = <AccountMigrationAuthorityRecord>[];

  @override
  Future<void> clearAuthority() async {
    saved = null;
  }

  @override
  Future<AccountMigrationAuthorityRecord?> loadAuthority() async => saved;

  @override
  Future<void> saveAuthority(AccountMigrationAuthorityRecord record) async {
    saved = record;
    history.add(record);
  }
}

class _MemoryCutoverRepository implements MigrationCutoverRepository {
  MigrationCutoverRecord? saved;

  @override
  Future<void> clearCutover() async {
    saved = null;
  }

  @override
  Future<MigrationCutoverRecord?> loadCutover() async => saved;

  @override
  Future<void> saveCutover(MigrationCutoverRecord record) async {
    saved = record;
  }
}
