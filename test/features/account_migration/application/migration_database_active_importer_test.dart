import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/104_group_exit_diagnostics.dart';
import 'package:flutter_app/core/database/migrations/108_direct_inbox_custody_outbox.dart';
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
      'TC-342-10b same-v108 transfer preserves pending custody and v107 rejection leaves target unchanged',
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
        expect(currentIdentityDatabaseVersion, 108);
        expect(manifest.databaseVersion, 108);
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
  });
}

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
