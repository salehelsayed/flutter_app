import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_bundle_transfer.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_local_transfer_runtime.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/account_migration/application/migration_entry_stream_source.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_app/features/stickers/data/sqlite_custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../migration_durable_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late Directory documents;
  late Directory temporary;
  late Directory targetDocuments;
  late Directory targetTemporary;
  late Database source;
  late Database target;
  late DurableMigrationKeyStore sourceKeys;
  late DurableMigrationKeyStore targetKeys;
  late List<SqliteCustomStickerLibrary> libraries;
  late List<Map<String, dynamic>> events;
  late _SnapshotProbe snapshot;
  var inputNumber = 0;

  SqliteCustomStickerLibrary sourceLibrary() {
    final library = SqliteCustomStickerLibrary(
      db: source,
      documentsDirectory: documents,
      temporaryDirectory: temporary,
      mayUseAccount: () async => true,
      enabled: true,
    );
    libraries.add(library);
    return library;
  }

  Future<NormalizedStickerAsset> input(
    int variant, {
    bool animated = false,
  }) async {
    img.Image pixels(int index) {
      final image = img.Image(width: 16, height: 16, numChannels: 4);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          image.setPixelRgba(x, y, 30 + index * 40, 70 + x, 100 + y, 255);
        }
      }
      return image;
    }

    final image = pixels(variant);
    if (animated) {
      image.frameDuration = 83;
      image.addFrame(pixels(variant + 1)..frameDuration = 84);
    }
    final bytes = img.encodeWebP(image, lossless: true);
    final file = File(
      p.join(root.path, 'producer', 'input-${inputNumber++}.webp'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return NormalizedStickerAsset(
      filePath: file.path,
      sha256Hex: sha256.convert(bytes).toString(),
      mime: 'image/webp',
      byteLength: bytes.length,
      width: 16,
      height: 16,
      frameCount: animated ? 2 : 1,
      durationMs: animated ? 167 : 0,
    );
  }

  Future<List<Map<String, Object?>>> rows(Database db) =>
      db.query('custom_stickers', orderBy: 'position ASC, id ASC');

  Future<AccountMigrationLocalTransferBundle> exportBundle({
    MigrationEntryFileReader? reader,
  }) =>
      AccountMigrationProductionBundleSource(
        sourceDb: source,
        primaryStore: sourceKeys,
        documentsRootPath: documents.path,
        exportDirectoryPath: p.join(root.path, 'exports'),
        snapshotExporter: MigrationDatabaseSnapshotExporter(adapter: snapshot),
        fileReader: reader ?? const IoMigrationEntryFileReader(),
        segmentSize: 64 * 1024,
      )(
        AccountMigrationTransferRequest(
          transcript: AuthenticatedMigrationChannelTranscript(
            sessionId: 'sticker-inspection',
            newPhoneEphemeralPublicKey: 'fixture-new-public',
            oldPhonePeerId: migrationOwner.peerId,
            authenticatedChannelBinding: 'fixture-channel-binding',
            authorizationNonce: 'fixture-nonce',
          ),
        ),
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('custom-sticker-move-');
    documents = await Directory(p.join(root.path, 'source-documents')).create();
    targetDocuments = await Directory(
      p.join(root.path, 'target-documents'),
    ).create();
    temporary = await Directory(p.join(root.path, 'source-temp')).create();
    targetTemporary = await Directory(
      p.join(root.path, 'target-temp'),
    ).create();
    source = await openMigrationProductionDatabase(
      p.join(root.path, 'source.db'),
    );
    target = await openMigrationProductionDatabase(
      p.join(root.path, 'target.db'),
    );
    sourceKeys = await DurableMigrationKeyStore.open(
      p.join(root.path, 'source-keys.db'),
    );
    targetKeys = await DurableMigrationKeyStore.open(
      p.join(root.path, 'target-keys.db'),
    );
    await seedMigrationAccount(
      source,
      sourceKeys,
      documentsRootPath: documents.path,
    );
    await targetKeys.write(
      MigrationSecureStorageRegistry.dbEncryptionKey,
      'target-active-db-key',
    );
    libraries = [];
    events = [];
    snapshot = _SnapshotProbe();
    debugSetFlowEventSink(events.add);
  });

  tearDown(() async {
    debugSetFlowEventSink(null);
    for (final library in libraries) {
      await library.retire();
    }
    if (source.isOpen) await source.close();
    if (target.isOpen) await target.close();
    await sourceKeys.close();
    await targetKeys.close();
    await root.delete(recursive: true);
  });

  test(
    'BL17 real bundle restores static and animated sticker rows bytes order and quota accounting while flag off',
    () async {
      expect(kCustomStickersEnabled, isFalse);
      final library = sourceLibrary();
      final first = await library.admit(await input(0));
      final second = await library.admit(await input(1, animated: true));
      await library.reorder([first.id, second.id]);
      final send = await library.prepareSend(
        second.id,
        representation: CustomStickerSendRepresentation.staticPoster,
      );
      final sendBytes = await send.file.readAsBytes();
      await library
          .retire(); // Runtime freeze/retire/drain wiring is separately owned.
      final before = await rows(source);
      final expectedBytes = <String, Uint8List>{
        for (final row in before)
          row['relative_path'] as String: await File(
            p.join(documents.path, row['relative_path'] as String),
          ).readAsBytes(),
      };
      final accounting = await source.rawQuery(
        'SELECT COUNT(*) AS items, SUM(size_bytes) AS bytes FROM custom_stickers',
      );
      final extras = <String, List<int>>{
        'stickers/orphan.webp': expectedBytes.values.first,
        'stickers/orphan.thumb.jpg': [4, 5, 6],
        'stickers/editor/source.png': [7, 8, 9],
        'custom-sticker-editor/working.webp': [10, 11],
        'sticker-send-11111111-2222-4333-8444-555555555555.webp': sendBytes,
      };
      for (final entry in extras.entries) {
        final file = File(p.join(documents.path, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }

      final bundle = await exportBundle();
      try {
        final files = bundle.manifest.entries
            .where((entry) => entry.kind == MigrationTransferEntryKind.file)
            .toList();
        expect(
          files.map((entry) => entry.relativePath),
          unorderedEquals([migrationVoiceRelativePath, ...expectedBytes.keys]),
        );
        final streams = {
          for (final entry in bundle.streamingEntries) entry.entryId: entry,
        };
        for (final descriptor in files.where(
          (entry) => expectedBytes.containsKey(entry.relativePath),
        )) {
          final bytes = BytesBuilder(copy: false);
          await for (final chunk in streams[descriptor.entryId]!.openChunks()) {
            bytes.add(chunk);
          }
          expect(bytes.takeBytes(), expectedBytes[descriptor.relativePath]);
          expect(
            descriptor.sha256,
            sha256.convert(expectedBytes[descriptor.relativePath]!).toString(),
          );
        }
        final metadataEntry = bundle.streamingEntries.singleWhere(
          (entry) => entry.kind == MigrationTransferEntryKind.secureValues,
        );
        final metadataBytes = BytesBuilder(copy: false);
        await for (final chunk in metadataEntry.openChunks()) {
          metadataBytes.add(chunk);
        }
        final metadata =
            jsonDecode(utf8.decode(metadataBytes.takeBytes()))
                as Map<String, dynamic>;
        final manifest = (metadata['files'] as Map)['manifest'] as Map;
        final stickerItems = (manifest['items'] as List).cast<Map>().where(
          (item) => item['source_table'] == 'custom_stickers',
        );
        expect(stickerItems, hasLength(2));
        expect(
          stickerItems.every(
            (item) =>
                item['kind'] == 'customSticker' &&
                item['criticality'] == 'critical',
          ),
          isTrue,
        );
      } finally {
        await bundle.cleanupExportArtifacts?.call();
      }

      await roundtripMigrationBundle(
        directory: root,
        source: source,
        target: target,
        sourceKeys: sourceKeys,
        targetKeys: targetKeys,
        sessionId: 'custom-sticker-roundtrip',
      );
      // Reopen the real destination file; a seeded verification DB cannot satisfy this.
      await target.close();
      target = await openMigrationProductionDatabase(
        p.join(root.path, 'target.db'),
      );
      expect(await rows(target), before);
      expect(
        await target.rawQuery(
          'SELECT COUNT(*) AS items, SUM(size_bytes) AS bytes FROM custom_stickers',
        ),
        accounting,
      );
      expect(
        (await target.query('identity')).single['peer_id'],
        migrationOwner.peerId,
      );
      expect(
        await targetKeys.read(MigrationSecureStorageRegistry.dbEncryptionKey),
        'target-active-db-key',
      );
      final readOnlyLibrary = SqliteCustomStickerLibrary(
        db: target,
        documentsDirectory: targetDocuments,
        temporaryDirectory: targetTemporary,
        mayUseAccount: () async => true,
      );
      libraries.add(readOnlyLibrary);
      final imported = await readOnlyLibrary.list();
      expect(imported.map((item) => item.id), [first.id, second.id]);
      expect(imported.map((item) => item.position), [0, 1]);
      expect(imported.map((item) => item.asset.frameCount), [1, 2]);
      expect(imported.map((item) => item.asset.durationMs), [0, 167]);
      for (final entry in expectedBytes.entries) {
        final bytes = await File(
          p.join(targetDocuments.path, entry.key),
        ).readAsBytes();
        expect(bytes, entry.value);
        expect(img.decodeWebP(bytes), isNotNull);
        expect(
          await File(p.join(documents.path, entry.key)).readAsBytes(),
          entry.value,
        );
      }
      final importedStickerFiles =
          await Directory(p.join(targetDocuments.path, 'stickers'))
              .list(recursive: true, followLinks: false)
              .where((entry) => entry is File)
              .map(
                (entry) => p.relative(entry.path, from: targetDocuments.path),
              )
              .toList();
      expect(importedStickerFiles, unorderedEquals(expectedBytes.keys));
      for (final entry in extras.entries) {
        expect(
          await File(p.join(targetDocuments.path, entry.key)).exists(),
          isFalse,
        );
        expect(
          await File(p.join(documents.path, entry.key)).readAsBytes(),
          entry.value,
        );
      }
      expect(await rows(source), before);
      expect(await send.file.readAsBytes(), sendBytes);
    },
  );

  for (final corruption in [
    'missing',
    'same-size-tamper',
    'wrong-size',
    'file-link',
    'root-link',
    'read-failure',
  ]) {
    test(
      'BL17 bundle blocks critical $corruption sticker before snapshot without downgrading rows',
      () async {
        expect(kCustomStickersEnabled, isFalse);
        final library = sourceLibrary();
        final sticker = await library.admit(await input(0));
        await library.retire();
        final file = File(sticker.asset.filePath);
        final bytes = await file.readAsBytes();
        final outside = File(p.join(root.path, 'outside.webp'));
        await outside.writeAsBytes(bytes, flush: true);
        File protectedFile = file;
        switch (corruption) {
          case 'missing':
            await file.delete();
            protectedFile = outside;
          case 'same-size-tamper':
            final changed = List<int>.of(bytes);
            changed[bytes.length - 1] ^= 1;
            await file.writeAsBytes(changed, flush: true);
          case 'wrong-size':
            await source.update(
              'custom_stickers',
              {'size_bytes': bytes.length + 1},
              where: 'id = ?',
              whereArgs: [sticker.id],
            );
          case 'file-link':
            await file.delete();
            await Link(file.path).create(outside.path);
            protectedFile = outside;
          case 'root-link':
            final moved = await file.parent.rename(
              p.join(root.path, 'moved-stickers'),
            );
            await Link(file.parent.path).create(moved.path);
            protectedFile = File(p.join(moved.path, p.basename(file.path)));
          case 'read-failure':
            break;
        }
        final before = await rows(source);
        final identityBefore = await source.query('identity');
        final protectedBefore = await protectedFile.readAsBytes();
        final reader = _UnavailableStickerReader(file.path);
        await expectLater(
          exportBundle(reader: corruption == 'read-failure' ? reader : null),
          throwsA(
            isA<AccountMigrationBundleAssemblyException>().having(
              accountMigrationBundleSourceFailureReason,
              'reason',
              'fileManifestBlockingIssues',
            ),
          ),
        );
        expect(snapshot.exports, 0);
        expect(await rows(source), before);
        expect(await source.query('identity'), identityBefore);
        expect(await protectedFile.readAsBytes(), protectedBefore);
        expect(await outside.readAsBytes(), bytes);
        if (corruption == 'missing') expect(await file.exists(), isFalse);
        if (corruption == 'read-failure') expect(reader.failures, 1);
        expect(
          events.where(
            (event) =>
                event['event'] ==
                'ACCOUNT_MIGRATION_BUNDLE_SOURCE_MISSING_MEDIA_DOWNGRADE_START',
          ),
          isEmpty,
        );
        final issues = events
            .where(
              (event) =>
                  event['event'] ==
                  'ACCOUNT_MIGRATION_BUNDLE_SOURCE_FILE_MANIFEST_ISSUE',
            )
            .map((event) => event['details'] as Map)
            .where((issue) => issue['sourceTable'] == 'custom_stickers');
        expect(issues, isNotEmpty);
        expect(
          issues.every(
            (issue) =>
                issue['blocking'] == true && issue['criticality'] == 'critical',
          ),
          isTrue,
        );
      },
    );
  }
}

/// Observes the existing real SQLite-copy seam; it does not invent a snapshot.
final class _SnapshotProbe implements MigrationSqlCipherExportAdapter {
  final _delegate = const MigrationSqliteSnapshotAdapter();
  int exports = 0;
  @override
  Future<MigrationDatabaseCipherMetadata> captureCipherMetadata(Database db) =>
      _delegate.captureCipherMetadata(db);
  @override
  Future<void> exportSqlCipherDatabase({
    required Database sourceDb,
    required String destinationPath,
    required String destinationKey,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) async {
    exports++;
    await _delegate.exportSqlCipherDatabase(
      sourceDb: sourceDb,
      destinationPath: destinationPath,
      destinationKey: destinationKey,
      cipherMetadata: cipherMetadata,
    );
  }

  @override
  Future<Database> openExportedDatabase({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) => _delegate.openExportedDatabase(
    path: path,
    key: key,
    cipherMetadata: cipherMetadata,
  );
  @override
  Future<String> runIntegrityCheck(Database db) =>
      _delegate.runIntegrityCheck(db);
}

final class _UnavailableStickerReader extends IoMigrationEntryFileReader {
  _UnavailableStickerReader(this.stickerPath);
  final String stickerPath;
  int failures = 0;
  @override
  Future<int> length(String path) async {
    if (path == stickerPath) {
      failures++;
      throw FileSystemException('fixture: required sticker became unreadable');
    }
    return super.length(path);
  }
}
