import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/104_group_exit_diagnostics.dart';
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

    test(
      'PB266-05 same-v104 move transfers allowlisted diagnostics and v103 mismatch preserves target',
      () async {
        await runGroupExitDiagnosticsMigration(activeDb);
        await runGroupExitDiagnosticsMigration(stagedDb);
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

        final manifest = await _manifestFor(stagedDb);
        expect(currentIdentityDatabaseVersion, 104);
        expect(manifest.databaseVersion, 104);
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

        await activeDb.delete('group_exit_diagnostics');
        final targetSentinel = _diagnosticRow(
          groupRef: 'cccccccccccc',
          intentRef: 'cccccccccccccccccccccccc',
        );
        await activeDb.insert('group_exit_diagnostics', targetSentinel);
        final targetBefore = await activeDb.query('group_exit_diagnostics');

        await expectLater(
          MigrationDatabaseActiveImporter(
            activeDatabase: activeDb,
          ).importVerifiedStagedDatabase(
            MigrationDatabaseImportStagingResult(
              database: stagedDb,
              manifest: manifest.copyWith(databaseVersion: 103),
              stagedDatabasePath: p.join(tempDir.path, 'staged.db'),
            ),
          ),
          throwsA(isA<MigrationDatabaseActiveImportException>()),
        );
        expect(await activeDb.query('group_exit_diagnostics'), targetBefore);
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
