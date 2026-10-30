import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_active_importer.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_import_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_import_validator.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_schema_inventory.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/account_migration/application/migration_pending_work_manifest_builder.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_pending_work_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../migration_durable_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'DC-019 TRANSFER-006 current production schema survives export, verified '
    'import and disk reopen while local AI results stay on the source',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'migration-schema-',
      );
      final sourcePath = '${directory.path}/source.db';
      final targetPath = '${directory.path}/target.db';
      var source = await openMigrationProductionDatabase(sourcePath);
      var target = await openMigrationProductionDatabase(targetPath);
      var sourceKeys = await DurableMigrationKeyStore.open(
        '${directory.path}/source-keys.db',
      );
      var targetKeys = await DurableMigrationKeyStore.open(
        '${directory.path}/target-keys.db',
      );
      Database? stagedDatabase;
      addTearDown(() async {
        if (stagedDatabase?.isOpen == true) await stagedDatabase!.close();
        if (source.isOpen) await source.close();
        if (target.isOpen) await target.close();
        await sourceKeys.close();
        await targetKeys.close();
        await directory.delete(recursive: true);
      });
      await seedMigrationAccount(
        source,
        sourceKeys,
        documentsRootPath: '${directory.path}/source-documents',
      );
      await targetKeys.write(
        MigrationSecureStorageRegistry.dbEncryptionKey,
        'target-active-db-key',
      );
      await source.insert('local_ai_translations', {
        'owner_kind': 'voiceAttachment',
        'owner_id': 'voice',
        'target_language': 'en',
        'source_sha256': sha256
            .convert(utf8.encode(migrationLocalTranscript))
            .toString(),
        'translated_text': migrationLocalTranslation,
      });
      await targetKeys.authority.saveAuthority(
        AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.migrationImportStaging,
          accountPeerId: migrationOwner.peerId,
        ),
      );
      const adapter = MigrationSqliteSnapshotAdapter();
      final snapshot = await MigrationDatabaseSnapshotExporter(adapter: adapter)
          .exportSnapshot(
            sourceDb: source,
            destinationPath: '${directory.path}/snapshot.db',
            destinationKey: 'host-copy-key',
            sourceAppVersion: 'fixture',
            sourceBuildNumber: '129',
          );
      final sourceInventory =
          await MigrationDatabaseSchemaInventory.fromDatabase(source);
      expect(snapshot.manifest.schemaHash, sourceInventory.schemaHash);
      expect(
        snapshot.manifest.schemaInventory.tableNames,
        sourceInventory.tableNames,
      );
      expect(
        snapshot.manifest.schemaInventory.transferableTableNames,
        isNot(contains('local_ai_translations')),
      );
      final bytes = String.fromCharCodes(
        await File(snapshot.destinationPath).readAsBytes(),
      );
      expect(bytes, isNot(contains(migrationLocalTranscript)));
      expect(bytes, isNot(contains(migrationLocalTranslation)));

      final staging = MigrationSecureStorageStaging(primaryStore: targetKeys);
      await expectLater(
        MigrationDatabaseImportStaging(
          secureStorageStaging: staging,
          opener: adapter,
        ).openVerifiedStagedDatabase(
          sessionId: 'schema',
          stagedDatabasePath: snapshot.destinationPath,
          manifest: snapshot.manifest,
        ),
        throwsA(isA<MigrationDatabaseImportStagingException>()),
      );
      final portableKeys = migrationPortableKeys();
      for (final key in portableKeys) {
        final value = await sourceKeys.read(key.activeKey);
        expect(value, isNotNull, reason: key.activeKey);
        await staging.stageValue(sessionId: 'schema', key: key, value: value!);
      }
      final staged =
          await MigrationDatabaseImportStaging(
            secureStorageStaging: staging,
            opener: adapter,
          ).openVerifiedStagedDatabase(
            sessionId: 'schema',
            stagedDatabasePath: snapshot.destinationPath,
            manifest: snapshot.manifest,
          );
      stagedDatabase = staged.database;
      final validation =
          await MigrationDatabaseImportValidator(
            secureStorageStaging: staging,
          ).validate(
            sessionId: 'schema',
            stagedDb: staged.database,
            requiredSecretKeys: portableKeys,
          );
      expect(validation.isAccepted, isTrue);
      await stagedDatabase.close();
      await roundtripMigrationBundle(
        directory: directory,
        source: source,
        target: target,
        sourceKeys: sourceKeys,
        targetKeys: targetKeys,
        sessionId: 'full-schema',
      );
      await source.close();
      await target.close();
      source = await openMigrationProductionDatabase(sourcePath);
      target = await openMigrationProductionDatabase(targetPath);
      sourceKeys = await sourceKeys.reopen();
      targetKeys = await targetKeys.reopen();

      // Compare every production account table after closing both handles. The
      // transcript cell is explicitly installation-local despite its portable parent.
      for (final table in sourceInventory.transferableTableNames) {
        final expected = [
          for (final row in await source.query(table))
            {
              ...row,
              if (table == 'media_attachments') 'local_transcript': null,
            },
        ];
        expect(await target.query(table), expected, reason: table);
      }
      expect(
        (await source.query('media_attachments')).single['local_transcript'],
        migrationLocalTranscript,
      );
      expect(
        (await source.query('local_ai_translations')).single['translated_text'],
        migrationLocalTranslation,
      );
      expect(await target.query('local_ai_translations'), isEmpty);
      for (final key in portableKeys) {
        expect(
          await targetKeys.read(key.activeKey),
          key.activeKey == MigrationSecureStorageRegistry.dbEncryptionKey
              ? 'target-active-db-key'
              : await sourceKeys.read(key.activeKey),
          reason: key.activeKey,
        );
      }
      expect(
        (await targetKeys.authority.loadAuthority())!.state,
        AccountMigrationAuthorityState.active,
      );
      expect(
        (await sourceKeys.authority.loadAuthority())!.state,
        AccountMigrationAuthorityState.migratedOut,
      );
      expect(
        await File(
          '${directory.path}/target-documents/$migrationVoiceRelativePath',
        ).readAsBytes(),
        migrationVoiceBytes,
      );
      expect(
        await targetKeys.networkGate.allowsAccountNetworkSideEffects(
          peerId: migrationOwner.peerId,
          operation: 'pending_retry',
        ),
        isTrue,
      );
      final pending = const MigrationPendingWorkManifestBuilder().build(
        oneToOneMessageRows: await target.query(
          'messages',
          where: 'status = ?',
          whereArgs: ['failed'],
        ),
        groupMessageRows: await target.query(
          'group_messages',
          where: 'status = ?',
          whereArgs: ['failed'],
        ),
      );
      expect(pending.isValid, isTrue, reason: jsonEncode(pending.toJson()));
      expect(
        pending.items.map((item) => item.kind),
        containsAll([
          MigrationPendingWorkItemKind.oneToOneMessageRetry,
          MigrationPendingWorkItemKind.groupMessageRetry,
        ]),
      );

      // Fail closed before deleting a previously imported account if an otherwise
      // real staged database has installation-local plaintext injected into it.
      final contaminated = await databaseFactoryFfi.openDatabase(
        snapshot.destinationPath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      stagedDatabase = contaminated;
      await contaminated.update('media_attachments', {
        'local_transcript': 'must not import',
      });
      final before = await target.query('messages');
      await expectLater(
        MigrationDatabaseActiveImporter(
          activeDatabase: target,
        ).importVerifiedStagedDatabase(
          MigrationDatabaseImportStagingResult(
            database: contaminated,
            manifest: snapshot.manifest,
            stagedDatabasePath: snapshot.destinationPath,
          ),
        ),
        throwsA(
          isA<MigrationDatabaseActiveImportException>().having(
            (error) => error.message,
            'message',
            contains('installation-local transcripts'),
          ),
        ),
      );
      await target.close();
      target = await openMigrationProductionDatabase(targetPath);
      expect(await target.query('messages'), before);
      expect(
        (await target.query('media_attachments')).single['local_transcript'],
        isNull,
      );
    },
  );

  test(
    'DC-019 TRANSFER-006 native SQLCipher encrypted snapshot capability',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'migration-native-cipher-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final capability =
          await MigrationDatabaseSnapshotExporter.probeSqlCipherExportCapability(
            tempDirectoryPath: directory.path,
          );
      expect(capability.isSupported, isTrue, reason: capability.failure);
      expect(capability.exportedRowCount, 1);
    },
    skip:
        'KNOWN GAP [DC-019/TRANSFER-006]: host FFI provides SQLite only; '
        'native plugin-registered SQLCipher export/encryption requires '
        'integration_test/migration_database_sqlcipher_capability_test.dart.',
  );
}
