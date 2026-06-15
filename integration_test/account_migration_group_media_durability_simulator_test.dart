import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_bundle_transfer.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/feed/application/load_feed_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '_support/fake_secure_key_store.dart';
import '../test/shared/fakes/in_memory_group_message_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';
import '../test/shared/fakes/in_memory_media_attachment_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _initializeSqliteForCurrentPlatform();

  group('account migration group media durability simulator', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'group_media_durability_sim_',
      );
    });

    tearDown(() async {
      debugSetFlowEventSink(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets(
      'relay-hash group media survives feed refresh and remains bundleable',
      (_) async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink((payload) => events.add(payload));

        final plaintextBytes = utf8.encode('downloaded group plaintext bytes');
        final relayContentHash = sha256
            .convert(utf8.encode('encrypted relay blob bytes'))
            .toString();
        expect(
          relayContentHash,
          isNot(sha256.convert(plaintextBytes).toString()),
        );

        const groupId = 'group-durable';
        const messageId = 'group-message-durable';
        const attachmentId = 'group-media-durable';
        const relativePath = 'media/$groupId/$attachmentId.jpg';
        final mediaFile = File(p.join(tempDir.path, relativePath));
        await mediaFile.parent.create(recursive: true);
        await mediaFile.writeAsBytes(plaintextBytes, flush: true);

        final groupRepo = InMemoryGroupRepository();
        final groupMessageRepo = InMemoryGroupMessageRepository();
        final mediaRepo = InMemoryMediaAttachmentRepository();
        final now = DateTime.utc(2026, 6, 9, 12);

        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Durable Group',
            type: GroupType.chat,
            topicName: 'topic-durable',
            createdAt: now,
            createdBy: 'alice-peer',
            myRole: GroupRole.member,
          ),
        );
        await groupMessageRepo.saveMessage(
          GroupMessage(
            id: messageId,
            groupId: groupId,
            senderPeerId: 'alice-peer',
            senderUsername: 'Alice',
            text: 'media attached',
            timestamp: now,
            status: 'received',
            isIncoming: true,
            createdAt: now,
          ),
        );
        await mediaRepo.saveAttachment(
          _groupAttachment(
            id: attachmentId,
            messageId: messageId,
            relativePath: relativePath,
            size: plaintextBytes.length,
            contentHash: relayContentHash,
            createdAt: now,
          ),
        );

        final feedItems = await loadGroupFeedItems(
          groupRepo: groupRepo,
          groupMsgRepo: groupMessageRepo,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: _TempMediaFileManager(tempDir.path),
        );

        expect(feedItems, hasLength(1));
        final groupThread = feedItems.single;
        expect(groupThread.messages, hasLength(1));
        final feedMedia = groupThread.messages.single.media.single;
        expect(feedMedia.downloadStatus, kMediaDownloadStatusDone);
        expect(feedMedia.localPath, mediaFile.path);
        expect(await mediaFile.exists(), isTrue);
        expect(
          events.map((event) => event['event']),
          contains('GROUP_FEED_MEDIA_PLAINTEXT_HASH_VALIDATION_SKIPPED'),
        );
        expect(
          events.map((event) => event['event']),
          contains('GROUP_FEED_MEDIA_DISPLAY_VERIFY_ALLOWED'),
        );

        final dbs = await _openBundleDatabases(tempDir);
        addTearDown(dbs.close);
        await _createGroupMessagesTable(dbs.sourceDb);
        await _createMediaAttachmentsTable(dbs.sourceDb);
        await dbs.sourceDb.insert('group_messages', {
          'id': messageId,
          'group_id': groupId,
        });
        await dbs.sourceDb.insert('media_attachments', {
          'id': attachmentId,
          'message_id': messageId,
          'mime': 'image/jpeg',
          'size': plaintextBytes.length,
          'media_type': 'image',
          'local_path': relativePath,
          'download_status': 'done',
          'created_at': now.toIso8601String(),
          'content_hash': relayContentHash,
          'encryption_key_base64': _fixtureEncryptionKeyBase64,
          'encryption_nonce': _fixtureEncryptionNonce,
          'encryption_scheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        });

        final bundle = await _bundleSource(
          dbs: dbs,
          documentsRootPath: tempDir.path,
        )(_request());

        expect(await mediaFile.exists(), isTrue);
        expect(
          bundle.manifest.entries
              .where(
                (entry) => entry.kind == MigrationTransferEntryKind.file,
              )
              .map((entry) => entry.relativePath),
          contains(relativePath),
        );
      },
    );

    testWidgets(
      'missing critical group media blocks old-phone bundle assembly',
      (_) async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink((payload) => events.add(payload));

        final dbs = await _openBundleDatabases(tempDir);
        addTearDown(dbs.close);
        await _createGroupMessagesTable(dbs.sourceDb);
        await _createMediaAttachmentsTable(dbs.sourceDb);
        await dbs.sourceDb.insert('group_messages', {
          'id': 'group-message-missing',
          'group_id': 'group-durable',
        });
        await dbs.sourceDb.insert('media_attachments', {
          'id': 'group-media-missing',
          'message_id': 'group-message-missing',
          'mime': 'image/jpeg',
          'size': 128,
          'media_type': 'image',
          'local_path': 'media/group-durable/group-media-missing.jpg',
          'download_status': 'done',
          'created_at': DateTime.utc(2026, 6, 9, 12).toIso8601String(),
          'content_hash': 'a' * 64,
          'encryption_key_base64': _fixtureEncryptionKeyBase64,
          'encryption_nonce': _fixtureEncryptionNonce,
          'encryption_scheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        });

        await expectLater(
          _bundleSource(dbs: dbs, documentsRootPath: tempDir.path)(_request()),
          throwsA(
            isA<AccountMigrationBundleAssemblyException>().having(
              (error) => accountMigrationBundleSourceFailureReason(error),
              'reason',
              'fileManifestBlockingIssues',
            ),
          ),
        );

        final rows = await dbs.sourceDb.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['group-media-missing'],
        );
        expect(rows.single['download_status'], kMediaDownloadStatusDone);
        expect(
          rows.single['local_path'],
          'media/group-durable/group-media-missing.jpg',
        );

        final audit = events.singleWhere(
          (event) =>
              event['event'] ==
              'ACCOUNT_MIGRATION_BUNDLE_SOURCE_RELAY_FREE_MEDIA_AUDIT',
        );
        final auditDetails = audit['details'] as Map<String, dynamic>;
        expect(auditDetails['relayDependencyRisk'], isTrue);
        expect(auditDetails['missingRequiredMediaCount'], 1);
        expect(auditDetails['sanitizedMissingMediaCount'], 0);
        expect(auditDetails['blockingIssueCount'], 1);
      },
    );
  });
}

void _initializeSqliteForCurrentPlatform() {
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
  }
}

MediaAttachment _groupAttachment({
  required String id,
  required String messageId,
  required String relativePath,
  required int size,
  required String contentHash,
  required DateTime createdAt,
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: 'image/jpeg',
    size: size,
    mediaType: 'image',
    localPath: relativePath,
    downloadStatus: kMediaDownloadStatusDone,
    contentHash: contentHash,
    encryptionKeyBase64: _fixtureEncryptionKeyBase64,
    encryptionNonce: _fixtureEncryptionNonce,
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    createdAt: createdAt.toIso8601String(),
  );
}

class _TempMediaFileManager extends MediaFileManager {
  _TempMediaFileManager(this.documentsRootPath);

  final String documentsRootPath;

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (p.isAbsolute(storedPath)) return storedPath;
    return p.join(documentsRootPath, storedPath);
  }
}

class _BundleDatabases {
  _BundleDatabases({
    required this.sourceDb,
    required this.verificationDb,
    required this.sourceStore,
  });

  final sqlcipher.Database sourceDb;
  final sqlcipher.Database verificationDb;
  final FakeSecureKeyStore sourceStore;

  Future<void> close() async {
    if (sourceDb.isOpen) {
      await sourceDb.close();
    }
    if (verificationDb.isOpen) {
      await verificationDb.close();
    }
  }
}

Future<_BundleDatabases> _openBundleDatabases(Directory tempDir) async {
  final sourceDb = await sqlcipher.openDatabase(
    p.join(tempDir.path, 'source.db'),
    version: 1,
    singleInstance: false,
  );
  final verificationDb = await sqlcipher.openDatabase(
    sqlcipher.inMemoryDatabasePath,
    version: 1,
    singleInstance: false,
  );
  await _createIdentityTable(sourceDb);
  await _createIdentityTable(verificationDb);
  final sourceStore = FakeSecureKeyStore();
  for (final key in _requiredSourceKeys) {
    await sourceStore.write(key, 'value:$key');
  }
  return _BundleDatabases(
    sourceDb: sourceDb,
    verificationDb: verificationDb,
    sourceStore: sourceStore,
  );
}

AccountMigrationProductionBundleSource _bundleSource({
  required _BundleDatabases dbs,
  required String documentsRootPath,
}) {
  return AccountMigrationProductionBundleSource(
    sourceDb: dbs.sourceDb,
    primaryStore: dbs.sourceStore,
    documentsRootPath: documentsRootPath,
    exportDirectoryPath: p.join(documentsRootPath, 'exports'),
    snapshotExporter: MigrationDatabaseSnapshotExporter(
      closeExportedDatabaseAfterValidation: false,
      adapter: _RecordingSnapshotExportAdapter(
        verificationDb: dbs.verificationDb,
        snapshotBytes: utf8.encode('snapshot-db-bytes'),
      ),
    ),
    segmentSize: 4096,
  );
}

Future<void> _createIdentityTable(sqlcipher.Database db) async {
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

Future<void> _createGroupMessagesTable(sqlcipher.Database db) async {
  await db.execute('''
CREATE TABLE group_messages (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL
)
''');
}

Future<void> _createMediaAttachmentsTable(sqlcipher.Database db) async {
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

class _RecordingSnapshotExportAdapter
    implements MigrationSqlCipherExportAdapter {
  _RecordingSnapshotExportAdapter({
    required this.verificationDb,
    required this.snapshotBytes,
  });

  final sqlcipher.Database verificationDb;
  final List<int> snapshotBytes;

  @override
  Future<MigrationDatabaseCipherMetadata> captureCipherMetadata(
    sqlcipher.Database db,
  ) async {
    return const MigrationDatabaseCipherMetadata(
      cipherVersion: '4.6.0',
      policy: MigrationDatabaseCipherPolicy.compatible,
    );
  }

  @override
  Future<void> exportSqlCipherDatabase({
    required sqlcipher.Database sourceDb,
    required String destinationPath,
    required String destinationKey,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) async {
    await File(destinationPath).writeAsBytes(snapshotBytes, flush: true);
  }

  @override
  Future<sqlcipher.Database> openExportedDatabase({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) async {
    return verificationDb;
  }

  @override
  Future<String> runIntegrityCheck(sqlcipher.Database db) async => 'ok';
}

const _fixtureEncryptionKeyBase64 =
    'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=';
const _fixtureEncryptionNonce = 'nonce-relay-blob';
