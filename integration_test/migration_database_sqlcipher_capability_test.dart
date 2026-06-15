import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_import_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_schema_inventory.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

/// Cross-platform portability artifact flow (spec gap G2):
///
/// 1. On the SOURCE platform (e.g. Android emulator):
///    flutter test integration_test/migration_database_sqlcipher_capability_test.dart \
///      -d `<android-device>` --dart-define=MIGRATION_PORTABILITY_EXPORT_DIR=/data/local/tmp/mig_portability
///    then `adb pull /data/local/tmp/mig_portability`.
/// 2. On the TARGET platform (e.g. iOS simulator):
///    flutter test integration_test/migration_database_sqlcipher_capability_test.dart \
///      -d `<ios-sim>` --dart-define=MIGRATION_PORTABILITY_FIXTURE_DIR=`<pulled-dir>`
///
/// Both modes skip silently when their define is absent, so the default
/// same-device run stays green.
const String _portabilityExportDir = String.fromEnvironment(
  'MIGRATION_PORTABILITY_EXPORT_DIR',
);
const String _portabilityFixtureDir = String.fromEnvironment(
  'MIGRATION_PORTABILITY_FIXTURE_DIR',
);
const String _portabilityKey = 'portability-transfer-key';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SQLCipher export capability', (_) async {
    final tempDir = await Directory.systemTemp.createTemp(
      'mig004_sqlcipher_capability_',
    );
    try {
      final capability =
          await MigrationDatabaseSnapshotExporter.probeSqlCipherExportCapability(
            tempDirectoryPath: tempDir.path,
          );

      expect(capability.isSupported, isTrue, reason: capability.failure);
      expect(capability.cipherVersion, isNotEmpty);
      expect(capability.exportedRowCount, 1);
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  testWidgets('SQLCipher cross-platform portability (artifact flow)', (
    _,
  ) async {
    if (_portabilityExportDir.isNotEmpty) {
      await _runPortabilityExport();
      return;
    }
    if (_portabilityFixtureDir.isNotEmpty) {
      await _runPortabilityVerify();
      return;
    }
    markTestSkipped(
      'Portability modes need --dart-define='
      'MIGRATION_PORTABILITY_EXPORT_DIR (source platform) or '
      'MIGRATION_PORTABILITY_FIXTURE_DIR (target platform); see file header.',
    );
  });

  testWidgets('SQLCipher export → staged open with the transferred key', (
    _,
  ) async {
    // The host E2E fakes the SQLCipher seam; this is the REAL seam: a
    // multi-table SQLCipher source DB exported with the production exporter
    // (re-keyed to the transfer key), then opened through the production
    // import-staging verification chain (checksum + quick_check + schema
    // hash) using the staged transferred key — with row-level content checks.
    final tempDir = await Directory.systemTemp.createTemp(
      'mig_sqlcipher_staged_open_',
    );
    const sourceKey = 'source-device-db-key';
    const transferredKey = 'transferred-db-encryption-key';
    const sessionId = 'sqlcipher-staged-open-session';
    sqlcipher.Database? sourceDb;
    sqlcipher.Database? stagedDb;
    try {
      final sourcePath = p.join(tempDir.path, 'source.db');
      sourceDb = await sqlcipher.openDatabase(
        sourcePath,
        password: sourceKey,
        version: 1,
        singleInstance: false,
      );
      await _createMigrationFixtureSchema(sourceDb);
      await _seedMigrationFixtureRows(sourceDb);

      // Old phone: real export, re-keyed to the transferred key.
      final exportedPath = p.join(tempDir.path, 'identity.snapshot.db');
      const exporter = MigrationDatabaseSnapshotExporter();
      final exportResult = await exporter.exportSnapshot(
        sourceDb: sourceDb,
        destinationPath: exportedPath,
        destinationKey: transferredKey,
        sourceAppVersion: 'integration-test',
        sourceBuildNumber: '1',
      );
      // Cipher profile pinning (spec gap G2, partial): the captured params
      // must travel in the manifest for the receiver to re-apply.
      expect(exportResult.manifest.cipherMetadata.cipherVersion, isNotEmpty);
      expect(exportResult.manifest.cipherMetadata.kdfIter, isNotNull);
      expect(exportResult.manifest.cipherMetadata.cipherPageSize, isNotNull);

      // New phone: stage the transferred key, then open through the real
      // verification chain.
      final staging = MigrationSecureStorageStaging(
        primaryStore: _InMemorySecureKeyStore(),
      );
      final dbKeyReference = MigrationSecureStorageRegistry.fixedKey(
        scope: MigrationSecureStoreScope.primary,
        activeKey: MigrationSecureStorageRegistry.dbEncryptionKey,
      );
      expect(dbKeyReference, isNotNull);
      await staging.stageValue(
        sessionId: sessionId,
        key: dbKeyReference!,
        value: transferredKey,
      );
      final stagedPath = p.join(tempDir.path, 'identity.staged.db');
      await File(exportResult.destinationPath).copy(stagedPath);

      final stagedResult = await MigrationDatabaseImportStaging(
        secureStorageStaging: staging,
        // Default opener: the REAL SQLCipher staged-open path.
      ).openVerifiedStagedDatabase(
        sessionId: sessionId,
        stagedDatabasePath: stagedPath,
        manifest: exportResult.manifest,
      );
      stagedDb = stagedResult.database;

      // Row-level content survived the export → stage → verified open chain.
      final identity = await stagedDb.query('identity');
      expect(identity, hasLength(1));
      expect(identity.single['peer_id'], 'old-peer');
      expect(await stagedDb.query('messages'), hasLength(1));
      expect(await stagedDb.query('media_attachments'), hasLength(2));
      expect(await stagedDb.query('group_messages'), hasLength(1));
      expect(await stagedDb.query('groups'), hasLength(1));
      final groupKeys = await stagedDb.query('group_keys');
      expect(groupKeys, hasLength(1));
      expect(
        groupKeys.single['encrypted_key'],
        'secure:group_key_material:group-1:1',
      );

      // Fail-closed: the snapshot must NOT open with the old source key.
      await expectLater(() async {
        final wrongKeyDb = await sqlcipher.openDatabase(
          stagedPath,
          password: sourceKey,
          singleInstance: false,
        );
        try {
          await wrongKeyDb.query('identity');
        } finally {
          await wrongKeyDb.close();
        }
      }(), throwsA(anything));
    } finally {
      if (stagedDb != null && stagedDb.isOpen) {
        await stagedDb.close();
      }
      if (sourceDb != null && sourceDb.isOpen) {
        await sourceDb.close();
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}

Future<void> _runPortabilityExport() async {
  final exportDir = Directory(_portabilityExportDir);
  await exportDir.create(recursive: true);
  final tempDir = await Directory.systemTemp.createTemp('mig_portability_src_');
  sqlcipher.Database? sourceDb;
  try {
    sourceDb = await sqlcipher.openDatabase(
      p.join(tempDir.path, 'source.db'),
      password: 'portability-source-key',
      version: 1,
      singleInstance: false,
    );
    await _createMigrationFixtureSchema(sourceDb);
    await _seedMigrationFixtureRows(sourceDb);

    const exporter = MigrationDatabaseSnapshotExporter();
    final result = await exporter.exportSnapshot(
      sourceDb: sourceDb,
      destinationPath: p.join(exportDir.path, 'snapshot.db'),
      destinationKey: _portabilityKey,
      sourceAppVersion: 'portability-export',
      sourceBuildNumber: '1',
    );
    await File(p.join(exportDir.path, 'portability.json')).writeAsString(
      jsonEncode({
        'platform': Platform.operatingSystem,
        'cipher_version': result.manifest.cipherMetadata.cipherVersion,
        'kdf_iter': result.manifest.cipherMetadata.kdfIter,
        'cipher_page_size': result.manifest.cipherMetadata.cipherPageSize,
        'checksum_sha256': result.manifest.databaseChecksumSha256,
        'schema_hash': result.manifest.schemaHash,
      }),
      flush: true,
    );
    // ignore: avoid_print
    print('PORTABILITY_EXPORT_WRITTEN dir=${exportDir.path}');
  } finally {
    if (sourceDb != null && sourceDb.isOpen) {
      await sourceDb.close();
    }
    await tempDir.delete(recursive: true);
  }
}

Future<void> _runPortabilityVerify() async {
  final fixtureDir = Directory(_portabilityFixtureDir);
  final meta =
      jsonDecode(
            await File(
              p.join(fixtureDir.path, 'portability.json'),
            ).readAsString(),
          )
          as Map<String, dynamic>;
  final snapshotPath = p.join(fixtureDir.path, 'snapshot.db');

  // The byte-level checksum must survive the platform hop.
  expect(
    await MigrationDatabaseSnapshotExporter.computeFileChecksum(snapshotPath),
    meta['checksum_sha256'],
    reason: 'snapshot bytes changed in transit',
  );

  // Open with the transferred key on THIS platform's SQLCipher, applying the
  // exporting platform's pinned cipher params — the G2 portability proof.
  final opener = const DefaultMigrationStagedDatabaseOpener();
  final db = await opener.open(
    path: snapshotPath,
    key: _portabilityKey,
    cipherMetadata: MigrationDatabaseCipherMetadata(
      cipherVersion: meta['cipher_version'] as String,
      kdfIter: meta['kdf_iter'] as int?,
      cipherPageSize: meta['cipher_page_size'] as int?,
      policy: MigrationDatabaseCipherPolicy.compatible,
    ),
  );
  try {
    final inventory = await MigrationDatabaseSchemaInventory.fromDatabase(db);
    expect(inventory.schemaHash, meta['schema_hash']);
    final identity = await db.query('identity');
    expect(identity.single['peer_id'], 'old-peer');
    expect(await db.query('media_attachments'), hasLength(2));
    expect(await db.query('group_keys'), hasLength(1));
    // ignore: avoid_print
    print(
      'PORTABILITY_VERIFY_OK source=${meta['platform']} '
      'target=${Platform.operatingSystem}',
    );
  } finally {
    await db.close();
  }
}

Future<void> _createMigrationFixtureSchema(sqlcipher.Database db) async {
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
  local_path TEXT,
  download_status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL
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

Future<void> _seedMigrationFixtureRows(sqlcipher.Database db) async {
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
    'text': 'hello',
    'timestamp': createdAt,
    'status': 'sent',
    'is_incoming': 0,
    'created_at': createdAt,
  });
  await db.insert('media_attachments', {
    'id': 'blob-1',
    'message_id': 'message-1',
    'mime': 'image/jpeg',
    'size': 5,
    'media_type': 'image',
    'local_path': 'media/peer-bob/blob-1.jpg',
    'download_status': 'done',
    'created_at': createdAt,
  });
  await db.insert('media_attachments', {
    'id': 'blob-2',
    'message_id': 'message-1',
    'mime': 'image/jpeg',
    'size': 7,
    'media_type': 'image',
    'local_path': 'media/peer-bob/blob-2.jpg',
    'download_status': 'done',
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
}

class _InMemorySecureKeyStore implements SecureKeyStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);
}
