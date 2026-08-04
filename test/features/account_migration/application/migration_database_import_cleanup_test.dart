import 'dart:io';

import 'package:flutter_app/features/account_migration/application/migration_database_import_cleanup.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_cleanup.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('MigrationDatabaseImportCleanup', () {
    late Directory tempDir;
    late FakeSecureKeyStore primaryStore;
    late MigrationSecureStorageStaging secureStaging;
    late MigrationSecureStorageCleanup secureCleanup;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mig004_cleanup_');
      primaryStore = FakeSecureKeyStore();
      secureStaging = MigrationSecureStorageStaging(primaryStore: primaryStore);
      secureCleanup = MigrationSecureStorageCleanup(staging: secureStaging);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test(
      'failed import deletes DB sidecars and invokes MIG-003 cleanup only for session',
      () async {
        final dbPath = p.join(tempDir.path, 'identity.staged.db');
        final activeDbPath = p.join(tempDir.path, 'identity.active.db');
        final manifestPath = p.join(tempDir.path, 'manifest.json');
        final tempExportPath = p.join(tempDir.path, 'identity.staged.db.tmp');
        for (final path in [
          dbPath,
          '$dbPath-wal',
          '$dbPath-shm',
          '$dbPath-journal',
          manifestPath,
          tempExportPath,
          activeDbPath,
        ]) {
          await File(path).writeAsString('data', flush: true);
        }
        final dbKey = _dbKey();
        await primaryStore.write(dbKey.activeKey, 'active-db');
        await secureStaging.stageValue(
          sessionId: 'session-1',
          key: dbKey,
          value: 'staged-db',
        );
        var secureCleanupInvoked = false;
        final cleanup = MigrationDatabaseImportCleanup(
          failedSecureStorageCleanup:
              ({required sessionId, required registryKeys}) async {
                secureCleanupInvoked = true;
                await secureCleanup.failedImportCleanup(
                  sessionId: sessionId,
                  registryKeys: registryKeys,
                );
              },
        );

        await cleanup.failedImportCleanup(
          sessionId: 'session-1',
          stagedDatabasePath: dbPath,
          manifestPath: manifestPath,
          extraArtifactPaths: [tempExportPath],
          registryKeys: [dbKey],
        );

        expect(secureCleanupInvoked, isTrue);
        for (final path in [
          dbPath,
          '$dbPath-wal',
          '$dbPath-shm',
          '$dbPath-journal',
          manifestPath,
          tempExportPath,
        ]) {
          expect(File(path).existsSync(), isFalse, reason: path);
        }
        expect(File(activeDbPath).existsSync(), isTrue);
        expect(await primaryStore.read(dbKey.activeKey), 'active-db');
        expect(
          await secureStaging.readStagedValue(
            sessionId: 'session-1',
            key: dbKey,
          ),
          isNull,
        );
      },
    );

    test(
      'successful import cleanup removes staging artifacts without rollback',
      () async {
        final dbPath = p.join(tempDir.path, 'verified.db');
        final manifestPath = p.join(tempDir.path, 'verified-manifest.json');
        await File(dbPath).writeAsString('db', flush: true);
        await File('$dbPath-wal').writeAsString('wal', flush: true);
        await File('$dbPath-shm').writeAsString('shm', flush: true);
        await File('$dbPath-journal').writeAsString('journal', flush: true);
        await File(manifestPath).writeAsString('manifest', flush: true);
        final cleanup = MigrationDatabaseImportCleanup(
          failedSecureStorageCleanup:
              ({required sessionId, required registryKeys}) {
                throw StateError(
                  'success cleanup must not call failed cleanup',
                );
              },
        );

        await cleanup.successfulImportCleanup(
          stagedDatabasePath: dbPath,
          manifestPath: manifestPath,
        );

        expect(File(dbPath).existsSync(), isFalse);
        expect(File('$dbPath-wal').existsSync(), isFalse);
        expect(File('$dbPath-shm').existsSync(), isFalse);
        expect(File('$dbPath-journal').existsSync(), isFalse);
        expect(File(manifestPath).existsSync(), isFalse);
      },
    );

    test(
      'cancelled v107 import removes every SQLite sidecar and session staging',
      () async {
        final dbPath = p.join(tempDir.path, 'cancelled-v107.db');
        final manifestPath = p.join(tempDir.path, 'cancelled-v107.json');
        for (final path in <String>[
          dbPath,
          '$dbPath-wal',
          '$dbPath-shm',
          '$dbPath-journal',
          manifestPath,
        ]) {
          await File(path).writeAsString('data', flush: true);
        }
        final dbKey = _dbKey();
        await secureStaging.stageValue(
          sessionId: 'cancelled-session',
          key: dbKey,
          value: 'staged-db',
        );
        final cleanup = MigrationDatabaseImportCleanup(
          failedSecureStorageCleanup:
              ({required sessionId, required registryKeys}) =>
                  secureCleanup.failedImportCleanup(
                    sessionId: sessionId,
                    registryKeys: registryKeys,
                  ),
        );

        await cleanup.cancelledImportCleanup(
          sessionId: 'cancelled-session',
          stagedDatabasePath: dbPath,
          manifestPath: manifestPath,
          registryKeys: <MigrationSecureStorageKey>[dbKey],
        );

        for (final path in <String>[
          dbPath,
          '$dbPath-wal',
          '$dbPath-shm',
          '$dbPath-journal',
          manifestPath,
        ]) {
          expect(File(path).existsSync(), isFalse, reason: path);
        }
        expect(
          await secureStaging.readStagedValue(
            sessionId: 'cancelled-session',
            key: dbKey,
          ),
          isNull,
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
