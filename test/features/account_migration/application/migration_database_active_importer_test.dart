import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/direct_inbox_custody_outbox_contract.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/104_group_exit_diagnostics.dart';
import 'package:flutter_app/core/database/migrations/108_direct_inbox_custody_outbox.dart';
import 'package:flutter_app/core/database/migrations/116_notification_completed_outcome_outbox.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_active_importer.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_import_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_schema_inventory.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('MigrationDatabaseActiveImporter', () {
    late Directory tempDir;
    late Database activeDb;
    late Database stagedDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mig_active_import_');
      activeDb = await openDatabase(
        p.join(tempDir.path, 'active.db'),
        version: 1,
        singleInstance: false,
      );
      stagedDb = await openDatabase(
        p.join(tempDir.path, 'staged.db'),
        version: 1,
        singleInstance: false,
      );
      await _createSchema(activeDb);
      await _createSchema(stagedDb);
    });

    tearDown(() async {
      if (activeDb.isOpen) {
        await activeDb.close();
      }
      if (stagedDb.isOpen) {
        await stagedDb.close();
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'copies verified staged rows into the already-open active DB',
      () async {
        await activeDb.insert('identity', {
          'id': 1,
          'peer_id': 'new-phone-temp',
          'public_key': 'new-public',
        });
        await activeDb.insert('contacts', {
          'peer_id': 'stale-contact',
          'display_name': 'Stale',
        });
        await stagedDb.insert('identity', {
          'id': 1,
          'peer_id': 'old-peer',
          'public_key': 'old-public',
        });
        await stagedDb.insert('contacts', {
          'peer_id': 'alice-peer',
          'display_name': 'Alice',
        });
        await stagedDb.insert('messages', {
          'id': 'msg-1',
          'contact_peer_id': 'alice-peer',
          'text': 'hello',
        });
        final manifest = await _manifestFor(stagedDb);

        final result =
            await MigrationDatabaseActiveImporter(
              activeDatabase: activeDb,
            ).importVerifiedStagedDatabase(
              MigrationDatabaseImportStagingResult(
                database: stagedDb,
                manifest: manifest,
                stagedDatabasePath: p.join(tempDir.path, 'staged.db'),
              ),
            );

        expect(result.importedTables, ['contacts', 'identity', 'messages']);
        expect(result.importedRows, 3);
        expect(await activeDb.query('identity'), [
          {'id': 1, 'peer_id': 'old-peer', 'public_key': 'old-public'},
        ]);
        expect(await activeDb.query('contacts'), [
          {'peer_id': 'alice-peer', 'display_name': 'Alice'},
        ]);
        expect(
          await MigrationDatabaseImportStaging.computeDatabaseChecksumForTesting(
            activeDb,
          ),
          manifest.databaseChecksumSha256,
        );
      },
    );

    test('refuses schema mismatch without deleting active rows', () async {
      final incompatibleActive = await openDatabase(
        p.join(tempDir.path, 'incompatible-active.db'),
        version: 1,
        singleInstance: false,
      );
      addTearDown(() async {
        if (incompatibleActive.isOpen) {
          await incompatibleActive.close();
        }
      });
      await incompatibleActive.execute('''
CREATE TABLE identity (
  id INTEGER PRIMARY KEY,
  peer_id TEXT NOT NULL
)
''');
      await incompatibleActive.insert('identity', {
        'id': 1,
        'peer_id': 'still-here',
      });
      await stagedDb.insert('identity', {
        'id': 1,
        'peer_id': 'old-peer',
        'public_key': 'old-public',
      });
      final manifest = await _manifestFor(stagedDb);

      await expectLater(
        MigrationDatabaseActiveImporter(
          activeDatabase: incompatibleActive,
        ).importVerifiedStagedDatabase(
          MigrationDatabaseImportStagingResult(
            database: stagedDb,
            manifest: manifest,
            stagedDatabasePath: p.join(tempDir.path, 'staged.db'),
          ),
        ),
        throwsA(isA<MigrationDatabaseActiveImportException>()),
      );

      expect(await incompatibleActive.query('identity'), [
        {'id': 1, 'peer_id': 'still-here'},
      ]);
    });

    test('active trigger cannot mutate imported derived rows', () async {
      await _createDerivedMessageTrigger(activeDb);
      await stagedDb.insert('contacts', {
        'peer_id': 'alice-peer',
        'display_name': 'Alice',
      });
      final manifest = await _manifestFor(stagedDb);

      final result =
          await MigrationDatabaseActiveImporter(
            activeDatabase: activeDb,
          ).importVerifiedStagedDatabase(
            MigrationDatabaseImportStagingResult(
              database: stagedDb,
              manifest: manifest,
              stagedDatabasePath: p.join(tempDir.path, 'staged.db'),
            ),
          );

      expect(result.importedRows, 1);
      expect(await activeDb.query('contacts'), [
        {'peer_id': 'alice-peer', 'display_name': 'Alice'},
      ]);
      expect(await activeDb.query('messages'), isEmpty);
      expect(
        await MigrationDatabaseImportStaging.computeDatabaseChecksumForTesting(
          activeDb,
        ),
        manifest.databaseChecksumSha256,
      );
    });

    test(
      'production current group and direct triggers preserve exact reconciliation rows',
      () async {
        final productionActive = await openDatabase(
          p.join(tempDir.path, 'production-active.db'),
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        final productionStaged = await openDatabase(
          p.join(tempDir.path, 'production-staged.db'),
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        addTearDown(() async {
          if (productionActive.isOpen) await productionActive.close();
          if (productionStaged.isOpen) await productionStaged.close();
        });
        await productionStaged.insert('groups', <String, Object?>{
          'id': 'triggered-group',
          'name': 'Triggered group',
          'type': 'chat',
          'topic_name': '/mknoon/groups/triggered-group',
          'created_at': '2026-08-03T07:00:00.000Z',
          'created_by': 'peer-creator',
          'my_role': 'admin',
        });
        await productionStaged.insert('contacts', <String, Object?>{
          'peer_id': 'direct-trigger-peer',
          'public_key': 'direct-public',
          'rendezvous': 'direct-relay',
          'username': 'Direct peer',
          'signature': 'direct-signature',
          'scanned_at': '2026-08-03T07:00:00.000Z',
        });
        await productionStaged.insert(
          'direct_notification_reaction_terminal_events',
          <String, Object?>{
            'peer_id': 'direct-trigger-peer',
            'message_id': 'same-id',
            'actor_peer_id': 'same-actor',
            'reaction_id': 'direct-reaction',
            'terminal_event_id': 'direct-terminal',
            'notification_acknowledged_at': null,
            'updated_at': '2026-08-03T07:00:00.000Z',
          },
        );
        final manifest = await _manifestFor(productionStaged);
        final stagedReconciliation = await productionStaged.query(
          'group_notification_reconciliation_outbox',
        );
        final stagedDirectReconciliation = await productionStaged.query(
          'direct_notification_reconciliation_outbox',
        );
        expect(stagedReconciliation, hasLength(1));
        expect(stagedDirectReconciliation, hasLength(1));

        await MigrationDatabaseActiveImporter(
          activeDatabase: productionActive,
        ).importVerifiedStagedDatabase(
          MigrationDatabaseImportStagingResult(
            database: productionStaged,
            manifest: manifest,
            stagedDatabasePath: p.join(tempDir.path, 'production-staged.db'),
          ),
        );

        expect(
          await productionActive.query(
            'group_notification_reconciliation_outbox',
          ),
          stagedReconciliation,
        );
        expect(
          await productionActive.query(
            'direct_notification_reconciliation_outbox',
          ),
          stagedDirectReconciliation,
        );
        expect(
          await productionActive.query(
            'direct_notification_reaction_terminal_events',
          ),
          await productionStaged.query(
            'direct_notification_reaction_terminal_events',
          ),
        );
        expect(
          await MigrationDatabaseImportStaging.computeDatabaseChecksumForTesting(
            productionActive,
          ),
          manifest.databaseChecksumSha256,
        );
        expect(
          await productionActive.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' "
            "AND name = 'trg_group_notification_reconcile_group_insert'",
          ),
          hasLength(1),
        );
        expect(
          await productionActive.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' "
            "AND name = 'trg_direct_notification_reconcile_contact_insert'",
          ),
          hasLength(1),
        );
      },
    );

    test(
      'successful exact copy restores active trigger definition and behavior',
      () async {
        await _createDerivedMessageTrigger(activeDb);
        final triggerBefore = await _loadTrigger(activeDb);
        await stagedDb.insert('contacts', {
          'peer_id': 'alice-peer',
          'display_name': 'Alice',
        });
        final manifest = await _manifestFor(stagedDb);

        await MigrationDatabaseActiveImporter(
          activeDatabase: activeDb,
        ).importVerifiedStagedDatabase(
          MigrationDatabaseImportStagingResult(
            database: stagedDb,
            manifest: manifest,
            stagedDatabasePath: p.join(tempDir.path, 'staged.db'),
          ),
        );

        expect(await _loadTrigger(activeDb), triggerBefore);
        expect(await activeDb.query('messages'), isEmpty);

        await activeDb.insert('contacts', {
          'peer_id': 'bob-peer',
          'display_name': 'Bob',
        });
        expect(await activeDb.query('messages'), [
          {
            'id': 'derived-bob-peer',
            'contact_peer_id': 'bob-peer',
            'text': 'derived:Bob',
          },
        ]);
      },
    );

    test(
      'logical checksum mismatch rolls back imported rows and preserves target sentinel',
      () async {
        await _seedActiveSentinel(activeDb);
        await _createDerivedMessageTrigger(activeDb);
        final targetBefore = await _snapshotRows(activeDb);
        final triggerBefore = await _loadTrigger(activeDb);
        await stagedDb.insert('identity', {
          'id': 1,
          'peer_id': 'transferred-peer',
          'public_key': 'transferred-public',
        });
        final manifest = await _manifestFor(stagedDb);

        await expectLater(
          MigrationDatabaseActiveImporter(
            activeDatabase: activeDb,
            activeLogicalChecksum: (_) async => 'forced-mismatch',
          ).importVerifiedStagedDatabase(
            MigrationDatabaseImportStagingResult(
              database: stagedDb,
              manifest: manifest,
              stagedDatabasePath: p.join(tempDir.path, 'staged.db'),
            ),
          ),
          throwsA(
            isA<MigrationDatabaseActiveImportException>().having(
              (error) => error.message,
              'message',
              contains('checksum'),
            ),
          ),
        );

        expect(await _snapshotRows(activeDb), targetBefore);
        expect(await _loadTrigger(activeDb), triggerBefore);
      },
    );

    test(
      'integrity mismatch rolls back imported rows and preserves target sentinel',
      () async {
        await _seedActiveSentinel(activeDb);
        final targetBefore = await _snapshotRows(activeDb);
        await stagedDb.insert('identity', {
          'id': 1,
          'peer_id': 'transferred-peer',
          'public_key': 'transferred-public',
        });
        final manifest = await _manifestFor(stagedDb);

        await expectLater(
          MigrationDatabaseActiveImporter(
            activeDatabase: activeDb,
            activeIntegrityCheck: (_) async => 'forced-integrity-failure',
          ).importVerifiedStagedDatabase(
            MigrationDatabaseImportStagingResult(
              database: stagedDb,
              manifest: manifest,
              stagedDatabasePath: p.join(tempDir.path, 'staged.db'),
            ),
          ),
          throwsA(
            isA<MigrationDatabaseActiveImportException>().having(
              (error) => error.message,
              'message',
              contains('integrity'),
            ),
          ),
        );

        expect(await _snapshotRows(activeDb), targetBefore);
      },
    );

    test(
      'legacy partial-schema fixture follows current manifest and rejects v107 before mutation',
      () async {
        await runGroupExitDiagnosticsMigration(activeDb);
        await runGroupExitDiagnosticsMigration(stagedDb);
        await runDirectInboxCustodyOutboxMigration(activeDb);
        await runDirectInboxCustodyOutboxMigration(stagedDb);
        await activeDb.insert('identity', {
          'id': 1,
          'peer_id': 'active-peer',
          'public_key': 'active-public',
        });
        await activeDb.insert(
          'group_exit_diagnostics',
          _diagnosticRow(
            groupRef: 'aaaaaaaaaaaa',
            intentRef: 'aaaaaaaaaaaaaaaaaaaaaaaa',
          ),
        );
        await stagedDb.insert('identity', {
          'id': 1,
          'peer_id': 'transferred-peer',
          'public_key': 'transferred-public',
        });
        final transferredDiagnostic = _diagnosticRow(
          groupRef: 'bbbbbbbbbbbb',
          intentRef: 'bbbbbbbbbbbbbbbbbbbbbbbb',
        );
        await stagedDb.insert('group_exit_diagnostics', transferredDiagnostic);
        final transferredCustody = _custodyRow(
          recipientPeerId: 'transferred-recipient',
          messageId: 'transferred-message',
          incarnationId: '1234567890abcdef1234567890abcdef',
          wireEnvelope: '{"type":"chat_message","id":"transferred-message"}',
        );
        await stagedDb.insert(
          'direct_inbox_custody_outbox',
          transferredCustody,
        );

        final manifest = await _manifestFor(stagedDb);
        expect(currentIdentityDatabaseVersion, 118);
        expect(manifest.databaseVersion, 117);
        final result =
            await MigrationDatabaseActiveImporter(
              activeDatabase: activeDb,
            ).importVerifiedStagedDatabase(
              MigrationDatabaseImportStagingResult(
                database: stagedDb,
                manifest: manifest,
                stagedDatabasePath: p.join(tempDir.path, 'staged.db'),
              ),
            );

        expect(result.importedTables, contains('group_exit_diagnostics'));
        expect(
          await activeDb.query('group_exit_diagnostics'),
          <Map<String, Object?>>[
            {'id': 1, ...transferredDiagnostic},
          ],
        );
        expect(
          await activeDb.query('direct_inbox_custody_outbox'),
          <Map<String, Object?>>[transferredCustody],
        );

        await activeDb.delete('group_exit_diagnostics');
        await activeDb.delete('direct_inbox_custody_outbox');
        final targetSentinel = _diagnosticRow(
          groupRef: 'cccccccccccc',
          intentRef: 'cccccccccccccccccccccccc',
        );
        await activeDb.insert('group_exit_diagnostics', targetSentinel);
        final targetCustodySentinel = _custodyRow(
          recipientPeerId: 'target-recipient',
          messageId: 'target-message',
          incarnationId: 'fedcba0987654321fedcba0987654321',
          wireEnvelope: '{"type":"chat_message","id":"target-message"}',
        );
        await activeDb.insert(
          'direct_inbox_custody_outbox',
          targetCustodySentinel,
        );
        final targetBefore = await activeDb.query('group_exit_diagnostics');
        final targetCustodyBefore = await activeDb.query(
          'direct_inbox_custody_outbox',
        );

        await expectLater(
          MigrationDatabaseActiveImporter(
            activeDatabase: activeDb,
          ).importVerifiedStagedDatabase(
            MigrationDatabaseImportStagingResult(
              database: stagedDb,
              manifest: manifest.copyWith(databaseVersion: 107),
              stagedDatabasePath: p.join(tempDir.path, 'staged.db'),
            ),
          ),
          throwsA(
            isA<MigrationDatabaseActiveImportException>().having(
              (error) => error.message,
              'message',
              contains('unsupportedDatabaseVersion'),
            ),
          ),
        );
        expect(await activeDb.query('group_exit_diagnostics'), targetBefore);
        expect(
          await activeDb.query('direct_inbox_custody_outbox'),
          targetCustodyBefore,
        );
      },
    );

    test(
      'TC-343-08b production-current transfer preserves two pending reaction transitions and v108 rejection leaves target unchanged',
      () async {
        final productionActive = await openDatabase(
          p.join(tempDir.path, 'tc343-production-active.db'),
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        final productionStaged = await openDatabase(
          p.join(tempDir.path, 'tc343-production-staged.db'),
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        addTearDown(() async {
          if (productionActive.isOpen) await productionActive.close();
          if (productionStaged.isOpen) await productionStaged.close();
        });

        expect(await _userVersion(productionActive), 118);
        expect(await _userVersion(productionStaged), 118);
        final activeInventory =
            await MigrationDatabaseSchemaInventory.fromDatabase(
              productionActive,
            );
        final stagedInventory =
            await MigrationDatabaseSchemaInventory.fromDatabase(
              productionStaged,
            );
        expect(activeInventory.schemaHash, stagedInventory.schemaHash);
        expect(
          activeInventory.tableNames,
          containsAll(<String>[
            'identity',
            'messages',
            'message_reactions',
            'direct_inbox_custody_outbox',
            'direct_reaction_inbox_custody_outbox',
          ]),
        );

        final addRow = _reactionCustodyRow(
          eventId: 'transfer-reaction-add',
          envelope: '{"event":"add","cipher":"exact-a"}',
          createdAt: '2026-08-07T06:00:00.000Z',
        );
        final removeRow = _reactionCustodyRow(
          eventId: 'transfer-reaction-remove',
          envelope: '{"event":"remove","cipher":"exact-b"}',
          createdAt: '2026-08-07T06:00:01.000Z',
        );
        await productionStaged.insert(
          'direct_reaction_inbox_custody_outbox',
          addRow,
        );
        await productionStaged.insert(
          'direct_reaction_inbox_custody_outbox',
          removeRow,
        );
        final manifest = await _manifestFor(productionStaged);
        expect(manifest.databaseVersion, 117);
        expect(manifest.schemaInventory.schemaHash, stagedInventory.schemaHash);

        await MigrationDatabaseActiveImporter(
          activeDatabase: productionActive,
        ).importVerifiedStagedDatabase(
          MigrationDatabaseImportStagingResult(
            database: productionStaged,
            manifest: manifest,
            stagedDatabasePath: p.join(
              tempDir.path,
              'tc343-production-staged.db',
            ),
          ),
        );
        expect(
          await productionActive.query(
            'direct_reaction_inbox_custody_outbox',
            orderBy: 'created_at ASC',
          ),
          <Map<String, Object?>>[addRow, removeRow],
        );

        await productionActive.delete('direct_reaction_inbox_custody_outbox');
        final targetSentinel = _reactionCustodyRow(
          eventId: 'target-must-survive-v108-rejection',
          envelope: '{"target":"unchanged"}',
          createdAt: '2026-08-07T06:01:00.000Z',
        );
        await productionActive.insert(
          'direct_reaction_inbox_custody_outbox',
          targetSentinel,
        );
        final targetBefore = await _snapshotAllProductionRows(productionActive);

        await expectLater(
          MigrationDatabaseActiveImporter(
            activeDatabase: productionActive,
          ).importVerifiedStagedDatabase(
            MigrationDatabaseImportStagingResult(
              database: productionStaged,
              manifest: manifest.copyWith(databaseVersion: 108),
              stagedDatabasePath: p.join(
                tempDir.path,
                'tc343-production-staged.db',
              ),
            ),
          ),
          throwsA(
            isA<MigrationDatabaseActiveImportException>().having(
              (error) => error.message,
              'message',
              contains('unsupportedDatabaseVersion'),
            ),
          ),
        );
        expect(
          await _snapshotAllProductionRows(productionActive),
          targetBefore,
        );
      },
    );

    test(
      'TC-345-10 production-v110 transfer preserves pending and outbox-only media custody',
      () async {
        final productionActive = await openDatabase(
          p.join(tempDir.path, 'tc345-production-active.db'),
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        final productionStaged = await openDatabase(
          p.join(tempDir.path, 'tc345-production-staged.db'),
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        addTearDown(() async {
          if (productionActive.isOpen) await productionActive.close();
          if (productionStaged.isOpen) await productionStaged.close();
        });

        expect(await _userVersion(productionActive), 118);
        expect(await _userVersion(productionStaged), 118);

        const pendingMessageId = 'tc345-transfer-pending';
        const pendingAttachmentId = 'tc345-transfer-pending-media';
        const pendingIntent = '11111111111111111111111111111111';
        await productionStaged.insert(
          'messages',
          _productionMessageRow(
            messageId: pendingMessageId,
            status: 'sending',
            directMediaCustodyIntentId: pendingIntent,
          ),
        );
        await productionStaged.insert(
          'media_attachments',
          _productionMediaRow(
            attachmentId: pendingAttachmentId,
            messageId: pendingMessageId,
            downloadStatus: 'upload_pending',
          ),
        );

        const completedMessageId = 'tc345-transfer-completed';
        const completedAttachmentId = 'tc345-transfer-completed-media';
        const completedEnvelope =
            '{"type":"chat_message","version":"2",'
            '"id":"tc345-transfer-completed","senderPeerId":"transfer-self",'
            '"encrypted":{"kem":"kem-completed",'
            '"ciphertext":"exact-completed","nonce":"nonce-completed"}}';
        const completedIncarnation = '22222222222222222222222222222222';
        await productionStaged.insert(
          'messages',
          _productionMessageRow(
            messageId: completedMessageId,
            status: 'sending',
            wireEnvelope: completedEnvelope,
          ),
        );
        await productionStaged.insert(
          'media_attachments',
          _productionMediaRow(
            attachmentId: completedAttachmentId,
            messageId: completedMessageId,
            downloadStatus: 'done',
            completed: true,
          ),
        );
        await productionStaged.insert(
          'direct_inbox_custody_outbox',
          _custodyRow(
            recipientPeerId: 'transfer-recipient',
            messageId: completedMessageId,
            incarnationId: completedIncarnation,
            wireEnvelope: completedEnvelope,
          ),
        );

        const removedMessageId = 'tc345-transfer-removed';
        const removedAttachmentId = 'tc345-transfer-removed-media';
        const removedEnvelope =
            '{"type":"chat_message","version":"2",'
            '"id":"tc345-transfer-removed","senderPeerId":"transfer-self",'
            '"encrypted":{"kem":"kem-removed",'
            '"ciphertext":"exact-removed","nonce":"nonce-removed"}}';
        const removedIncarnation = '33333333333333333333333333333333';
        await productionStaged.insert(
          'messages',
          _productionMessageRow(
            messageId: removedMessageId,
            status: 'sending',
            wireEnvelope: removedEnvelope,
          ),
        );
        await productionStaged.insert(
          'media_attachments',
          _productionMediaRow(
            attachmentId: removedAttachmentId,
            messageId: removedMessageId,
            downloadStatus: 'done',
            completed: true,
          ),
        );
        await productionStaged.insert(
          'direct_inbox_custody_outbox',
          _custodyRow(
            recipientPeerId: 'transfer-recipient',
            messageId: removedMessageId,
            incarnationId: removedIncarnation,
            wireEnvelope: removedEnvelope,
          ),
        );
        await productionStaged.delete(
          'media_attachments',
          where: 'message_id = ?',
          whereArgs: const <Object?>[removedMessageId],
        );
        await productionStaged.delete(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[removedMessageId],
        );

        final expectedMessages = await productionStaged.query(
          'messages',
          orderBy: 'id',
        );
        final expectedMedia = await productionStaged.query(
          'media_attachments',
          orderBy: 'id',
        );
        final expectedCustody = await productionStaged.query(
          'direct_inbox_custody_outbox',
          orderBy: 'message_id',
        );
        final manifest = await _manifestFor(productionStaged);
        expect(manifest.databaseVersion, 117);

        final result =
            await MigrationDatabaseActiveImporter(
              activeDatabase: productionActive,
            ).importVerifiedStagedDatabase(
              MigrationDatabaseImportStagingResult(
                database: productionStaged,
                manifest: manifest,
                stagedDatabasePath: p.join(
                  tempDir.path,
                  'tc345-production-staged.db',
                ),
              ),
            );
        expect(result.importedTables, contains('media_attachments'));
        expect(result.importedTables, contains('direct_inbox_custody_outbox'));
        expect(
          await productionActive.query('messages', orderBy: 'id'),
          expectedMessages,
        );
        expect(
          await productionActive.query('media_attachments', orderBy: 'id'),
          expectedMedia,
        );
        expect(
          await productionActive.query(
            'direct_inbox_custody_outbox',
            orderBy: 'message_id',
          ),
          expectedCustody,
        );
        expect(
          (await productionActive.query(
            'messages',
            columns: const <String>['direct_media_custody_intent_id'],
            where: 'id = ?',
            whereArgs: const <Object?>[pendingMessageId],
          )).single['direct_media_custody_intent_id'],
          pendingIntent,
        );
        expect(
          await productionActive.query(
            'messages',
            where: 'id = ?',
            whereArgs: const <Object?>[removedMessageId],
          ),
          isEmpty,
        );
        expect(
          await dbCompleteAcceptedDirectInboxCustodyIfExact(
            productionActive,
            recipientPeerId: 'transfer-recipient',
            messageId: removedMessageId,
            expectedIncarnationId: removedIncarnation,
            expectedWireEnvelope: removedEnvelope,
            relayExpiresAt: 1999999999000,
          ),
          DirectInboxCustodyCompletionOutcome.messageRemoved,
        );

        final targetBeforeV109Refusal = await _snapshotAllProductionRows(
          productionActive,
        );
        await expectLater(
          MigrationDatabaseActiveImporter(
            activeDatabase: productionActive,
          ).importVerifiedStagedDatabase(
            MigrationDatabaseImportStagingResult(
              database: productionStaged,
              manifest: manifest.copyWith(databaseVersion: 109),
              stagedDatabasePath: p.join(
                tempDir.path,
                'tc345-production-staged.db',
              ),
            ),
          ),
          throwsA(
            isA<MigrationDatabaseActiveImportException>().having(
              (error) => error.message,
              'message',
              contains('unsupportedDatabaseVersion'),
            ),
          ),
        );
        expect(
          await _snapshotAllProductionRows(productionActive),
          targetBeforeV109Refusal,
        );
      },
    );

    test(
      'TC-347-07 production transfer preserves v111 rows and exact v108 binding',
      () async {
        final productionActive = await openDatabase(
          p.join(tempDir.path, 'tc347-production-active.db'),
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        final productionStaged = await openDatabase(
          p.join(tempDir.path, 'tc347-production-staged.db'),
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        addTearDown(() async {
          if (productionActive.isOpen) await productionActive.close();
          if (productionStaged.isOpen) await productionStaged.close();
        });

        expect(await _userVersion(productionActive), 118);
        expect(await _userVersion(productionStaged), 118);

        const incarnation = '34734734734734734734734734734734';
        const manifestHash =
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
        const expiresAtMs = 2000000000000;
        final boundV108 = <String, Object?>{
          ..._custodyRow(
            recipientPeerId: 'transfer-recipient',
            messageId: 'message-347',
            incarnationId: incarnation,
            wireEnvelope: '{"type":"chat_message","id":"message-347"}',
          ),
          'media_blob_expires_at_ms': expiresAtMs,
          'media_blob_manifest_hash': manifestHash,
        };
        await productionStaged.insert('direct_inbox_custody_outbox', boundV108);
        await productionStaged.insert(
          'direct_media_blob_custody',
          _outgoingBlobCustodyRow(
            attachmentId: 'outgoing-attachment-347',
            messageId: 'message-347',
            incarnationId: incarnation,
            expiresAtMs: expiresAtMs,
          ),
        );
        await productionStaged.insert(
          'direct_media_blob_custody',
          _incomingBlobCustodyRow(
            attachmentId: 'incoming-attachment-347',
            messageId: 'incoming-message-347',
            expiresAtMs: expiresAtMs,
          ),
        );

        final expectedV108 = await productionStaged.query(
          'direct_inbox_custody_outbox',
          orderBy: 'message_id',
        );
        final expectedV111 = await productionStaged.query(
          'direct_media_blob_custody',
          orderBy: 'attachment_id',
        );
        final manifest = await _manifestFor(productionStaged);
        expect(manifest.databaseVersion, 117);
        expect(
          manifest.schemaInventory.tables['direct_media_blob_custody'],
          isNotEmpty,
        );
        expect(
          manifest.schemaInventory.hasColumn(
            'direct_inbox_custody_outbox',
            'media_blob_manifest_hash',
          ),
          isTrue,
        );

        final result =
            await MigrationDatabaseActiveImporter(
              activeDatabase: productionActive,
            ).importVerifiedStagedDatabase(
              MigrationDatabaseImportStagingResult(
                database: productionStaged,
                manifest: manifest,
                stagedDatabasePath: p.join(
                  tempDir.path,
                  'tc347-production-staged.db',
                ),
              ),
            );

        expect(result.importedTables, contains('direct_media_blob_custody'));
        expect(
          await productionActive.query(
            'direct_inbox_custody_outbox',
            orderBy: 'message_id',
          ),
          expectedV108,
        );
        expect(
          await productionActive.query(
            'direct_media_blob_custody',
            orderBy: 'attachment_id',
          ),
          expectedV111,
        );

        final targetBeforeRefusal = await _snapshotAllProductionRows(
          productionActive,
        );
        await expectLater(
          MigrationDatabaseActiveImporter(
            activeDatabase: productionActive,
          ).importVerifiedStagedDatabase(
            MigrationDatabaseImportStagingResult(
              database: productionStaged,
              manifest: manifest.copyWith(databaseVersion: 110),
              stagedDatabasePath: p.join(
                tempDir.path,
                'tc347-production-staged.db',
              ),
            ),
          ),
          throwsA(
            isA<MigrationDatabaseActiveImportException>().having(
              (error) => error.message,
              'message',
              contains('unsupportedDatabaseVersion'),
            ),
          ),
        );
        expect(
          await _snapshotAllProductionRows(productionActive),
          targetBeforeRefusal,
        );
      },
    );

    test('TC-360-01b v112 remote roster migrates while linked installation '
        'authority cannot move', () async {
      final productionActive = await openDatabase(
        p.join(tempDir.path, 'tc360-production-active.db'),
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      );
      final productionStaged = await openDatabase(
        p.join(tempDir.path, 'tc360-production-staged.db'),
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      );
      addTearDown(() async {
        if (productionActive.isOpen) await productionActive.close();
        if (productionStaged.isOpen) await productionStaged.close();
      });

      expect(await _userVersion(productionActive), 118);
      expect(await _userVersion(productionStaged), 118);

      const contactPeerId =
          '12D3KooWP7CwQswqLKZbwvYd9wrEynnL9F2aKVP1X9huNASBTuqj';
      const contactPublicKey = 'xXheGGW3CJOK/4Fh1XMAZJZmOxqhCDTjltxWaGmixmo=';
      const transportPeerId =
          '12D3KooWPCyWnZCXR3VGdrQjLr5d8TBaAHD956XZvo6xoCXYB5AR';
      const transportPublicKey = 'xvKsVZiXDHljNxTT61w017/D6S2ljHNUs3mW2aSvOrI=';
      const timestamp = '2026-08-11T12:00:00.000Z';

      // A REMOTE-CONTACT roster: this is account data, and it must move with
      // the account. Losing it on a Move would silently drop every device a
      // user explicitly verified, quietly reverting them to legacy-only
      // addressing without any decision being recorded.
      await productionStaged.insert('contacts', <String, Object?>{
        'peer_id': contactPeerId,
        'public_key': contactPublicKey,
        'rendezvous': '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
        'username': 'Alice',
        'signature': 'sig-alice',
        'scanned_at': timestamp,
        'ml_kem_public_key': 'legacy-mlkem',
      });
      await productionStaged
          .insert('direct_contact_device_bindings', <String, Object?>{
            'contact_account_peer_id': contactPeerId,
            'device_id': 'device-alpha',
            'verified_account_signing_public_key': contactPublicKey,
            'transport_peer_id': transportPeerId,
            'transport_public_key': transportPublicKey,
            'device_ml_kem_public_key': 'device-mlkem',
            'binding_fingerprint': 'a' * 64,
            'state': 'active',
            'staged_at': timestamp,
            'decided_at': timestamp,
          });
      await productionStaged
          .insert('direct_contact_device_roster_metadata', <String, Object?>{
            'contact_account_peer_id': contactPeerId,
            'roster_initialized': 1,
            'legacy_target_state': 'active',
            'initialized_at': timestamp,
            'legacy_revoked_at': null,
            'updated_at': timestamp,
          });

      final expectedBindings = await productionStaged.query(
        'direct_contact_device_bindings',
        orderBy: 'device_id',
      );
      final expectedMetadata = await productionStaged.query(
        'direct_contact_device_roster_metadata',
        orderBy: 'contact_account_peer_id',
      );

      final manifest = await _manifestFor(productionStaged);
      expect(manifest.databaseVersion, 117);
      expect(
        manifest.schemaInventory.tables['direct_contact_device_bindings'],
        isNotEmpty,
      );
      expect(
        manifest
            .schemaInventory
            .tables['direct_contact_device_roster_metadata'],
        isNotEmpty,
      );

      final result =
          await MigrationDatabaseActiveImporter(
            activeDatabase: productionActive,
          ).importVerifiedStagedDatabase(
            MigrationDatabaseImportStagingResult(
              database: productionStaged,
              manifest: manifest,
              stagedDatabasePath: p.join(
                tempDir.path,
                'tc360-production-staged.db',
              ),
            ),
          );

      expect(
        result.importedTables,
        containsAll(<String>[
          'direct_contact_device_bindings',
          'direct_contact_device_roster_metadata',
        ]),
      );
      expect(
        await productionActive.query(
          'direct_contact_device_bindings',
          orderBy: 'device_id',
        ),
        expectedBindings,
      );
      expect(
        await productionActive.query(
          'direct_contact_device_roster_metadata',
          orderBy: 'contact_account_peer_id',
        ),
        expectedMetadata,
      );

      // The installation's OWN linked role and transport credential are
      // secure-storage records, so they have no schema presence at all:
      // imported DB data can never create or promote a local linked role.
      expect(
        manifest.schemaInventory.tableNames,
        isNot(
          anyElement(
            anyOf(
              contains('linked_installation'),
              contains('transport_credential'),
            ),
          ),
        ),
      );
    });

    test(
      'TC-369-01 active import never transfers completed outcomes',
      () async {
        await activeDb.close();
        await stagedDb.close();
        activeDb = await openDatabase(
          p.join(tempDir.path, 'tc369-active.db'),
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        stagedDb = await openDatabase(
          p.join(tempDir.path, 'tc369-staged.db'),
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        await activeDb.insert(
          kNotificationCompletedOutcomeOutboxTable,
          _completedOutcomeRow('a'),
        );
        await stagedDb.insert(
          kNotificationCompletedOutcomeOutboxTable,
          _completedOutcomeRow('b'),
        );
        final manifest = await _manifestFor(stagedDb);
        var expectedPortableRows = 0;
        for (final tableName
            in manifest.schemaInventory.transferableTableNames) {
          expectedPortableRows +=
              (await stagedDb.rawQuery(
                    'SELECT COUNT(*) FROM "$tableName"',
                  )).single.values.single
                  as int;
        }

        final result =
            await MigrationDatabaseActiveImporter(
              activeDatabase: activeDb,
            ).importVerifiedStagedDatabase(
              MigrationDatabaseImportStagingResult(
                database: stagedDb,
                manifest: manifest,
                stagedDatabasePath: p.join(tempDir.path, 'tc369-staged.db'),
              ),
            );

        expect(
          await stagedDb.query(kNotificationCompletedOutcomeOutboxTable),
          hasLength(1),
          reason: 'the verified source remains immutable during active import',
        );
        expect(
          await activeDb.query(kNotificationCompletedOutcomeOutboxTable),
          isEmpty,
          reason: 'stale destination and transferred sibling authority clear',
        );
        expect(
          result.importedTables,
          isNot(contains(kNotificationCompletedOutcomeOutboxTable)),
        );
        expect(result.importedRows, expectedPortableRows);
      },
    );
  });
}

Map<String, Object?> _completedOutcomeRow(String seed) => <String, Object?>{
  'wake_correlation': seed * 64,
  'outcome': 'os_posted',
  'revision': 1,
  'retry_count': 0,
  'last_error_code': null,
  'last_attempt_at': null,
  'next_attempt_at': null,
  'completed_at': '2026-08-15T12:00:00.000Z',
  'created_at': '2026-08-15T12:00:00.000Z',
  'expires_at': '2026-08-22T12:00:00.000Z',
};

Map<String, Object?> _diagnosticRow({
  required String groupRef,
  required String intentRef,
}) => <String, Object?>{
  'occurred_at': '2026-07-21T09:03:00.000Z',
  'group_ref': groupRef,
  'intent_ref': intentRef,
  'exit_kind': 'voluntary',
  'severity': 'failure',
  'phase': 'native',
  'public_code': 'EX04',
  'reason_code': 'node_not_initialized',
};

Map<String, Object?> _custodyRow({
  required String recipientPeerId,
  required String messageId,
  required String incarnationId,
  required String wireEnvelope,
}) => <String, Object?>{
  'recipient_peer_id': recipientPeerId,
  'message_id': messageId,
  'incarnation_id': incarnationId,
  'wire_envelope': wireEnvelope,
  'retry_count': 2,
  'last_attempt_at': '2026-08-06T10:00:00.000Z',
  'last_error_code': 'store_failed',
  'created_at': '2026-08-06T09:00:00.000Z',
  'updated_at': '2026-08-06T10:00:00.000Z',
};

Map<String, Object?> _reactionCustodyRow({
  required String eventId,
  required String envelope,
  required String createdAt,
}) => <String, Object?>{
  'recipient_peer_id': 'transfer-recipient',
  'event_id': eventId,
  'wire_envelope': envelope,
  'retry_count': 0,
  'last_attempt_at': null,
  'last_error_code': null,
  // 361: DB v113 nullable fanout facts transfer verbatim (null for legacy).
  'contact_account_peer_id': null,
  'parent_message_id': null,
  'created_at': createdAt,
  'updated_at': createdAt,
};

Map<String, Object?> _outgoingBlobCustodyRow({
  required String attachmentId,
  required String messageId,
  required String incarnationId,
  required int expiresAtMs,
}) => <String, Object?>{
  'attachment_id': attachmentId,
  'message_id': messageId,
  'owner_lane': 'direct',
  'custody_blob_id': attachmentId,
  'direction': 'outgoing',
  'state': 'outgoing_stored',
  'inbox_custody_incarnation_id': incarnationId,
  'recipient_peer_id': 'transfer-recipient',
  'ciphertext_relative_path':
      'direct_media_blob_custody_v1/${'a' * 64}/outgoing.blob',
  'custody_kind': 'direct_media_blob_v1',
  'custody_contract': 'ack_or_expiry_v1',
  'content_hash': 'd' * 64,
  'ciphertext_size': 347,
  'transport_mime': 'application/octet-stream',
  'expires_at_ms': expiresAtMs,
  'custody_relay_peer_id': 'relay-transfer',
  'retry_count': 0,
  'last_attempt_at': null,
  'next_attempt_at': null,
  'created_at': '2026-08-08T10:00:00.000Z',
  'updated_at': '2026-08-08T10:01:00.000Z',
};

Map<String, Object?> _incomingBlobCustodyRow({
  required String attachmentId,
  required String messageId,
  required int expiresAtMs,
}) => <String, Object?>{
  'attachment_id': attachmentId,
  'message_id': messageId,
  'owner_lane': 'direct',
  'custody_blob_id': attachmentId,
  'direction': 'incoming',
  'state': 'incoming_ack_pending',
  'inbox_custody_incarnation_id': null,
  'recipient_peer_id': null,
  'ciphertext_relative_path': null,
  'custody_kind': 'direct_media_blob_v1',
  'custody_contract': 'ack_or_expiry_v1',
  'content_hash': 'e' * 64,
  'ciphertext_size': 743,
  'transport_mime': 'application/octet-stream',
  'expires_at_ms': expiresAtMs,
  'custody_relay_peer_id': 'relay-source',
  'retry_count': 1,
  'last_attempt_at': '2026-08-08T10:02:00.000Z',
  'next_attempt_at': '2026-08-08T10:03:00.000Z',
  'created_at': '2026-08-08T10:00:00.000Z',
  'updated_at': '2026-08-08T10:02:00.000Z',
};

Map<String, Object?> _productionMessageRow({
  required String messageId,
  required String status,
  String? wireEnvelope,
  String? directMediaCustodyIntentId,
}) => <String, Object?>{
  'id': messageId,
  'contact_peer_id': 'transfer-recipient',
  'sender_peer_id': 'transfer-self',
  'text': 'opaque media message',
  'timestamp': '2026-08-07T12:00:00.000Z',
  'status': status,
  'is_incoming': 0,
  'created_at': '2026-08-07T12:00:00.000Z',
  'wire_envelope': wireEnvelope,
  'direct_media_custody_intent_id': directMediaCustodyIntentId,
};

Map<String, Object?> _productionMediaRow({
  required String attachmentId,
  required String messageId,
  required String downloadStatus,
  bool completed = false,
}) => <String, Object?>{
  'id': attachmentId,
  'message_id': messageId,
  'mime': 'image/jpeg',
  'size': 345,
  'media_type': 'image',
  'local_path': 'media/$messageId/$attachmentId.jpg',
  'download_status': downloadStatus,
  'created_at': '2026-08-07T12:00:00.000Z',
  'content_hash': completed
      ? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      : null,
  'encryption_key_base64': completed
      ? 'secure:media_attachment_encryption_key:$attachmentId'
      : null,
  'encryption_nonce': completed ? 'nonce-$attachmentId' : null,
  'encryption_scheme': completed ? 'blob_aes_256_gcm_v1' : null,
  'owner_lane': 'direct',
};

Future<void> _createSchema(Database db) async {
  await db.execute('''
CREATE TABLE identity (
  id INTEGER PRIMARY KEY,
  peer_id TEXT NOT NULL,
  public_key TEXT NOT NULL
)
''');
  await db.execute('''
CREATE TABLE contacts (
  peer_id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL
)
''');
  await db.execute('''
CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  contact_peer_id TEXT NOT NULL,
  text TEXT NOT NULL
)
''');
}

Future<void> _createDerivedMessageTrigger(Database db) {
  return db.execute('''
CREATE TRIGGER contacts_derive_message
AFTER INSERT ON contacts
BEGIN
  INSERT INTO messages(id, contact_peer_id, text)
  VALUES (
    'derived-' || NEW.peer_id,
    NEW.peer_id,
    'derived:' || NEW.display_name
  );
END
''');
}

Future<Map<String, Object?>> _loadTrigger(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name, sql FROM sqlite_master WHERE type = 'trigger' AND name = ?",
    <Object?>['contacts_derive_message'],
  );
  return rows.single;
}

Future<void> _seedActiveSentinel(Database db) async {
  await db.insert('identity', {
    'id': 1,
    'peer_id': 'target-sentinel',
    'public_key': 'target-public',
  });
  await db.insert('contacts', {
    'peer_id': 'sentinel-contact',
    'display_name': 'Sentinel',
  });
  await db.insert('messages', {
    'id': 'sentinel-message',
    'contact_peer_id': 'sentinel-contact',
    'text': 'keep me',
  });
}

Future<Map<String, List<Map<String, Object?>>>> _snapshotRows(
  Database db,
) async {
  return <String, List<Map<String, Object?>>>{
    'contacts': await db.query('contacts', orderBy: 'peer_id'),
    'identity': await db.query('identity', orderBy: 'id'),
    'messages': await db.query('messages', orderBy: 'id'),
  };
}

Future<Map<String, List<Map<String, Object?>>>> _snapshotAllProductionRows(
  Database db,
) async {
  final inventory = await MigrationDatabaseSchemaInventory.fromDatabase(db);
  return <String, List<Map<String, Object?>>>{
    for (final tableName in inventory.tableNames)
      tableName: await db.query(tableName),
  };
}

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return (rows.single.values.single as num).toInt();
}

Future<MigrationDatabaseManifest> _manifestFor(Database db) async {
  final inventory = await MigrationDatabaseSchemaInventory.fromDatabase(db);
  return MigrationDatabaseManifest.current(
    sourceAppVersion: '1.2.3',
    sourceBuildNumber: '456',
    schemaInventory: inventory,
    databaseChecksumSha256:
        await MigrationDatabaseImportStaging.computeDatabaseChecksumForTesting(
          db,
        ),
    cipherMetadata: const MigrationDatabaseCipherMetadata(
      cipherVersion: '4.6.0',
      policy: MigrationDatabaseCipherPolicy.compatible,
    ),
  );
}
