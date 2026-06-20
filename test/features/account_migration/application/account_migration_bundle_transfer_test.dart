import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_bundle_transfer.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_local_transfer_runtime.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_breadcrumb.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_coordinator.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_active_importer.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_import_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/account_migration/application/migration_entry_stream_source.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_transfer_checkpoint_store.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_cutover_record.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_cutover_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('AccountMigrationBundleTransfer', () {
    late Directory tempDir;
    late Database sourceDb;
    late Database verificationDb;
    late Database activeDb;
    late FakeSecureKeyStore sourceStore;
    late FakeSecureKeyStore destinationStore;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('account_bundle_');
      sourceDb = await openDatabase(
        p.join(tempDir.path, 'source.db'),
        version: 1,
        singleInstance: false,
      );
      verificationDb = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        singleInstance: false,
      );
      activeDb = await openDatabase(
        p.join(tempDir.path, 'active.db'),
        version: 1,
        singleInstance: false,
      );
      await _createIdentityTable(sourceDb);
      await _createIdentityTable(verificationDb);
      await _createIdentityTable(activeDb);
      sourceStore = FakeSecureKeyStore();
      destinationStore = FakeSecureKeyStore();
      for (final key in _requiredSourceKeys) {
        await sourceStore.write(key, 'value:$key');
      }
    });

    tearDown(() async {
      if (sourceDb.isOpen) {
        await sourceDb.close();
      }
      if (verificationDb.isOpen) {
        await verificationDb.close();
      }
      if (activeDb.isOpen) {
        await activeDb.close();
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'assembles encrypted transfer bundle from database snapshot and secrets',
      () async {
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
            ),
          ),
          segmentSize: 32,
        );

        final bundle = await source(_request());

        expect(bundle.encryptedSegments, isNull);
        expect(bundle.plaintextSegments, isEmpty);
        expect(bundle.streamingEntries, isNotEmpty);
        expect(bundle.manifest.sessionId, 'session-1');
        expect(
          bundle.manifest.protocolVersionValue,
          MigrationTransferManifest.protocolVersion,
        );
        expect(
          bundle.manifest
              .compatibility(
                importerProtocolVersion:
                    MigrationTransferManifest.protocolVersion,
              )
              .isAccepted,
          isTrue,
        );
        expect(
          bundle.manifest.entries.map((entry) => entry.kind),
          containsAll(const [
            MigrationTransferEntryKind.database,
            MigrationTransferEntryKind.secureValues,
          ]),
        );
        expect(
          bundle.manifest.entries.map((entry) => entry.sha256),
          everyElement(isNotEmpty),
        );
      },
    );

    test(
      'emits ordered ASSEMBLY_PHASE breadcrumbs and ASSEMBLY_OK on success',
      () async {
        final lines = <String>[];
        debugSetMigrationBreadcrumbSink(lines.add);
        addTearDown(() => debugSetMigrationBreadcrumbSink(null));

        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
            ),
          ),
          segmentSize: 32,
        );

        await source(_request());

        final phases = lines
            .where((line) => line.startsWith('MKNOON_MIG ASSEMBLY_PHASE '))
            .map((line) => line.split('phase=').last)
            .toList();
        expect(
          phases,
          containsAllInOrder(<String>[
            'validateConfiguration',
            'prepareExportDirectory',
            'readDatabaseKey',
            'loadDatabaseRows',
            'collectSecureStorage',
            'buildFilePayload',
            'applyFilePathRepairs',
            'exportDatabaseSnapshot',
            'writeMetadataBlob',
            'buildEntryStream',
          ]),
        );
        expect(
          lines.any((line) => line.startsWith('MKNOON_MIG ASSEMBLY_OK')),
          isTrue,
        );
        expect(lines.any((line) => line.contains('ASSEMBLY_FAIL')), isFalse);
      },
    );

    test(
      'emits ASSEMBLY_FAIL with the failing phase + reason when a critical '
      'secure value is missing',
      () async {
        final lines = <String>[];
        debugSetMigrationBreadcrumbSink(lines.add);
        addTearDown(() => debugSetMigrationBreadcrumbSink(null));

        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          // Empty store -> db_encryption_key missing -> throws at readDatabaseKey.
          primaryStore: FakeSecureKeyStore(),
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
            ),
          ),
          segmentSize: 32,
        );

        await expectLater(
          source(_request()),
          throwsA(isA<AccountMigrationBundleAssemblyException>()),
        );

        expect(
          lines,
          contains(
            predicate<String>(
              (line) =>
                  line.contains('ASSEMBLY_FAIL') &&
                  line.contains('phase=readDatabaseKey') &&
                  line.contains('reason=missingCriticalSecureValue'),
              'ASSEMBLY_FAIL naming phase=readDatabaseKey '
                  'reason=missingCriticalSecureValue',
            ),
          ),
        );
        // Never advanced past the failing phase.
        expect(
          lines.any((line) => line.contains('phase=loadDatabaseRows')),
          isFalse,
        );
      },
    );

    test('fails before transfer when a critical secure value is missing', () {
      final source = AccountMigrationProductionBundleSource(
        sourceDb: sourceDb,
        primaryStore: FakeSecureKeyStore(),
        documentsRootPath: tempDir.path,
        exportDirectoryPath: p.join(tempDir.path, 'exports'),
        snapshotExporter: MigrationDatabaseSnapshotExporter(
          closeExportedDatabaseAfterValidation: false,
          adapter: _RecordingSnapshotExportAdapter(
            verificationDb: verificationDb,
            snapshotBytes: utf8.encode('snapshot-db-bytes'),
          ),
        ),
      );

      expect(
        source(_request()),
        throwsA(isA<AccountMigrationBundleAssemblyException>()),
      );
    });

    test(
      'fails before transfer when required local media cannot be migrated',
      () async {
        await _createMediaAttachmentsTable(sourceDb);
        await sourceDb.insert('media_attachments', {
          'id': 'legacy-picker-path',
          'message_id': 'message-1',
          'mime': 'image/jpeg',
          'size': 128,
          'media_type': 'image',
          'local_path':
              '/data/user/0/com.mknoon.app/cache/image_picker/image.jpg',
          'download_status': 'done',
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
            ),
          ),
          segmentSize: 4096,
        );

        expect(
          source(_request()),
          throwsA(
            isA<AccountMigrationBundleAssemblyException>().having(
              (error) => accountMigrationBundleSourceFailureReason(error),
              'reason',
              'fileManifestBlockingIssues',
            ),
          ),
        );
      },
    );

    test(
      'missing critical chat media blocks bundle and leaves row unchanged',
      () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink((payload) => events.add(payload));
        addTearDown(() => debugSetFlowEventSink(null));

        await _createMessagesTable(sourceDb);
        await _createMediaAttachmentsTable(sourceDb);
        await sourceDb.insert('messages', {
          'id': 'message-1',
          'contact_peer_id': 'peer-bob',
          'sender_peer_id': 'old-peer',
          'text': '',
          'timestamp': DateTime.utc(2026, 6, 8).toIso8601String(),
          'status': 'sent',
          'is_incoming': 0,
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        await sourceDb.insert('media_attachments', {
          'id': 'missing-chat-media',
          'message_id': 'message-1',
          'mime': 'image/jpeg',
          'size': 128,
          'media_type': 'image',
          'local_path': 'media/peer-bob/missing-chat-media.jpg',
          'download_status': 'done',
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        var snapshotExportStarted = false;
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
              onExport: (db) async {
                snapshotExportStarted = true;
              },
            ),
          ),
          segmentSize: 4096,
        );

        await expectLater(
          source(_request()),
          throwsA(
            isA<AccountMigrationBundleAssemblyException>().having(
              (error) => accountMigrationBundleSourceFailureReason(error),
              'reason',
              'fileManifestBlockingIssues',
            ),
          ),
        );

        final manifestEvent = events.singleWhere(
          (event) =>
              event['event'] ==
              'ACCOUNT_MIGRATION_BUNDLE_SOURCE_FILE_MANIFEST_ISSUES',
        );
        final details = manifestEvent['details'] as Map<String, dynamic>;
        final issues = details['issues'] as List<dynamic>;
        expect(
          issues,
          contains(
            allOf(
              isA<Map<String, Object?>>(),
              containsPair('code', 'missingRequiredFile'),
              containsPair('sourceTable', 'media_attachments'),
              containsPair('sourceId', 'missing-chat-media'),
              containsPair(
                'relativePath',
                'media/peer-bob/missing-chat-media.jpg',
              ),
              containsPair('blocking', true),
              containsPair('criticality', 'critical'),
            ),
          ),
        );
        final perIssueEvent = events.singleWhere(
          (event) =>
              event['event'] ==
              'ACCOUNT_MIGRATION_BUNDLE_SOURCE_FILE_MANIFEST_ISSUE',
        );
        expect(
          perIssueEvent['details'],
          allOf(
            containsPair('phase', 'build'),
            containsPair('issueIndex', 0),
            containsPair('issueCount', 1),
            containsPair('code', 'missingRequiredFile'),
            containsPair('sourceTable', 'media_attachments'),
            containsPair('sourceId', 'missing-chat-media'),
            allOf(
              containsPair(
                'relativePath',
                'media/peer-bob/missing-chat-media.jpg',
              ),
              containsPair('blocking', true),
              containsPair('criticality', 'critical'),
            ),
          ),
        );
        expect(
          events.map((event) => event['event']),
          isNot(
            contains(
              'ACCOUNT_MIGRATION_BUNDLE_SOURCE_MISSING_MEDIA_DOWNGRADE_START',
            ),
          ),
        );
        expect(
          events.map((event) => event['event']),
          isNot(
            contains(
              'ACCOUNT_MIGRATION_BUNDLE_SOURCE_MISSING_MEDIA_DOWNGRADE_SUCCESS',
            ),
          ),
        );
        final diagnosticEvent = events.singleWhere(
          (event) =>
              event['event'] ==
              'ACCOUNT_MIGRATION_BUNDLE_SOURCE_MISSING_MEDIA_DIAGNOSTIC',
        );
        final diagnosticDetails =
            diagnosticEvent['details'] as Map<String, dynamic>;
        expect(
          diagnosticDetails,
          allOf(
            containsPair('phase', 'build'),
            containsPair('sourceId', 'missing-chat-media'),
            containsPair(
              'relativePath',
              'media/peer-bob/missing-chat-media.jpg',
            ),
            containsPair('blocking', true),
          ),
        );
        final diagnostics =
            diagnosticDetails['diagnostics'] as Map<String, dynamic>;
        expect(diagnostics['messageId'], 'message-1');
        expect(diagnostics['downloadStatus'], 'done');
        expect(diagnostics['mime'], 'image/jpeg');
        expect(diagnostics['mediaType'], 'image');
        expect(diagnostics['storedPathKind'], 'relative');
        expect(diagnostics['migrationContactPeerId'], 'peer-bob');
        expect(diagnostics['candidateCount'], 2);
        expect(diagnostics['candidateDiagnosticsCount'], 2);
        expect(diagnostics.containsKey('candidateDiagnostics'), isFalse);
        final candidateEvents = events
            .where(
              (event) =>
                  event['event'] ==
                  'ACCOUNT_MIGRATION_BUNDLE_SOURCE_MISSING_MEDIA_CANDIDATE_DIAGNOSTIC',
            )
            .toList(growable: false);
        expect(candidateEvents, hasLength(2));
        final candidates = candidateEvents
            .map(
              (event) =>
                  (event['details']
                      as Map<String, dynamic>)['candidateDiagnostic'],
            )
            .toList(growable: false);
        expect(
          candidates,
          contains(
            allOf(
              isA<Map<String, Object?>>(),
              containsPair('reason', 'source_file_missing'),
              containsPair(
                'candidateRelativePath',
                'media/peer-bob/missing-chat-media.jpg',
              ),
              containsPair('fileExists', false),
              containsPair('expectedSizeBytes', 128),
            ),
          ),
        );
        expect(
          candidateEvents.first['details'],
          allOf(
            containsPair('candidateIndex', 0),
            containsPair('candidateCount', 2),
            containsPair('sourceId', 'missing-chat-media'),
          ),
        );
        expect(snapshotExportStarted, isFalse);
        final mediaRows = await sourceDb.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['missing-chat-media'],
        );
        expect(mediaRows.single['download_status'], 'done');
        expect(
          mediaRows.single['local_path'],
          'media/peer-bob/missing-chat-media.jpg',
        );
        expect(
          events.map((event) => event['event']),
          contains('ACCOUNT_MIGRATION_BUNDLE_SOURCE_RELAY_FREE_MEDIA_AUDIT'),
        );
        final audit = events.singleWhere(
          (event) =>
              event['event'] ==
              'ACCOUNT_MIGRATION_BUNDLE_SOURCE_RELAY_FREE_MEDIA_AUDIT',
        );
        final auditDetails = audit['details'] as Map<String, dynamic>;
        expect(auditDetails['policy'], 'sanitize_missing_media_without_relay');
        expect(auditDetails['relayMediaDownloadCount'], 0);
        expect(auditDetails['relayDependencyRisk'], isTrue);
        expect(auditDetails['missingRequiredMediaCount'], 1);
        expect(auditDetails['sanitizedMissingMediaCount'], 0);
        expect(auditDetails['blockingIssueCount'], 1);
      },
    );

    test(
      'sanitized non-critical cache media keeps relay dependency risk visible',
      () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink((payload) => events.add(payload));
        addTearDown(() => debugSetFlowEventSink(null));

        await _createMessagesTable(sourceDb);
        await _createMediaAttachmentsTable(sourceDb);
        await sourceDb.insert('messages', {
          'id': 'message-1',
          'contact_peer_id': 'peer-bob',
          'sender_peer_id': 'old-peer',
          'text': '',
          'timestamp': DateTime.utc(2026, 6, 8).toIso8601String(),
          'status': 'sent',
          'is_incoming': 0,
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        await sourceDb.insert('media_attachments', {
          'id': 'missing-thumb-cache',
          'message_id': 'message-1',
          'mime': 'image/jpeg',
          'size': 128,
          'media_type': 'image',
          'local_path': 'media/peer-bob/video.thumb.jpg',
          'download_status': 'done',
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
            ),
          ),
          segmentSize: 4096,
        );

        final bundle = await source(_request());
        final payloadJson = await _readBundleMetadataJson(bundle);
        final filesJson = payloadJson['files'] as Map<String, dynamic>;
        final manifest = filesJson['manifest'] as Map<String, dynamic>;
        final manifestIssues = manifest['issues'] as List<dynamic>;

        expect(manifest['valid'], isTrue);
        expect(
          manifestIssues,
          contains(
            allOf(
              isA<Map<String, Object?>>(),
              containsPair('code', 'missingRequiredFile'),
              containsPair('source_table', 'media_attachments'),
              containsPair('source_id', 'missing-thumb-cache'),
              containsPair('blocking', false),
              containsPair('criticality', 'nonCriticalCache'),
            ),
          ),
        );
        final audit = events.singleWhere(
          (event) =>
              event['event'] ==
              'ACCOUNT_MIGRATION_BUNDLE_SOURCE_RELAY_FREE_MEDIA_AUDIT',
        );
        final auditDetails = audit['details'] as Map<String, dynamic>;
        expect(auditDetails['sanitizedMissingMediaCount'], 1);
        expect(auditDetails['relayDependencyRisk'], isTrue);
      },
    );

    test(
      'canonicalizes local media rows into bundle media paths before snapshot',
      () async {
        await _createMessagesTable(sourceDb);
        await _createMediaAttachmentsTable(sourceDb);
        await sourceDb.insert('messages', {
          'id': 'message-1',
          'contact_peer_id': 'peer-bob',
          'sender_peer_id': 'old-peer',
          'text': '',
          'timestamp': DateTime.utc(2026, 6, 8).toIso8601String(),
          'status': 'sent',
          'is_incoming': 0,
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        await sourceDb.insert('media_attachments', {
          'id': 'blob-local-media',
          'message_id': 'message-1',
          'mime': 'image/jpeg',
          'size': 5,
          'media_type': 'image',
          'local_path': 'local_media/peer-bob/blob-local-media.jpg',
          'download_status': 'done',
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        await _writeRelative(
          tempDir,
          'local_media/peer-bob/blob-local-media.jpg',
          'image',
        );
        String? localPathAtSnapshotExport;
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
              onExport: (db) async {
                final rows = await db.query(
                  'media_attachments',
                  where: 'id = ?',
                  whereArgs: ['blob-local-media'],
                );
                localPathAtSnapshotExport =
                    rows.single['local_path'] as String?;
              },
            ),
          ),
          segmentSize: 4096,
        );

        final bundle = await source(_request());
        final relativePaths = _bundleFileRelativePaths(bundle);

        expect(
          localPathAtSnapshotExport,
          'media/peer-bob/blob-local-media.jpg',
        );
        expect(
          File(
            p.join(tempDir.path, 'media/peer-bob/blob-local-media.jpg'),
          ).readAsStringSync(),
          'image',
        );
        expect(
          relativePaths,
          contains('media/peer-bob/blob-local-media.jpg'),
        );
        expect(
          relativePaths,
          isNot(contains('local_media/peer-bob/blob-local-media.jpg')),
        );
      },
    );

    test(
      'emits source file payload telemetry with migrated media row identity',
      () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink((payload) => events.add(payload));
        addTearDown(() => debugSetFlowEventSink(null));

        await _createMessagesTable(sourceDb);
        await _createMediaAttachmentsTable(sourceDb);
        await sourceDb.insert('messages', {
          'id': 'message-1',
          'contact_peer_id': 'peer-bob',
          'sender_peer_id': 'old-peer',
          'text': '',
          'timestamp': DateTime.utc(2026, 6, 8).toIso8601String(),
          'status': 'sent',
          'is_incoming': 0,
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        await sourceDb.insert('media_attachments', {
          'id': 'blob-migrated',
          'message_id': 'message-1',
          'mime': 'image/jpeg',
          'size': 5,
          'media_type': 'image',
          'local_path': 'media/peer-bob/blob-migrated.jpg',
          'download_status': 'done',
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        await _writeRelative(
          tempDir,
          'media/peer-bob/blob-migrated.jpg',
          'image',
        );
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
            ),
          ),
          segmentSize: 4096,
        );

        await source(_request());

        final payloadEvent = events.singleWhere(
          (event) =>
              event['event'] ==
              'ACCOUNT_MIGRATION_BUNDLE_SOURCE_FILE_PAYLOAD_BUILT',
        );
        final details = payloadEvent['details'] as Map<String, dynamic>;
        expect(details['fileEntryCount'], 1);
        expect(details['fileEntryBytes'], 5);
        final counts = Map<String, dynamic>.from(
          details['fileEntryCountsByKind'] as Map,
        );
        expect(counts['chatMedia'], 1);
        final entries = details['fileEntries'] as List<dynamic>;
        expect(
          entries.single,
          allOf(
            isA<Map<String, Object?>>(),
            containsPair('kind', 'chatMedia'),
            containsPair('sourceTable', 'media_attachments'),
            containsPair('sourceId', 'blob-migrated'),
            containsPair('relativePath', 'media/peer-bob/blob-migrated.jpg'),
            containsPair('entryBytes', 5),
          ),
        );
      },
    );

    test(
      'repairs stale media paths before exporting the database snapshot',
      () async {
        await _createMessagesTable(sourceDb);
        await _createMediaAttachmentsTable(sourceDb);
        await sourceDb.insert('messages', {
          'id': 'message-1',
          'contact_peer_id': 'peer-bob',
          'sender_peer_id': 'old-peer',
          'text': '',
          'timestamp': DateTime.utc(2026, 6, 8).toIso8601String(),
          'status': 'sent',
          'is_incoming': 0,
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        await sourceDb.insert('media_attachments', {
          'id': 'blob-healed',
          'message_id': 'message-1',
          'mime': 'image/jpeg',
          'size': 5,
          'media_type': 'image',
          'local_path':
              '/data/user/0/com.mknoon.app/cache/image_picker/source.jpg',
          'download_status': 'done',
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        await _writeRelative(
          tempDir,
          'media/peer-bob/blob-healed.jpg',
          'image',
        );
        String? localPathAtSnapshotExport;
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
              onExport: (db) async {
                final rows = await db.query(
                  'media_attachments',
                  where: 'id = ?',
                  whereArgs: ['blob-healed'],
                );
                localPathAtSnapshotExport =
                    rows.single['local_path'] as String?;
              },
            ),
          ),
          segmentSize: 4096,
        );

        final bundle = await source(_request());

        expect(localPathAtSnapshotExport, 'media/peer-bob/blob-healed.jpg');
        expect(
          _bundleFileRelativePaths(bundle),
          contains('media/peer-bob/blob-healed.jpg'),
        );
      },
    );

    test(
      'assembles bundle with encrypted group companion when plaintext is missing',
      () async {
        await _createGroupMessagesTable(sourceDb);
        await _createMediaAttachmentsTable(sourceDb);
        await sourceDb.insert('group_messages', {
          'id': 'group-message-1',
          'group_id': 'group-1',
        });
        await sourceDb.insert('media_attachments', {
          'id': 'blob-group',
          'message_id': 'group-message-1',
          'mime': 'image/jpeg',
          'size': 11,
          'media_type': 'image',
          'local_path': 'media/group-1/blob-group.jpg',
          'download_status': 'done',
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
          'content_hash': 'a' * 64,
          'encryption_key_base64': 'media-key',
          'encryption_nonce': 'nonce',
          'encryption_scheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        });
        await _writeRelative(
          tempDir,
          'media/group-1/blob-group.jpg.enc',
          'encrypted-group-image',
        );

        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
            ),
          ),
          segmentSize: 4096,
        );

        final bundle = await source(_request());

        expect(
          _bundleFileRelativePaths(bundle),
          contains('media/group-1/blob-group.jpg.enc'),
        );
      },
    );

    test(
      'receiver emits import file telemetry and writes migrated media files',
      () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink((payload) => events.add(payload));
        addTearDown(() => debugSetFlowEventSink(null));

        await _createMessagesTable(sourceDb);
        await _createMediaAttachmentsTable(sourceDb);
        await sourceDb.insert('messages', {
          'id': 'message-1',
          'contact_peer_id': 'peer-bob',
          'sender_peer_id': 'old-peer',
          'text': '',
          'timestamp': DateTime.utc(2026, 6, 8).toIso8601String(),
          'status': 'sent',
          'is_incoming': 0,
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        await sourceDb.insert('media_attachments', {
          'id': 'blob-imported',
          'message_id': 'message-1',
          'mime': 'image/jpeg',
          'size': 5,
          'media_type': 'image',
          'local_path': 'media/peer-bob/blob-imported.jpg',
          'download_status': 'done',
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        await _writeRelative(
          tempDir,
          'media/peer-bob/blob-imported.jpg',
          'image',
        );

        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
            ),
          ),
          segmentSize: 24,
        );
        final bundle = await source(_request());
        final destinationDocumentsPath = p.join(
          tempDir.path,
          'destination-documents',
        );
        final receiver = AccountMigrationProductionBundleReceiver(
          streamCrypto: _testStreamCrypto(),
          secureStorageStaging: MigrationSecureStorageStaging(
            primaryStore: destinationStore,
          ),
          databaseImportStaging: MigrationDatabaseImportStaging(
            secureStorageStaging: MigrationSecureStorageStaging(
              primaryStore: destinationStore,
            ),
            opener: _RecordingStagedDatabaseOpener(database: verificationDb),
          ),
          authorityRepository: _MemoryAuthorityRepository(),
          stagingDirectoryPath: p.join(tempDir.path, 'incoming'),
          documentsRootPath: destinationDocumentsPath,
        );
        final pending = _pendingSession();
        final transcript = _request().transcript;

        expect(
          await receiver.acceptManifest(
            manifest: bundle.manifest,
            transcript: transcript,
            pendingSession: pending,
          ),
          isTrue,
        );
        await _sendAllChunks(
          receiver,
          bundle,
          transcript: transcript,
          pendingSession: pending,
        );
        expect(
          await receiver.complete(
            manifest: bundle.manifest,
            transcript: transcript,
            pendingSession: pending,
          ),
          isTrue,
        );

        expect(
          File(
            p.join(
              destinationDocumentsPath,
              'media/peer-bob/blob-imported.jpg',
            ),
          ).readAsStringSync(),
          'image',
        );
        final writtenEvent = events.singleWhere(
          (event) =>
              event['event'] == 'ACCOUNT_MIGRATION_BUNDLE_IMPORT_FILES_WRITTEN',
        );
        final details = writtenEvent['details'] as Map<String, dynamic>;
        expect(details['fileEntryCount'], 1);
        expect(details['writtenCount'], 1);
        expect(details['bytesWritten'], 5);
        final entries = details['entries'] as List<dynamic>;
        expect(
          entries.single,
          allOf(
            isA<Map<String, Object?>>(),
            containsPair('kind', 'chatMedia'),
            containsPair('sourceTable', 'media_attachments'),
            containsPair('sourceId', 'blob-imported'),
            containsPair('relativePath', 'media/peer-bob/blob-imported.jpg'),
            containsPair('entryBytes', 5),
            containsPair('writeVerified', true),
          ),
        );
        final auditEvent = events.singleWhere(
          (event) =>
              event['event'] ==
              'ACCOUNT_MIGRATION_BUNDLE_IMPORT_RELAY_FREE_MEDIA_AUDIT',
        );
        final auditDetails = auditEvent['details'] as Map<String, dynamic>;
        expect(auditDetails['transport'], 'move_bundle');
        expect(auditDetails['relayMediaDownloadCount'], 0);
        expect(auditDetails['writtenCount'], 1);
      },
    );

    test(
      'receiver decrypts bundle, stages secrets, verifies DB, and records import state',
      () async {
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
            ),
          ),
          segmentSize: 24,
        );
        final bundle = await source(_request());
        final authorityRepository = _MemoryAuthorityRepository();
        final receiver = AccountMigrationProductionBundleReceiver(
          streamCrypto: _testStreamCrypto(),
          secureStorageStaging: MigrationSecureStorageStaging(
            primaryStore: destinationStore,
          ),
          databaseImportStaging: MigrationDatabaseImportStaging(
            secureStorageStaging: MigrationSecureStorageStaging(
              primaryStore: destinationStore,
            ),
            opener: _RecordingStagedDatabaseOpener(database: verificationDb),
          ),
          authorityRepository: authorityRepository,
          stagingDirectoryPath: p.join(tempDir.path, 'incoming'),
          documentsRootPath: p.join(tempDir.path, 'destination-documents'),
        );
        final pending = _pendingSession();
        final transcript = _request().transcript;

        expect(
          await receiver.acceptManifest(
            manifest: bundle.manifest,
            transcript: transcript,
            pendingSession: pending,
          ),
          isTrue,
        );
        await _sendAllChunks(
          receiver,
          bundle,
          transcript: transcript,
          pendingSession: pending,
        );

        expect(
          await receiver.complete(
            manifest: bundle.manifest,
            transcript: transcript,
            pendingSession: pending,
          ),
          isTrue,
        );

        final dbKey = MigrationSecureStorageRegistry.fixedKey(
          scope: MigrationSecureStoreScope.primary,
          activeKey: MigrationSecureStorageRegistry.dbEncryptionKey,
        )!;
        expect(
          await destinationStore.read(
            MigrationSecureStorageStaging.stagingKeyFor(
              sessionId: 'session-1',
              key: dbKey,
            ),
          ),
          'value:db_encryption_key',
        );
        expect(
          authorityRepository.saved?.state,
          AccountMigrationAuthorityState.migrationVerifiedWaitingForCutover,
        );
        expect(authorityRepository.saved?.accountPeerId, 'old-peer');
      },
    );

    test(
      'receiver finalizes cutover into active DB without replacing the new DB key',
      () async {
        await activeDb.delete('identity');
        await activeDb.insert('identity', {
          'id': 1,
          'peer_id': 'new-temp-peer',
          'public_key': 'new-public',
          'username': 'new-temp',
        });
        await destinationStore.write(
          MigrationSecureStorageRegistry.dbEncryptionKey,
          'new-active-db-key',
        );
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
            ),
          ),
          segmentSize: 24,
        );
        final bundle = await source(_request());
        final authorityRepository = _MemoryAuthorityRepository();
        final cutoverRepository = _MemoryCutoverRepository();
        final receiver = AccountMigrationProductionBundleReceiver(
          streamCrypto: _testStreamCrypto(),
          secureStorageStaging: MigrationSecureStorageStaging(
            primaryStore: destinationStore,
          ),
          databaseImportStaging: MigrationDatabaseImportStaging(
            secureStorageStaging: MigrationSecureStorageStaging(
              primaryStore: destinationStore,
            ),
            opener: _RecordingStagedDatabaseOpener(database: verificationDb),
          ),
          activeDatabaseImporter: MigrationDatabaseActiveImporter(
            activeDatabase: activeDb,
          ),
          cutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: authorityRepository,
            cutoverRepository: cutoverRepository,
            now: () => DateTime.utc(2026, 6, 8, 12),
          ),
          authorityRepository: authorityRepository,
          stagingDirectoryPath: p.join(tempDir.path, 'incoming'),
          documentsRootPath: p.join(tempDir.path, 'destination-documents'),
        );
        final pending = _pendingSession();
        final transcript = _request().transcript;

        expect(
          await receiver.acceptManifest(
            manifest: bundle.manifest,
            transcript: transcript,
            pendingSession: pending,
          ),
          isTrue,
        );
        await _sendAllChunks(
          receiver,
          bundle,
          transcript: transcript,
          pendingSession: pending,
        );
        expect(
          await receiver.complete(
            manifest: bundle.manifest,
            transcript: transcript,
            pendingSession: pending,
          ),
          isTrue,
        );

        final newActiveProof = await receiver.acceptOldBlockProof(
          manifest: bundle.manifest,
          transcript: transcript,
          pendingSession: pending,
          oldBlockProof: _oldBlockProof(),
        );

        expect(newActiveProof?.provesNewActiveCommitted, isTrue);
        expect(
          authorityRepository.saved?.state,
          AccountMigrationAuthorityState.active,
        );
        expect(cutoverRepository.saved?.provesNewActiveCommitted, isTrue);
        expect(await activeDb.query('identity'), [
          {
            'id': 1,
            'peer_id': 'old-peer',
            'public_key': 'public',
            'username': 'alice',
          },
        ]);
        expect(
          await destinationStore.read(
            MigrationSecureStorageRegistry.dbEncryptionKey,
          ),
          'new-active-db-key',
        );
        expect(
          await destinationStore.read(
            MigrationSecureStorageRegistry.identityPrivateKey,
          ),
          'value:identity_private_key',
        );
      },
    );

    group('receiver completion and proof stage telemetry', () {
      late List<Map<String, dynamic>> events;

      setUp(() {
        events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
      });

      tearDown(() => debugSetFlowEventSink(null));

      Future<AccountMigrationLocalTransferBundle> buildBundle() {
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
            ),
          ),
          segmentSize: 24,
        );
        return source(_request());
      }

      AccountMigrationProductionBundleReceiver buildReceiver({
        MigrationStagedDatabaseOpener? opener,
        MigrationDatabaseActiveImporter? activeImporter,
        MigrationCutoverCoordinator? coordinator,
        AccountMigrationAuthorityRepository? authorityRepository,
      }) {
        return AccountMigrationProductionBundleReceiver(
          streamCrypto: _testStreamCrypto(),
          secureStorageStaging: MigrationSecureStorageStaging(
            primaryStore: destinationStore,
          ),
          databaseImportStaging: MigrationDatabaseImportStaging(
            secureStorageStaging: MigrationSecureStorageStaging(
              primaryStore: destinationStore,
            ),
            opener:
                opener ?? _RecordingStagedDatabaseOpener(database: verificationDb),
          ),
          activeDatabaseImporter: activeImporter,
          cutoverCoordinator: coordinator,
          authorityRepository:
              authorityRepository ?? _MemoryAuthorityRepository(),
          stagingDirectoryPath: p.join(tempDir.path, 'incoming'),
          documentsRootPath: p.join(tempDir.path, 'destination-documents'),
        );
      }

      Future<void> acceptAll(
        AccountMigrationProductionBundleReceiver receiver,
        AccountMigrationLocalTransferBundle bundle,
      ) async {
        final pending = _pendingSession();
        final transcript = _request().transcript;
        expect(
          await receiver.acceptManifest(
            manifest: bundle.manifest,
            transcript: transcript,
            pendingSession: pending,
          ),
          isTrue,
        );
        await _sendAllChunks(
          receiver,
          bundle,
          transcript: transcript,
          pendingSession: pending,
        );
      }

      List<Map<String, dynamic>> detailsNamed(String name) => events
          .where((event) => event['event'] == name)
          .map(
            (event) => Map<String, dynamic>.from(event['details'] as Map),
          )
          .toList(growable: false);

      test('complete emits stage telemetry on successful import', () async {
        final bundle = await buildBundle();
        final receiver = buildReceiver();
        await acceptAll(receiver, bundle);

        expect(
          await receiver.complete(
            manifest: bundle.manifest,
            transcript: _request().transcript,
            pendingSession: _pendingSession(),
          ),
          isTrue,
        );

        final stages = detailsNamed(
          'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_COMPLETE_STAGE',
        );
        // P2-5: complete() is a ledger check + staged-DB validation; the v1
        // whole-payload `payloadDecode` stage no longer exists.
        expect(stages.map((details) => details['stage']).toList(), [
          'ledgerCheck',
          'secureStaging',
          'stagedDbOpen',
          'importFiles',
          'authorityRecord',
        ]);
        expect(
          stages.map((details) => details['stage']),
          isNot(contains('payloadDecode')),
        );
        for (final details in stages) {
          expect(details['sessionId'], 'session-1');
          expect(details['elapsedMs'], isA<int>());
        }
        expect(
          detailsNamed('ACCOUNT_MIGRATION_BUNDLE_RECEIVER_COMPLETE_FAILED'),
          isEmpty,
        );
      });

      test(
        'complete with unverified entries fails typed with the missing count',
        () async {
          final bundle = await buildBundle();
          final receiver = buildReceiver();
          final pending = _pendingSession();
          final transcript = _request().transcript;
          expect(
            await receiver.acceptManifest(
              manifest: bundle.manifest,
              transcript: transcript,
              pendingSession: pending,
            ),
            isTrue,
          );
          // No chunks sent at all: every non-empty entry is missing.
          expect(
            await receiver.complete(
              manifest: bundle.manifest,
              transcript: transcript,
              pendingSession: pending,
            ),
            isFalse,
          );

          final missing = detailsNamed(
            'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_COMPLETE_MISSING_ENTRIES',
          ).single;
          expect(missing['sessionId'], 'session-1');
          expect(
            missing['missingEntryCount'],
            bundle.manifest.entries
                .where((entry) => entry.sizeBytes > 0)
                .length,
          );
          // The failure carries the COUNT of missing entries, never contents.
          expect(
            jsonEncode(missing),
            isNot(contains('snapshot-db-bytes')),
          );
        },
      );

      test('complete failure during staged db open is diagnosable', () async {
        final bundle = await buildBundle();
        final receiver = buildReceiver(opener: _ThrowingStagedDatabaseOpener());
        await acceptAll(receiver, bundle);

        expect(
          await receiver.complete(
            manifest: bundle.manifest,
            transcript: _request().transcript,
            pendingSession: _pendingSession(),
          ),
          isFalse,
        );

        final failed = detailsNamed(
          'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_COMPLETE_FAILED',
        ).single;
        expect(failed['stage'], 'stagedDbOpen');
        expect(failed['errorType'], isNotEmpty);
        for (final event in events) {
          final encoded = jsonEncode(event['details']);
          expect(encoded, isNot(contains('value:identity_private_key')));
          expect(encoded, isNot(contains('value:db_encryption_key')));
        }
      });

      test('old block proof emits stage telemetry on success', () async {
        await activeDb.delete('identity');
        await activeDb.insert('identity', {
          'id': 1,
          'peer_id': 'new-temp-peer',
          'public_key': 'new-public',
          'username': 'new-temp',
        });
        await destinationStore.write(
          MigrationSecureStorageRegistry.dbEncryptionKey,
          'new-active-db-key',
        );
        final bundle = await buildBundle();
        final authorityRepository = _MemoryAuthorityRepository();
        final receiver = buildReceiver(
          activeImporter: MigrationDatabaseActiveImporter(
            activeDatabase: activeDb,
          ),
          coordinator: MigrationCutoverCoordinator(
            authorityRepository: authorityRepository,
            cutoverRepository: _MemoryCutoverRepository(),
            now: () => DateTime.utc(2026, 6, 8, 12),
          ),
          authorityRepository: authorityRepository,
        );
        await acceptAll(receiver, bundle);
        expect(
          await receiver.complete(
            manifest: bundle.manifest,
            transcript: _request().transcript,
            pendingSession: _pendingSession(),
          ),
          isTrue,
        );

        final newActiveProof = await receiver.acceptOldBlockProof(
          manifest: bundle.manifest,
          transcript: _request().transcript,
          pendingSession: _pendingSession(),
          oldBlockProof: _oldBlockProof(),
        );

        expect(newActiveProof?.provesNewActiveCommitted, isTrue);
        final stages = detailsNamed(
          'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_OLD_BLOCK_PROOF_STAGE',
        );
        expect(stages.map((details) => details['stage']).toList(), [
          'activeDbImport',
          'securePromotion',
          'recordOldBlockProof',
          'commitNewActive',
          'cleanup',
        ]);
        expect(
          detailsNamed(
            'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_OLD_BLOCK_PROOF_FAILED',
          ),
          isEmpty,
        );
      });

      test(
        'old block proof failure during active import is diagnosable',
        () async {
          final bundle = await buildBundle();
          final receiver = buildReceiver(
            activeImporter: _ThrowingActiveImporter(),
            coordinator: MigrationCutoverCoordinator(
              authorityRepository: _MemoryAuthorityRepository(),
              cutoverRepository: _MemoryCutoverRepository(),
              now: () => DateTime.utc(2026, 6, 8, 12),
            ),
          );
          await acceptAll(receiver, bundle);
          expect(
            await receiver.complete(
              manifest: bundle.manifest,
              transcript: _request().transcript,
              pendingSession: _pendingSession(),
            ),
            isTrue,
          );

          final newActiveProof = await receiver.acceptOldBlockProof(
            manifest: bundle.manifest,
            transcript: _request().transcript,
            pendingSession: _pendingSession(),
            oldBlockProof: _oldBlockProof(),
          );

          expect(newActiveProof, isNull);
          final failed = detailsNamed(
            'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_OLD_BLOCK_PROOF_FAILED',
          ).single;
          expect(failed['sessionId'], 'session-1');
          expect(failed['stage'], 'activeDbImport');
          expect(failed['errorType'], 'StateError');
          for (final event in events) {
            final encoded = jsonEncode(event['details']);
            expect(encoded, isNot(contains('value:identity_private_key')));
          }
        },
      );

      test(
        'old block proof failure at new active commit is diagnosable',
        () async {
          await activeDb.delete('identity');
          await activeDb.insert('identity', {
            'id': 1,
            'peer_id': 'new-temp-peer',
            'public_key': 'new-public',
            'username': 'new-temp',
          });
          final bundle = await buildBundle();
          final receiver = buildReceiver(
            activeImporter: MigrationDatabaseActiveImporter(
              activeDatabase: activeDb,
            ),
            coordinator: _ThrowingCommitCoordinator(
              authorityRepository: _MemoryAuthorityRepository(),
              cutoverRepository: _MemoryCutoverRepository(),
            ),
          );
          await acceptAll(receiver, bundle);
          expect(
            await receiver.complete(
              manifest: bundle.manifest,
              transcript: _request().transcript,
              pendingSession: _pendingSession(),
            ),
            isTrue,
          );

          final newActiveProof = await receiver.acceptOldBlockProof(
            manifest: bundle.manifest,
            transcript: _request().transcript,
            pendingSession: _pendingSession(),
            oldBlockProof: _oldBlockProof(),
          );

          expect(newActiveProof, isNull);
          final failed = detailsNamed(
            'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_OLD_BLOCK_PROOF_FAILED',
          ).single;
          expect(failed['stage'], 'commitNewActive');
          expect(failed['errorType'], 'StateError');
        },
      );
    });

    group('protocol v2 entry-streamed receiver', () {
      Future<AccountMigrationLocalTransferBundle> buildBundle({
        int segmentSize = 24,
      }) async {
        await _createMessagesTable(sourceDb);
        await _createMediaAttachmentsTable(sourceDb);
        await sourceDb.insert('messages', {
          'id': 'message-1',
          'contact_peer_id': 'peer-bob',
          'sender_peer_id': 'old-peer',
          'text': '',
          'timestamp': DateTime.utc(2026, 6, 8).toIso8601String(),
          'status': 'sent',
          'is_incoming': 0,
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        await sourceDb.insert('media_attachments', {
          'id': 'blob-imported',
          'message_id': 'message-1',
          'mime': 'image/jpeg',
          'size': 64,
          'media_type': 'image',
          'local_path': 'media/peer-bob/blob-imported.jpg',
          'download_status': 'done',
          'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
        });
        await _writeRelative(
          tempDir,
          'media/peer-bob/blob-imported.jpg',
          'i' * 64,
        );
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            closeExportedDatabaseAfterValidation: false,
            adapter: _RecordingSnapshotExportAdapter(
              verificationDb: verificationDb,
              snapshotBytes: utf8.encode('snapshot-db-bytes'),
            ),
          ),
          segmentSize: segmentSize,
        );
        return source(_request());
      }

      AccountMigrationProductionBundleReceiver buildReceiver() {
        return AccountMigrationProductionBundleReceiver(
          streamCrypto: _testStreamCrypto(),
          secureStorageStaging: MigrationSecureStorageStaging(
            primaryStore: destinationStore,
          ),
          databaseImportStaging: MigrationDatabaseImportStaging(
            secureStorageStaging: MigrationSecureStorageStaging(
              primaryStore: destinationStore,
            ),
            opener: _RecordingStagedDatabaseOpener(database: verificationDb),
          ),
          authorityRepository: _MemoryAuthorityRepository(),
          stagingDirectoryPath: p.join(tempDir.path, 'incoming'),
          documentsRootPath: p.join(tempDir.path, 'destination-documents'),
        );
      }

      Future<MigrationEncryptedChunk> encryptFirstChunk(
        AccountMigrationLocalTransferBundle bundle,
        String entryId, {
        int chunkIndex = 0,
        int? offset,
        bool? isFinal,
      }) async {
        final crypto = _testStreamCrypto();
        final manifest = bundle.manifest;
        final ordinal = manifest.entries.indexWhere(
          (entry) => entry.entryId == entryId,
        );
        final descriptor = manifest.entries[ordinal];
        final entry = bundle.streamingEntries.firstWhere(
          (entry) => entry.entryId == entryId,
        );
        final chunkOffset = offset ?? chunkIndex * descriptor.chunkSize;
        final plaintext = await entry
            .openChunks(offset: chunkOffset)
            .first;
        final session = await crypto.encapsulateSession(
          recipientMlKemPublicKey: 'new-public-key',
          sessionId: manifest.sessionId,
          bundleId: manifest.bundleId,
          direction: MigrationStreamDirection.oldToNew,
        );
        return crypto.encryptChunk(
          session: session,
          plaintext: plaintext,
          associatedData: MigrationChunkAssociatedData(
            sessionId: manifest.sessionId,
            bundleId: manifest.bundleId,
            entryId: entryId,
            chunkIndex: chunkIndex,
            offset: chunkOffset,
            isFinal:
                isFinal ??
                chunkOffset + plaintext.length >= descriptor.sizeBytes,
          ),
          nonce: migrationChunkNonceBase64(
            entryOrdinal: ordinal,
            chunkIndex: chunkIndex,
          ),
        );
      }

      test(
        'rejects out-of-order chunks typed without corrupting the offset and '
        'accepts duplicates idempotently',
        () async {
          final bundle = await buildBundle();
          final receiver = buildReceiver();
          final pending = _pendingSession();
          final transcript = _request().transcript;
          expect(
            await receiver.acceptManifest(
              manifest: bundle.manifest,
              transcript: transcript,
              pendingSession: pending,
            ),
            isTrue,
          );

          // Chunk 1 before chunk 0 → typed out-of-order reject.
          final outOfOrder = await receiver.acceptChunk(
            manifest: bundle.manifest,
            chunk: await encryptFirstChunk(
              bundle,
              'file-0',
              chunkIndex: 1,
            ),
            transcript: transcript,
            pendingSession: pending,
          );
          expect(outOfOrder.code, AccountMigrationChunkAcceptCode.outOfOrder);

          // Chunk 0 still lands at offset 0 afterwards.
          final first = await encryptFirstChunk(bundle, 'file-0');
          final accepted = await receiver.acceptChunk(
            manifest: bundle.manifest,
            chunk: first,
            transcript: transcript,
            pendingSession: pending,
          );
          expect(accepted.code, AccountMigrationChunkAcceptCode.accepted);

          // Retransmission of the same chunk: idempotent, no double write.
          final duplicate = await receiver.acceptChunk(
            manifest: bundle.manifest,
            chunk: first,
            transcript: transcript,
            pendingSession: pending,
          );
          expect(duplicate.code, AccountMigrationChunkAcceptCode.duplicate);
          expect(
            duplicate.verifiedChunkCount,
            accepted.verifiedChunkCount,
          );

          final status = await receiver.transferStatus(
            manifest: bundle.manifest,
            transcript: transcript,
            pendingSession: pending,
          );
          expect(status!.entryOffsets['file-0'], 24);
        },
      );

      test('rejects a tampered chunk with a typed decrypt failure', () async {
        final bundle = await buildBundle();
        final receiver = buildReceiver();
        final pending = _pendingSession();
        final transcript = _request().transcript;
        expect(
          await receiver.acceptManifest(
            manifest: bundle.manifest,
            transcript: transcript,
            pendingSession: pending,
          ),
          isTrue,
        );

        final chunk = await encryptFirstChunk(bundle, 'file-0');
        final tampered = chunk.copyWith(
          ciphertext: '${chunk.ciphertext}corrupt',
        );
        final outcome = await receiver.acceptChunk(
          manifest: bundle.manifest,
          chunk: tampered,
          transcript: transcript,
          pendingSession: pending,
        );
        expect(outcome.code, AccountMigrationChunkAcceptCode.decryptFailed);
      });

      test(
        'finalizes file entries by rename: staging keeps no second copy',
        () async {
          final bundle = await buildBundle();
          final receiver = buildReceiver();
          final pending = _pendingSession();
          final transcript = _request().transcript;
          expect(
            await receiver.acceptManifest(
              manifest: bundle.manifest,
              transcript: transcript,
              pendingSession: pending,
            ),
            isTrue,
          );
          await _sendAllChunks(
            receiver,
            bundle,
            transcript: transcript,
            pendingSession: pending,
          );
          expect(
            await receiver.complete(
              manifest: bundle.manifest,
              transcript: transcript,
              pendingSession: pending,
            ),
            isTrue,
          );

          final imported = File(
            p.join(
              tempDir.path,
              'destination-documents',
              'media/peer-bob/blob-imported.jpg',
            ),
          );
          expect(imported.readAsStringSync(), 'i' * 64);
          // The staged entry file MOVED (rename), it was not copied: no
          // media-entry file and no .partial remains under staging.
          final entriesDir = Directory(
            p.join(tempDir.path, 'incoming', 'session-1', 'entries'),
          );
          final residue = entriesDir
              .listSync()
              .map((child) => p.basename(child.path))
              .where(
                (name) =>
                    name.startsWith('file-') || name.endsWith('.partial'),
              );
          expect(residue, isEmpty);
        },
      );

      test(
        'receiver restart resumes from the file-backed ledger without '
        'resending verified entries',
        () async {
          final bundle = await buildBundle();
          final pending = _pendingSession();
          final transcript = _request().transcript;

          final firstReceiver = buildReceiver();
          expect(
            await firstReceiver.acceptManifest(
              manifest: bundle.manifest,
              transcript: transcript,
              pendingSession: pending,
            ),
            isTrue,
          );
          // Verify only the first chunk of file-0, then "restart" the phone.
          final partial = await firstReceiver.acceptChunk(
            manifest: bundle.manifest,
            chunk: await encryptFirstChunk(bundle, 'file-0'),
            transcript: transcript,
            pendingSession: pending,
          );
          expect(partial.code, AccountMigrationChunkAcceptCode.accepted);

          final restarted = buildReceiver();
          expect(
            await restarted.acceptManifest(
              manifest: bundle.manifest,
              transcript: transcript,
              pendingSession: pending,
            ),
            isTrue,
          );
          final status = await restarted.transferStatus(
            manifest: bundle.manifest,
            transcript: transcript,
            pendingSession: pending,
          );
          expect(status!.entryOffsets['file-0'], 24);

          // The remaining bytes resume from the persisted offset, the entry
          // hash still verifies, and the whole import completes.
          await _sendAllChunksFrom(
            restarted,
            bundle,
            status,
            transcript: transcript,
            pendingSession: pending,
          );
          expect(
            await restarted.complete(
              manifest: bundle.manifest,
              transcript: transcript,
              pendingSession: pending,
            ),
            isTrue,
          );
        },
      );

      test(
        'a changed manifest carries identical entries over and wipes '
        'changed ones',
        () async {
          final bundle = await buildBundle();
          final receiver = buildReceiver();
          final pending = _pendingSession();
          final transcript = _request().transcript;
          expect(
            await receiver.acceptManifest(
              manifest: bundle.manifest,
              transcript: transcript,
              pendingSession: pending,
            ),
            isTrue,
          );
          expect(
            (await receiver.acceptChunk(
              manifest: bundle.manifest,
              chunk: await encryptFirstChunk(bundle, 'file-0'),
              transcript: transcript,
              pendingSession: pending,
            )).isAccepted,
            isTrue,
          );

          // Identical entries under a rebuilt bundle id (e.g. only the DB
          // snapshot changed) keep their verified offsets.
          final rebundled = bundle.manifest.copyWith(
            bundleId: 'bundle-different',
          );
          expect(
            await receiver.acceptManifest(
              manifest: rebundled,
              transcript: transcript,
              pendingSession: pending,
            ),
            isTrue,
          );
          final carried = await receiver.transferStatus(
            manifest: rebundled,
            transcript: transcript,
            pendingSession: pending,
          );
          expect(carried!.entryOffsets['file-0'], 24);

          // A content-changed entry is wiped: its partial can never verify.
          final changed = rebundled.copyWith(
            bundleId: 'bundle-changed',
            entries: rebundled.entries
                .map(
                  (entry) => entry.entryId == 'file-0'
                      ? MigrationTransferEntryDescriptor(
                          entryId: entry.entryId,
                          kind: entry.kind,
                          relativePath: entry.relativePath,
                          sizeBytes: entry.sizeBytes,
                          sha256: 'f' * 64,
                          chunkSize: entry.chunkSize,
                          chunkCount: entry.chunkCount,
                        )
                      : entry,
                )
                .toList(growable: false),
          );
          expect(
            await receiver.acceptManifest(
              manifest: changed,
              transcript: transcript,
              pendingSession: pending,
            ),
            isTrue,
          );
          final wiped = await receiver.transferStatus(
            manifest: changed,
            transcript: transcript,
            pendingSession: pending,
          );
          expect(wiped!.entryOffsets['file-0'], anyOf(isNull, 0));
          expect(
            File(
              p.join(
                tempDir.path,
                'incoming',
                'session-1',
                'entries',
                'file-0.partial',
              ),
            ).existsSync(),
            isFalse,
          );
        },
      );

      test(
        'P2-3: production source builds and streams without whole-file reads',
        () async {
          await _createMessagesTable(sourceDb);
          await _createMediaAttachmentsTable(sourceDb);
          await sourceDb.insert('messages', {
            'id': 'message-1',
            'contact_peer_id': 'peer-bob',
            'sender_peer_id': 'old-peer',
            'text': '',
            'timestamp': DateTime.utc(2026, 6, 8).toIso8601String(),
            'status': 'sent',
            'is_incoming': 0,
            'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
          });
          await sourceDb.insert('media_attachments', {
            'id': 'blob-streamed',
            'message_id': 'message-1',
            'mime': 'image/jpeg',
            'size': 64,
            'media_type': 'image',
            'local_path': 'media/peer-bob/blob-streamed.jpg',
            'download_status': 'done',
            'created_at': DateTime.utc(2026, 6, 8).toIso8601String(),
          });
          await _writeRelative(
            tempDir,
            'media/peer-bob/blob-streamed.jpg',
            's' * 64,
          );
          final reader = _GuardedEntryFileReader();
          final source = AccountMigrationProductionBundleSource(
            sourceDb: sourceDb,
            primaryStore: sourceStore,
            documentsRootPath: tempDir.path,
            exportDirectoryPath: p.join(tempDir.path, 'exports'),
            snapshotExporter: MigrationDatabaseSnapshotExporter(
              closeExportedDatabaseAfterValidation: false,
              adapter: _RecordingSnapshotExportAdapter(
                verificationDb: verificationDb,
                snapshotBytes: utf8.encode('snapshot-db-bytes'),
              ),
            ),
            fileReader: reader,
            segmentSize: 24,
          );

          final bundle = await source(_request());
          // Drain every entry stream end-to-end like the sender loop does.
          for (final entry in bundle.streamingEntries) {
            await for (final _ in entry.openChunks()) {}
          }

          expect(reader.readAllCalls, 0);
          expect(reader.maxActiveChunks, lessThanOrEqualTo(1));
        },
      );

      test('rejects a legacy v1 manifest typed (sender too old)', () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        final receiver = buildReceiver();
        final legacy = MigrationTransferManifest.legacyV1(
          sessionId: 'session-1',
          bundleId: 'bundle-legacy',
          segmentSize: 24,
          totalBytes: 24,
          manifestSha256: 'legacy-hash',
          segments: [
            MigrationTransferSegmentDescriptor(
              index: 0,
              offset: 0,
              plaintextLength: 24,
              plaintextSha256: 'p' * 64,
              ciphertextSha256: 'c' * 64,
              nonce: 'nonce-0',
            ),
          ],
        );
        expect(
          await receiver.acceptManifest(
            manifest: legacy,
            transcript: _request().transcript,
            pendingSession: _pendingSession(),
          ),
          isFalse,
        );
        final incompatible = events.singleWhere(
          (event) =>
              event['event'] ==
              'ACCOUNT_MIGRATION_BUNDLE_RECEIVER_MANIFEST_INCOMPATIBLE',
        );
        expect(
          (incompatible['details'] as Map)['errors'],
          contains('senderTooOld'),
        );
      });
    });
  });
}

class _ThrowingStagedDatabaseOpener implements MigrationStagedDatabaseOpener {
  @override
  Future<Database> open({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) async {
    throw StateError('staged database open refused');
  }
}

class _ThrowingActiveImporter implements MigrationDatabaseActiveImporter {
  @override
  Database get activeDatabase => throw StateError('no active database');

  @override
  Future<MigrationDatabaseActiveImportResult> importVerifiedStagedDatabase(
    MigrationDatabaseImportStagingResult staged,
  ) async {
    throw StateError('active import refused');
  }
}

class _ThrowingCommitCoordinator extends MigrationCutoverCoordinator {
  _ThrowingCommitCoordinator({
    required super.authorityRepository,
    required super.cutoverRepository,
  }) : super(now: () => DateTime.utc(2026, 6, 8, 12));

  @override
  Future<MigrationCutoverRecord> commitNewActive({
    required String sessionId,
    required String accountPeerId,
    required String devicePeerId,
    required bool importVerified,
    required MigrationCutoverRecord oldBlockProof,
  }) async {
    throw StateError('commit refused');
  }
}

Future<void> _createIdentityTable(Database db) async {
  await db.execute('''
CREATE TABLE identity (
  id INTEGER PRIMARY KEY,
  peer_id TEXT NOT NULL,
  public_key TEXT NOT NULL,
  username TEXT NOT NULL
)
''');
  await db.insert('identity', {
    'id': 1,
    'peer_id': 'old-peer',
    'public_key': 'public',
    'username': 'alice',
  });
}

Future<void> _createMediaAttachmentsTable(Database db) async {
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
}

Future<void> _createGroupMessagesTable(Database db) async {
  await db.execute('''
CREATE TABLE group_messages (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL
)
''');
}

Future<void> _createMessagesTable(Database db) async {
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

/// Synchronous chunk-work executor: the production default is Isolate.run,
/// which these tests bypass for speed/determinism.
Future<R> _inlineChunkWork<R>(R Function() work) async => work();

/// Real streaming IO that refuses whole-file reads and tracks how many
/// chunks are in flight, proving the P2-3 bounded-memory contract.
class _GuardedEntryFileReader implements MigrationEntryFileReader {
  static const _inner = IoMigrationEntryFileReader();
  int readAllCalls = 0;
  int _activeChunks = 0;
  int maxActiveChunks = 0;

  @override
  Future<int> length(String path) => _inner.length(path);

  @override
  Future<String> sha256Hex(String path) => _inner.sha256Hex(path);

  @override
  Stream<Uint8List> openRead(
    String path, {
    required int offset,
    required int chunkSize,
  }) async* {
    await for (final chunk in _inner.openRead(
      path,
      offset: offset,
      chunkSize: chunkSize,
    )) {
      _activeChunks += 1;
      if (_activeChunks > maxActiveChunks) {
        maxActiveChunks = _activeChunks;
      }
      yield chunk;
      _activeChunks -= 1;
    }
  }

  @override
  Future<Uint8List> readAll(String path) async {
    readAllCalls += 1;
    throw StateError('whole-file read is forbidden in protocol v2');
  }
}

BridgeMigrationStreamCrypto _testStreamCrypto() {
  return BridgeMigrationStreamCrypto(
    bridge: FakeBridge(),
    executeChunkWork: _inlineChunkWork,
  );
}

/// Drives the protocol v2 sender half against a receiver: one encapsulation,
/// then every entry streamed and encrypted chunk-by-chunk.
Future<void> _sendAllChunks(
  AccountMigrationProductionBundleReceiver receiver,
  AccountMigrationLocalTransferBundle bundle, {
  required AuthenticatedMigrationChannelTranscript transcript,
  required MigrationPendingPairingSession pendingSession,
}) async {
  final crypto = _testStreamCrypto();
  final manifest = bundle.manifest;
  final session = await crypto.encapsulateSession(
    recipientMlKemPublicKey: transcript.newPhoneEphemeralPublicKey,
    sessionId: manifest.sessionId,
    bundleId: manifest.bundleId,
    direction: MigrationStreamDirection.oldToNew,
  );
  final entriesById = {
    for (final entry in bundle.streamingEntries) entry.entryId: entry,
  };
  for (var ordinal = 0; ordinal < manifest.entries.length; ordinal += 1) {
    final descriptor = manifest.entries[ordinal];
    if (descriptor.sizeBytes == 0) {
      continue;
    }
    final entry = entriesById[descriptor.entryId]!;
    var offset = 0;
    var chunkIndex = 0;
    await for (final plaintext in entry.openChunks()) {
      final encrypted = await crypto.encryptChunk(
        session: session,
        plaintext: plaintext,
        associatedData: MigrationChunkAssociatedData(
          sessionId: manifest.sessionId,
          bundleId: manifest.bundleId,
          entryId: descriptor.entryId,
          chunkIndex: chunkIndex,
          offset: offset,
          isFinal: offset + plaintext.length >= descriptor.sizeBytes,
        ),
        nonce: migrationChunkNonceBase64(
          entryOrdinal: ordinal,
          chunkIndex: chunkIndex,
        ),
      );
      final outcome = await receiver.acceptChunk(
        manifest: manifest,
        chunk: encrypted,
        transcript: transcript,
        pendingSession: pendingSession,
      );
      expect(
        outcome.isAccepted,
        isTrue,
        reason:
            'chunk ${descriptor.entryId}/$chunkIndex rejected: '
            '${outcome.code}',
      );
      offset += plaintext.length;
      chunkIndex += 1;
    }
  }
}

/// Resume-aware variant of [_sendAllChunks]: skips verified entries and
/// starts each remaining entry from the ledger offset, with a FRESH
/// encapsulation (one per transfer attempt).
Future<void> _sendAllChunksFrom(
  AccountMigrationProductionBundleReceiver receiver,
  AccountMigrationLocalTransferBundle bundle,
  MigrationTransferLedgerStatus status, {
  required AuthenticatedMigrationChannelTranscript transcript,
  required MigrationPendingPairingSession pendingSession,
}) async {
  final crypto = _testStreamCrypto();
  final manifest = bundle.manifest;
  final session = await crypto.encapsulateSession(
    recipientMlKemPublicKey: transcript.newPhoneEphemeralPublicKey,
    sessionId: manifest.sessionId,
    bundleId: manifest.bundleId,
    direction: MigrationStreamDirection.oldToNew,
  );
  final verified = status.verifiedEntryIds.toSet();
  final entriesById = {
    for (final entry in bundle.streamingEntries) entry.entryId: entry,
  };
  for (var ordinal = 0; ordinal < manifest.entries.length; ordinal += 1) {
    final descriptor = manifest.entries[ordinal];
    if (descriptor.sizeBytes == 0 || verified.contains(descriptor.entryId)) {
      continue;
    }
    var offset = status.entryOffsets[descriptor.entryId] ?? 0;
    if (offset % descriptor.chunkSize != 0 || offset >= descriptor.sizeBytes) {
      offset = 0;
    }
    var chunkIndex = offset ~/ descriptor.chunkSize;
    final entry = entriesById[descriptor.entryId]!;
    await for (final plaintext in entry.openChunks(offset: offset)) {
      final encrypted = await crypto.encryptChunk(
        session: session,
        plaintext: plaintext,
        associatedData: MigrationChunkAssociatedData(
          sessionId: manifest.sessionId,
          bundleId: manifest.bundleId,
          entryId: descriptor.entryId,
          chunkIndex: chunkIndex,
          offset: offset,
          isFinal: offset + plaintext.length >= descriptor.sizeBytes,
        ),
        nonce: migrationChunkNonceBase64(
          entryOrdinal: ordinal,
          chunkIndex: chunkIndex,
        ),
      );
      final outcome = await receiver.acceptChunk(
        manifest: manifest,
        chunk: encrypted,
        transcript: transcript,
        pendingSession: pendingSession,
      );
      expect(
        outcome.isAccepted,
        isTrue,
        reason:
            'resumed chunk ${descriptor.entryId}/$chunkIndex rejected: '
            '${outcome.code}',
      );
      offset += plaintext.length;
      chunkIndex += 1;
    }
  }
}

/// Reads the small secure-values metadata entry from the bundle's streams.
Future<Map<String, dynamic>> _readBundleMetadataJson(
  AccountMigrationLocalTransferBundle bundle,
) async {
  final entry = bundle.streamingEntries.firstWhere(
    (entry) => entry.kind == MigrationTransferEntryKind.secureValues,
  );
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in entry.openChunks()) {
    bytes.add(chunk);
  }
  return jsonDecode(utf8.decode(bytes.takeBytes())) as Map<String, dynamic>;
}

List<String?> _bundleFileRelativePaths(
  AccountMigrationLocalTransferBundle bundle,
) {
  return bundle.manifest.entries
      .where((entry) => entry.kind == MigrationTransferEntryKind.file)
      .map((entry) => entry.relativePath)
      .toList(growable: false);
}

List<String> get _requiredSourceKeys => const [
  MigrationSecureStorageRegistry.dbEncryptionKey,
  MigrationSecureStorageRegistry.identityPrivateKey,
  MigrationSecureStorageRegistry.identityMnemonic12,
  MigrationSecureStorageRegistry.identityMlKemSecretKey,
];

AccountMigrationTransferRequest _request() {
  return AccountMigrationTransferRequest(
    transcript: AuthenticatedMigrationChannelTranscript(
      sessionId: 'session-1',
      newPhoneEphemeralPublicKey: 'new-public-key',
      oldPhonePeerId: 'old-peer',
      authenticatedChannelBinding: 'binding',
      authorizationNonce: 'nonce',
    ),
  );
}

MigrationPendingPairingSession _pendingSession() {
  final createdAt = DateTime.utc(2026, 6, 8, 10);
  return MigrationPendingPairingSession(
    sessionId: 'session-1',
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(minutes: 5)),
    newPhoneEphemeralPublicKey: 'new-public-key',
    newPhoneEphemeralSecretKey: 'new-secret-key',
  );
}

MigrationCutoverRecord _oldBlockProof() {
  final now = DateTime.utc(2026, 6, 8, 11, 59);
  return MigrationCutoverRecord.initial(
    sessionId: 'session-1',
    accountPeerId: 'old-peer',
    devicePeerId: 'old-peer',
    deviceRole: MigrationCutoverDeviceRole.oldPhone,
    now: now,
  ).copyWith(
    phase: MigrationCutoverPhase.oldNetworkBlocked,
    oldNetworkBlocked: true,
    oldNetworkBlockedAt: now,
  );
}

class _RecordingSnapshotExportAdapter
    implements MigrationSqlCipherExportAdapter {
  final Database verificationDb;
  final List<int> snapshotBytes;
  final Future<void> Function(Database db)? onExport;

  _RecordingSnapshotExportAdapter({
    required this.verificationDb,
    required this.snapshotBytes,
    this.onExport,
  });

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
    await onExport?.call(sourceDb);
    await File(destinationPath).writeAsBytes(snapshotBytes, flush: true);
  }

  @override
  Future<Database> openExportedDatabase({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) async {
    return verificationDb;
  }

  @override
  Future<String> runIntegrityCheck(Database db) async => 'ok';
}

class _RecordingStagedDatabaseOpener implements MigrationStagedDatabaseOpener {
  final Database database;

  _RecordingStagedDatabaseOpener({required this.database});

  @override
  Future<Database> open({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) async {
    return database;
  }
}

class _MemoryAuthorityRepository
    implements AccountMigrationAuthorityRepository {
  AccountMigrationAuthorityRecord? saved;

  @override
  Future<void> clearAuthority() async {
    saved = null;
  }

  @override
  Future<AccountMigrationAuthorityRecord?> loadAuthority() async => saved;

  @override
  Future<void> saveAuthority(AccountMigrationAuthorityRecord record) async {
    saved = record;
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
