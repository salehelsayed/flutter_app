import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/116_notification_completed_outcome_outbox.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('MigrationDatabaseSnapshotExporter', () {
    Directory? tempDir;
    Database? sourceDb;
    Database? exportedDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mig004_exporter_');
      sourceDb = await openDatabase(
        p.join(tempDir!.path, 'source.db'),
        version: 1,
        singleInstance: false,
      );
      exportedDb = await openDatabase(
        p.join(tempDir!.path, 'exported.db'),
        version: 1,
        singleInstance: false,
      );
      await _createSeededAccountDb(sourceDb!);
      await _createSeededAccountDb(exportedDb!);
    });

    tearDown(() async {
      final currentSourceDb = sourceDb;
      final currentExportedDb = exportedDb;
      final currentTempDir = tempDir;
      sourceDb = null;
      exportedDb = null;
      tempDir = null;
      if (currentSourceDb != null && currentSourceDb.isOpen) {
        await currentSourceDb.close();
      }
      if (currentExportedDb != null && currentExportedDb.isOpen) {
        await currentExportedDb.close();
      }
      if (currentTempDir != null && await currentTempDir.exists()) {
        await currentTempDir.delete(recursive: true);
      }
    });

    test(
      'exports through SQLCipher adapter, computes checksum, and verifies schema',
      () async {
        final adapter = RecordingSnapshotExportAdapter(
          verificationDb: exportedDb!,
          bytesToWrite: List<int>.filled(64, 7),
        );
        final exporter = MigrationDatabaseSnapshotExporter(adapter: adapter);
        final outputPath = p.join(tempDir!.path, 'identity.snapshot.db');

        final result = await exporter.exportSnapshot(
          sourceDb: sourceDb!,
          destinationPath: outputPath,
          destinationKey: 'staged-db-key',
          sourceAppVersion: '1.2.3',
          sourceBuildNumber: '456',
        );

        expect(adapter.commands, [
          'captureCipherMetadata',
          'sqlcipherExport',
          'openExportedDatabase',
        ]);
        expect(adapter.exportDestinationPath, outputPath);
        expect(adapter.exportDestinationKey, 'staged-db-key');
        expect(File(outputPath).existsSync(), isTrue);
        expect(result.manifest.databaseChecksumSha256, hasLength(64));
        expect(
          result.manifest.schemaInventory.hasColumn('identity', 'private_key'),
          isTrue,
        );
        expect(exportedDb!.isOpen, isFalse);
      },
    );

    test(
      'rejects an exported DB that fails integrity/schema verification',
      () async {
        final adapter = RecordingSnapshotExportAdapter(
          verificationDb: exportedDb!,
          bytesToWrite: List<int>.filled(64, 9),
          integrityResult: 'database disk image is malformed',
        );
        final exporter = MigrationDatabaseSnapshotExporter(adapter: adapter);

        await expectLater(
          exporter.exportSnapshot(
            sourceDb: sourceDb!,
            destinationPath: p.join(tempDir!.path, 'bad.snapshot.db'),
            destinationKey: 'staged-db-key',
            sourceAppVersion: '1.2.3',
            sourceBuildNumber: '456',
          ),
          throwsA(isA<MigrationDatabaseSnapshotExportException>()),
        );
      },
    );

    test(
      'TC-369-01 exported snapshot carries empty outcome authority',
      () async {
        await sourceDb!.close();
        await exportedDb!.close();
        sourceDb = await openDatabase(
          p.join(tempDir!.path, 'v116-source.db'),
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        exportedDb = await openDatabase(
          p.join(tempDir!.path, 'v116-export-copy.db'),
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        await sourceDb!.insert(
          kNotificationCompletedOutcomeOutboxTable,
          _outcomeRow('a'),
        );
        await exportedDb!.insert(
          kNotificationCompletedOutcomeOutboxTable,
          _outcomeRow('a'),
        );
        final outputPath = p.join(tempDir!.path, 'v116.snapshot.db');
        final exporter = MigrationDatabaseSnapshotExporter(
          adapter: RecordingSnapshotExportAdapter(
            verificationDb: exportedDb!,
            bytesToWrite: List<int>.filled(64, 11),
          ),
          closeExportedDatabaseAfterValidation: false,
        );

        final result = await exporter.exportSnapshot(
          sourceDb: sourceDb!,
          destinationPath: outputPath,
          destinationKey: 'staged-db-key',
          sourceAppVersion: '1.2.3',
          sourceBuildNumber: '456',
        );

        expect(
          await sourceDb!.query(kNotificationCompletedOutcomeOutboxTable),
          hasLength(1),
          reason: 'sanitizing a copied snapshot cannot mutate the live DB',
        );
        expect(
          await exportedDb!.query(kNotificationCompletedOutcomeOutboxTable),
          isEmpty,
        );
        expect(
          result.manifest.schemaInventory.tables.containsKey(
            kNotificationCompletedOutcomeOutboxTable,
          ),
          isTrue,
          reason: 'the current-version empty schema remains transferable',
        );
      },
    );

    test(
      'runs sqlcipher_export through rawQuery for Android sqflite',
      () async {
        final db = RecordingSqlCipherExportDatabase();
        const adapter = DefaultMigrationSqlCipherExportAdapter();

        await adapter.exportSqlCipherDatabase(
          sourceDb: db,
          destinationPath: p.join(tempDir!.path, 'android.snapshot.db'),
          destinationKey: 'staged-db-key',
          cipherMetadata: const MigrationDatabaseCipherMetadata(
            cipherVersion: '4.6.0',
            policy: MigrationDatabaseCipherPolicy.compatible,
          ),
        );

        expect(db.commands, hasLength(3));
        expect(
          db.commands[0],
          allOf(
            startsWith('execute:ATTACH DATABASE '),
            contains('migration_export'),
          ),
        );
        expect(
          db.commands[1],
          "rawQuery:SELECT sqlcipher_export('migration_export')",
        );
        expect(db.commands[2], 'execute:DETACH DATABASE migration_export');
      },
    );

    test(
      'SQLCipher export capability',
      () async {
        final capability =
            await MigrationDatabaseSnapshotExporter.probeSqlCipherExportCapability(
              tempDirectoryPath: tempDir!.path,
            );

        expect(capability.isSupported, isTrue, reason: capability.failure);
        expect(capability.cipherVersion, isNotEmpty);
        expect(capability.exportedRowCount, 1);
      },
      skip:
          'Plugin-registered SQLCipher capability is covered by '
          'integration_test/migration_database_sqlcipher_capability_test.dart.',
    );
  });
}

Map<String, Object?> _outcomeRow(String seed) => <String, Object?>{
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

Future<void> _createSeededAccountDb(Database db) async {
  await db.execute('''
CREATE TABLE identity (
  id INTEGER PRIMARY KEY,
  peer_id TEXT NOT NULL,
  public_key TEXT NOT NULL,
  private_key TEXT,
  mnemonic12 TEXT,
  ml_kem_secret_key TEXT,
  username TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');
  await db.insert('identity', {
    'id': 1,
    'peer_id': 'peer-1',
    'public_key': 'pub',
    'private_key': null,
    'mnemonic12': null,
    'ml_kem_secret_key': null,
    'username': 'alice',
    'created_at': '2026-06-07T00:00:00Z',
    'updated_at': '2026-06-07T00:00:00Z',
  });
}

class RecordingSnapshotExportAdapter
    implements MigrationSqlCipherExportAdapter {
  final Database verificationDb;
  final List<int> bytesToWrite;
  final String integrityResult;
  final commands = <String>[];
  String? exportDestinationPath;
  String? exportDestinationKey;

  RecordingSnapshotExportAdapter({
    required this.verificationDb,
    required this.bytesToWrite,
    this.integrityResult = 'ok',
  });

  @override
  Future<MigrationDatabaseCipherMetadata> captureCipherMetadata(
    Database db,
  ) async {
    commands.add('captureCipherMetadata');
    return const MigrationDatabaseCipherMetadata(
      cipherVersion: '4.6.0',
      kdfIter: 256000,
      cipherPageSize: 4096,
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
    commands.add('sqlcipherExport');
    exportDestinationPath = destinationPath;
    exportDestinationKey = destinationKey;
    await File(destinationPath).writeAsBytes(bytesToWrite, flush: true);
  }

  @override
  Future<Database> openExportedDatabase({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) async {
    commands.add('openExportedDatabase');
    return verificationDb;
  }

  @override
  Future<String> runIntegrityCheck(Database db) async => integrityResult;
}

class RecordingSqlCipherExportDatabase implements Database {
  final commands = <String>[];

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    commands.add('execute:$sql');
    if (sql.trimLeft().toUpperCase().startsWith('SELECT')) {
      throw StateError('SELECT statements must run through rawQuery');
    }
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    commands.add('rawQuery:$sql');
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
