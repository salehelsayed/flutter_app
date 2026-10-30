import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_bundle_transfer.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_coordinator.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_import_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_active_importer.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_secure_storage_key.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/bridge/fake_bridge.dart';
import '../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../contact_request/presentation/support/contact_request_sql_fixture.dart';
import '../contact_request/support/contact_repair_harness.dart';

final migrationOwner = TestEd25519Identity.fromSeedByte(0xD1);
final migrationPeer = TestEd25519Identity.fromSeedByte(0xD2);
const migrationGroupId = 'migration-group';
const migrationVoiceBytes = <int>[17, 42];
String get migrationVoiceRelativePath =>
    MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: migrationPeer.peerId,
      blobId: 'voice',
      mime: 'audio/mp4',
    );
const migrationGroupSecret = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const migrationLocalTranscript = 'LOCAL_TRANSCRIPT_NOT_TRANSFERABLE_E91A';
const migrationLocalTranslation = 'LOCAL_TRANSLATION_NOT_TRANSFERABLE_22FD';

Future<Database> openMigrationProductionDatabase(String path) {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: currentIdentityDatabaseVersion,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    ),
  );
}

/// Durable host storage seam. This is ordinary SQLite, not mobile Keychain or
/// EncryptedSharedPreferences. Production authority/cutover repositories own
/// serialization and decisions; this adapter only persists key/value writes.
final class DurableMigrationKeyStore implements SecureKeyStore {
  DurableMigrationKeyStore._(this.db);
  final Database db;
  void Function(String key, String value)? afterWrite;

  static Future<DurableMigrationKeyStore> open(String path) async {
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE secure_values (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        ),
      ),
    );
    return DurableMigrationKeyStore._(db);
  }

  Future<DurableMigrationKeyStore> reopen() async {
    final path = db.path;
    await db.close();
    return open(path);
  }

  Future<void> close() => db.close();

  @override
  Future<String?> read(String key) async {
    final rows = await db.query(
      'secure_values',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  @override
  Future<void> write(String key, String value) async {
    await db.insert('secure_values', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    afterWrite?.call(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await db.delete('secure_values', where: 'key = ?', whereArgs: [key]);
  }

  @override
  Future<bool> containsKey(String key) async => await read(key) != null;

  SecureKeyStoreAccountMigrationAuthorityRepository get authority =>
      SecureKeyStoreAccountMigrationAuthorityRepository(secureKeyStore: this);
  SecureKeyStoreMigrationCutoverRepository get cutover =>
      SecureKeyStoreMigrationCutoverRepository(secureKeyStore: this);
  MigrationCutoverCoordinator get coordinator => MigrationCutoverCoordinator(
    authorityRepository: authority,
    cutoverRepository: cutover,
  );
  AccountMigrationRuntimeNetworkGate get networkGate =>
      AccountMigrationRuntimeNetworkGate(authorityRepository: authority);
}

/// Same byte-copy seam as the existing snapshot-export sanitation test. It
/// intentionally makes no native SQLCipher/encryption claim.
final class MigrationSqliteSnapshotAdapter
    implements MigrationSqlCipherExportAdapter, MigrationStagedDatabaseOpener {
  const MigrationSqliteSnapshotAdapter();

  @override
  Future<MigrationDatabaseCipherMetadata> captureCipherMetadata(
    Database db,
  ) async => const MigrationDatabaseCipherMetadata(
    cipherVersion: 'host-sqlite-copy-fixture',
    policy: MigrationDatabaseCipherPolicy.compatible,
  );

  @override
  Future<void> exportSqlCipherDatabase({
    required Database sourceDb,
    required String destinationPath,
    required String destinationKey,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) async {
    await sourceDb.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    await File(sourceDb.path).copy(destinationPath);
  }

  @override
  Future<Database> openExportedDatabase({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) => open(path: path, key: key, cipherMetadata: cipherMetadata);

  @override
  Future<Database> open({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) => databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(singleInstance: false),
  );

  @override
  Future<String> runIntegrityCheck(Database db) async =>
      (await db.rawQuery('PRAGMA quick_check')).single.values.single as String;
}

List<MigrationSecureStorageKey> migrationPortableKeys() => [
  for (final name in [
    MigrationSecureStorageRegistry.dbEncryptionKey,
    MigrationSecureStorageRegistry.identityPrivateKey,
    MigrationSecureStorageRegistry.identityMnemonic12,
    MigrationSecureStorageRegistry.identityMlKemSecretKey,
  ])
    MigrationSecureStorageRegistry.fixedKey(
      scope: MigrationSecureStoreScope.primary,
      activeKey: name,
    )!,
  MigrationSecureStorageRegistry.primaryGroupKeyMaterial(
    groupId: migrationGroupId,
    generation: 7,
  ),
  MigrationSecureStorageRegistry.primaryMediaAttachmentKey(
    attachmentId: 'voice',
  ),
];

Future<void> seedMigrationAccount(
  Database db,
  DurableMigrationKeyStore keys, {
  required String documentsRootPath,
}) async {
  final voice = File('$documentsRootPath/$migrationVoiceRelativePath');
  await voice.parent.create(recursive: true);
  await voice.writeAsBytes(migrationVoiceBytes, flush: true);
  await buildWidgetIdentityRepository(db, keys).saveIdentity(
    testIdentityModel(
      migrationOwner,
      username: 'Migrating Alice',
      mlKemPublicKey: 'owner-mlkem',
    ),
  );
  await keys.write(
    MigrationSecureStorageRegistry.dbEncryptionKey,
    'host-copy-key',
  );
  await keys.write(
    groupKeyMaterialStoreName(migrationGroupId, 7),
    migrationGroupSecret,
  );
  await keys.write(
    mediaAttachmentEncryptionKeyStoreName('voice'),
    'voice-secret',
  );
  await databaseContactRepository(
    db,
  ).addContact(contactFor(migrationPeer, mlKem: 'peer-current-mlkem'));
  final now = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
  final iso = now.toIso8601String();
  for (final incoming in [true, false]) {
    await db.insert('messages', {
      'id': incoming ? 'direct-unread' : 'direct-pending',
      'contact_peer_id': migrationPeer.peerId,
      'sender_peer_id': incoming ? migrationPeer.peerId : migrationOwner.peerId,
      'text': incoming ? 'Imported direct history' : 'Pending direct retry',
      'timestamp': iso,
      'created_at': iso,
      'is_incoming': incoming ? 1 : 0,
      'status': incoming ? 'delivered' : 'failed',
    });
  }
  await db.insert('groups', {
    'id': migrationGroupId,
    'name': 'Imported group',
    'type': 'chat',
    'topic_name': 'migration-topic',
    'created_at': iso,
    'created_by': migrationOwner.peerId,
    'my_role': 'admin',
  });
  for (final member in [migrationOwner, migrationPeer]) {
    await db.insert('group_members', {
      'group_id': migrationGroupId,
      'peer_id': member.peerId,
      'username': 'Member',
      'role': member == migrationOwner ? 'admin' : 'writer',
      'public_key': member.publicKey,
      'joined_at': iso,
    });
  }
  await db.insert('group_keys', {
    'group_id': migrationGroupId,
    'key_generation': 7,
    'encrypted_key': secureStoreReferenceForKey(
      groupKeyMaterialStoreName(migrationGroupId, 7),
    ),
    'created_at': iso,
  });
  for (final incoming in [true, false]) {
    await db.insert('group_messages', {
      'id': incoming ? 'group-unread' : 'group-pending',
      'group_id': migrationGroupId,
      'sender_peer_id': incoming ? migrationPeer.peerId : migrationOwner.peerId,
      'text': incoming ? 'Imported group history' : 'Pending group retry',
      'timestamp': iso,
      'created_at': iso,
      'key_generation': 7,
      'is_incoming': incoming ? 1 : 0,
      'status': incoming ? 'delivered' : 'failed',
      if (!incoming)
        'wire_envelope': jsonEncode({
          'groupId': migrationGroupId,
          'text': 'Pending group retry',
          'senderPeerId': migrationOwner.peerId,
          'senderUsername': 'Migrating Alice',
          'messageId': 'group-pending',
        }),
    });
  }
  await db.insert('media_attachments', {
    'id': 'voice',
    'message_id': 'direct-unread',
    'mime': 'audio/mp4',
    'size': 2,
    'media_type': 'audio',
    'duration_ms': 1000,
    'local_path': migrationVoiceRelativePath,
    'download_status': 'done',
    'created_at': iso,
    'owner_lane': 'direct',
    'encryption_key_base64': secureStoreReferenceForKey(
      mediaAttachmentEncryptionKeyStoreName('voice'),
    ),
    'encryption_nonce': base64Encode(List<int>.filled(12, 0)),
    'encryption_scheme': 'blob_aes_256_gcm_v1',
    'content_hash': sha256.convert(migrationVoiceBytes).toString(),
    'local_transcript': migrationLocalTranscript,
  });
}

Future<R> _inlineMigrationWork<R>(R Function() work) async => work();

/// Drives the existing production entry-streamed bundle APIs. Transport KEM is
/// the existing FakeBridge seam; file manifests, chunk hashes, receiver file
/// renames, sanitation, staging, promotion and cutover remain production code.
Future<void> roundtripMigrationBundle({
  required Directory directory,
  required Database source,
  required Database target,
  required DurableMigrationKeyStore sourceKeys,
  required DurableMigrationKeyStore targetKeys,
  required String sessionId,
}) async {
  final createdAt = DateTime.now().toUtc();
  final transcript = AuthenticatedMigrationChannelTranscript(
    sessionId: sessionId,
    newPhoneEphemeralPublicKey: 'fixture-new-public',
    oldPhonePeerId: migrationOwner.peerId,
    authenticatedChannelBinding: 'fixture-channel-binding',
    authorizationNonce: 'fixture-nonce',
  );
  final pending = MigrationPendingPairingSession(
    sessionId: sessionId,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(minutes: 5)),
    newPhoneEphemeralPublicKey: transcript.newPhoneEphemeralPublicKey,
    newPhoneEphemeralSecretKey: 'fixture-new-secret',
  );
  await sourceKeys.coordinator.markExportingNetworkPaused(
    accountPeerId: migrationOwner.peerId,
  );
  final bundle = await AccountMigrationProductionBundleSource(
    sourceDb: source,
    primaryStore: sourceKeys,
    documentsRootPath: '${directory.path}/source-documents',
    exportDirectoryPath: '${directory.path}/exports',
    snapshotExporter: const MigrationDatabaseSnapshotExporter(
      adapter: MigrationSqliteSnapshotAdapter(),
    ),
    segmentSize: 64 * 1024,
  )(AccountMigrationTransferRequest(transcript: transcript));
  final crypto = BridgeMigrationStreamCrypto(
    bridge: FakeBridge(),
    executeChunkWork: _inlineMigrationWork,
  );
  final staging = MigrationSecureStorageStaging(primaryStore: targetKeys);
  final receiver = AccountMigrationProductionBundleReceiver(
    streamCrypto: crypto,
    secureStorageStaging: staging,
    databaseImportStaging: MigrationDatabaseImportStaging(
      secureStorageStaging: staging,
      opener: const MigrationSqliteSnapshotAdapter(),
    ),
    activeDatabaseImporter: MigrationDatabaseActiveImporter(
      activeDatabase: target,
    ),
    cutoverCoordinator: targetKeys.coordinator,
    authorityRepository: targetKeys.authority,
    stagingDirectoryPath: '${directory.path}/incoming',
    documentsRootPath: '${directory.path}/target-documents',
  );
  try {
    expect(
      bundle.manifest.entries.where(
        (entry) => entry.relativePath == migrationVoiceRelativePath,
      ),
      hasLength(1),
      reason: 'the real required media file must be in the bundle',
    );
    expect(
      await receiver.acceptManifest(
        manifest: bundle.manifest,
        transcript: transcript,
        pendingSession: pending,
      ),
      isTrue,
    );
    final encryption = await crypto.encapsulateSession(
      recipientMlKemPublicKey: transcript.newPhoneEphemeralPublicKey,
      sessionId: sessionId,
      bundleId: bundle.manifest.bundleId,
      direction: MigrationStreamDirection.oldToNew,
    );
    final entries = {
      for (final entry in bundle.streamingEntries) entry.entryId: entry,
    };
    for (var ordinal = 0; ordinal < bundle.manifest.entries.length; ordinal++) {
      final descriptor = bundle.manifest.entries[ordinal];
      if (descriptor.sizeBytes == 0) continue;
      var offset = 0;
      var index = 0;
      await for (final plaintext in entries[descriptor.entryId]!.openChunks()) {
        final chunk = await crypto.encryptChunk(
          session: encryption,
          plaintext: plaintext,
          associatedData: MigrationChunkAssociatedData(
            sessionId: sessionId,
            bundleId: bundle.manifest.bundleId,
            entryId: descriptor.entryId,
            chunkIndex: index,
            offset: offset,
            isFinal: offset + plaintext.length >= descriptor.sizeBytes,
          ),
          nonce: migrationChunkNonceBase64(
            entryOrdinal: ordinal,
            chunkIndex: index,
          ),
        );
        final outcome = await receiver.acceptChunk(
          manifest: bundle.manifest,
          chunk: chunk,
          transcript: transcript,
          pendingSession: pending,
        );
        expect(
          outcome.isAccepted,
          isTrue,
          reason: '${descriptor.entryId}/$index: ${outcome.code}',
        );
        offset += plaintext.length;
        index++;
      }
    }
    expect(
      await receiver.complete(
        manifest: bundle.manifest,
        transcript: transcript,
        pendingSession: pending,
      ),
      isTrue,
    );
    expect(
      await targetKeys.networkGate.allowsAccountNetworkSideEffects(
        peerId: migrationOwner.peerId,
        operation: 'pending_retry',
      ),
      isFalse,
    );
    final oldProof = await sourceKeys.coordinator.markOldNetworkBlocked(
      sessionId: sessionId,
      accountPeerId: migrationOwner.peerId,
      devicePeerId: 'old-fixture-device',
    );
    final newProof = await receiver.acceptOldBlockProof(
      manifest: bundle.manifest,
      transcript: transcript,
      pendingSession: pending,
      oldBlockProof: oldProof,
    );
    expect(newProof?.provesNewActiveCommitted, isTrue);
    await sourceKeys.coordinator.markOldMigratedOutAfterNewActive(
      sessionId: sessionId,
      accountPeerId: migrationOwner.peerId,
      devicePeerId: 'old-fixture-device',
      newActiveProof: newProof!,
      leaseCleanup: MigrationCutoverLeaseCleanup(
        clearLocalStalePushToken: () async {},
        unregisterPersonalRendezvous: () async {},
        unregisterInboxPushToken: () async {},
      ),
    );
    expect(
      await File(
        '${directory.path}/target-documents/$migrationVoiceRelativePath',
      ).readAsBytes(),
      migrationVoiceBytes,
    );
  } finally {
    await bundle.cleanupExportArtifacts?.call();
  }
}
