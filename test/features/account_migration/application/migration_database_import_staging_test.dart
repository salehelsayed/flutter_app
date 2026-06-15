import 'dart:io';

import 'package:flutter_app/features/account_migration/application/migration_database_import_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_schema_inventory.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('MigrationDatabaseImportStaging', () {
    late Directory tempDir;
    late RecordingSecureKeyStore primaryStore;
    late MigrationSecureStorageStaging secureStaging;
    late Database stagedDb;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mig004_import_');
      primaryStore = RecordingSecureKeyStore();
      secureStaging = MigrationSecureStorageStaging(primaryStore: primaryStore);
      stagedDb = await openDatabase(inMemoryDatabasePath, version: 1);
      await stagedDb.execute('CREATE TABLE identity (id INTEGER PRIMARY KEY)');
    });

    tearDown(() async {
      await stagedDb.close();
      await tempDir.delete(recursive: true);
    });

    test('opens staged SQLCipher database with staged key', () async {
      final opener = RecordingStagedDatabaseOpener(database: stagedDb);
      final importStaging = MigrationDatabaseImportStaging(
        secureStorageStaging: secureStaging,
        opener: opener,
      );
      final dbKey = _dbKey();
      await primaryStore.write(dbKey.activeKey, 'active-db-key');
      primaryStore.activeWrites.clear();
      await secureStaging.stageValue(
        sessionId: 'session-1',
        key: dbKey,
        value: 'staged-db-key',
      );
      final manifest = await _manifestFor(stagedDb);
      final stagedPath = p.join(tempDir.path, 'identity.staged.db');

      final result = await importStaging.openVerifiedStagedDatabase(
        sessionId: 'session-1',
        stagedDatabasePath: stagedPath,
        manifest: manifest,
      );

      expect(result.database, same(stagedDb));
      expect(opener.openedPath, stagedPath);
      expect(opener.openedKey, 'staged-db-key');
      expect(primaryStore.activeWrites, isEmpty);
      expect(await primaryStore.read(dbKey.activeKey), 'active-db-key');
    });

    test(
      'fails closed for missing key, checksum mismatch, and bad cipher policy',
      () async {
        final opener = RecordingStagedDatabaseOpener(database: stagedDb);
        final importStaging = MigrationDatabaseImportStaging(
          secureStorageStaging: secureStaging,
          opener: opener,
        );
        final manifest = await _manifestFor(stagedDb);

        await expectLater(
          importStaging.openVerifiedStagedDatabase(
            sessionId: 'session-2',
            stagedDatabasePath: p.join(tempDir.path, 'missing-key.db'),
            manifest: manifest,
          ),
          throwsA(isA<MigrationDatabaseImportStagingException>()),
        );
        expect(opener.openCount, 0);

        await secureStaging.stageValue(
          sessionId: 'session-2',
          key: _dbKey(),
          value: 'staged-db-key',
        );
        await expectLater(
          importStaging.openVerifiedStagedDatabase(
            sessionId: 'session-2',
            stagedDatabasePath: p.join(tempDir.path, 'wrong-checksum.db'),
            manifest: manifest.copyWith(databaseChecksumSha256: '0' * 64),
          ),
          throwsA(isA<MigrationDatabaseImportStagingException>()),
        );

        await expectLater(
          importStaging.openVerifiedStagedDatabase(
            sessionId: 'session-2',
            stagedDatabasePath: p.join(tempDir.path, 'bad-cipher.db'),
            manifest: manifest.copyWith(
              cipherMetadata: const MigrationDatabaseCipherMetadata(
                cipherVersion: '4.6.0',
                policy: MigrationDatabaseCipherPolicy.unsupported,
              ),
            ),
          ),
          throwsA(isA<MigrationDatabaseImportStagingException>()),
        );
      },
    );
  });
}

MigrationSecureStorageKey _dbKey() {
  return MigrationSecureStorageRegistry.fixedKey(
    scope: MigrationSecureStoreScope.primary,
    activeKey: MigrationSecureStorageRegistry.dbEncryptionKey,
  )!;
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

class RecordingStagedDatabaseOpener implements MigrationStagedDatabaseOpener {
  final Database database;
  String? openedPath;
  String? openedKey;
  int openCount = 0;

  RecordingStagedDatabaseOpener({required this.database});

  @override
  Future<Database> open({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) async {
    openCount += 1;
    openedPath = path;
    openedKey = key;
    return database;
  }
}

class RecordingSecureKeyStore extends FakeSecureKeyStore {
  final activeWrites = <String>[];

  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    if (!key.startsWith(MigrationSecureStorageStaging.stagingPrefix)) {
      activeWrites.add(key);
    }
  }
}
