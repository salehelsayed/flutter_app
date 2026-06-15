// Full Move Account end-to-end host test: QR pairing → transfer → cutover.
//
// The 124 Phase-8 "migration_full_transfer" gap asked for a single flow that
// stitches the three legs the existing slice tests cover only in isolation:
//   * QR pairing (migration_qr_payload_use_case): build → serialize → scan-
//     parse → confirmation-code match → consume,
//   * the live-wire transfer (account_migration_end_to_end already proves a
//     REAL in-process LocalWsServer runs GREEN on the plain Dart VM — the
//     trick is to NOT call ensureInitialized(), which would install
//     HttpOverrides that break the sender's real HttpClient), and
//   * the cutover hand-off (migration_cutover_coordinator) old→migratedOut /
//     new→active.
//
// The existing account_migration_end_to_end_test hand-builds the QR payload
// and saves the pending session directly, so it never exercises the production
// QR build (FakeBridge mlkem.keygen + repo persist) nor the scan-parse path
// nor the human confirmation code. THIS test drives all of those through the
// real use-cases (buildMigrationQrPayload / parseMigrationQrPayload /
// deriveMigrationPairingConfirmationCode) over the REAL
// SecureKeyStoreMigrationPairingSessionRepository, then feeds the parsed
// payload + persisted pending session into the real chained transfer + cutover.
//
// Only the two platform seams are faked, via their existing injection points:
//   * the SQLCipher snapshot adapter / staged opener (plain ffi sqlite:
//     VACUUM INTO produces a REAL snapshot of the source DB), and
//   * the ML-KEM segment crypto (deterministic reversible scheme; real hash
//     pipeline via the production BridgeMigrationStreamCrypto over FakeBridge).
//
// NOTE: no TestWidgetsFlutterBinding.ensureInitialized() — the flutter_test
// binding installs HttpOverrides that break the sender's real HttpClient.

import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_bundle_transfer.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_local_transfer_runtime.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_cutover_coordinator.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_active_importer.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_import_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_database_snapshot_exporter.dart';
import 'package:flutter_app/features/account_migration/application/migration_export_authorization.dart';
import 'package:flutter_app/features/account_migration/application/migration_pairing_session_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/migration_qr_payload_use_case.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_cutover_record.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_database_manifest.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/account_migration_authority_repository.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_cutover_repository.dart';
import 'package:flutter_app/features/account_migration/domain/repositories/migration_pairing_session_repository.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/bridge/fake_bridge.dart';
import '../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Move Account full flow (QR pairing → transfer → cutover)', () {
    late Directory tempDir;
    late Database sourceDb;
    late Database activeDb;
    late FakeSecureKeyStore sourceStore;
    late FakeSecureKeyStore destinationStore;
    late Map<String, LocalPeer> registry;
    late SecureKeyStoreMigrationPairingSessionRepository pairingRepo;
    late LocalWsServer newPhoneServer;
    late LocalWsServer oldPhoneServer;
    late _SharedFakeDiscovery newPhoneDiscovery;
    late _SharedFakeDiscovery oldPhoneDiscovery;
    late List<Map<String, dynamic>> flowEvents;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'account_migration_full_',
      );
      sourceDb = await openDatabase(
        p.join(tempDir.path, 'source.db'),
        version: 1,
        singleInstance: false,
      );
      activeDb = await openDatabase(
        p.join(tempDir.path, 'active.db'),
        version: 1,
        singleInstance: false,
      );
      for (final db in [sourceDb, activeDb]) {
        await _createSchema(db);
      }
      await _seedSourceAccount(sourceDb, tempDir);
      await activeDb.insert('identity', {
        'id': 1,
        'peer_id': 'new-temp-peer',
        'public_key': 'new-public',
        'username': 'new-temp',
      });

      sourceStore = FakeSecureKeyStore();
      destinationStore = FakeSecureKeyStore();
      for (final key in const [
        MigrationSecureStorageRegistry.dbEncryptionKey,
        MigrationSecureStorageRegistry.identityPrivateKey,
        MigrationSecureStorageRegistry.identityMnemonic12,
        MigrationSecureStorageRegistry.identityMlKemSecretKey,
      ]) {
        await sourceStore.write(key, 'value:$key');
      }
      await sourceStore.write(
        'group_key_material:group-1:1',
        'group-key-material-value',
      );
      await destinationStore.write(
        MigrationSecureStorageRegistry.dbEncryptionKey,
        'new-active-db-key',
      );

      registry = <String, LocalPeer>{};
      // The PRODUCTION pairing repository, backed by the new phone's secure
      // store — the QR build persists its ephemeral key pair here, and the
      // receiver loads it back by sessionId.
      pairingRepo = SecureKeyStoreMigrationPairingSessionRepository(
        secureKeyStore: destinationStore,
      );
      newPhoneServer = LocalWsServer();
      oldPhoneServer = LocalWsServer();
      newPhoneDiscovery = _SharedFakeDiscovery(registry);
      oldPhoneDiscovery = _SharedFakeDiscovery(registry);
      flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
    });

    tearDown(() async {
      debugSetFlowEventSink(null);
      await newPhoneServer.stop();
      await oldPhoneServer.stop();
      newPhoneDiscovery.dispose();
      oldPhoneDiscovery.dispose();
      if (sourceDb.isOpen) await sourceDb.close();
      if (activeDb.isOpen) await activeDb.close();
      await tempDir.delete(recursive: true);
    });

    test(
      'a scanned QR pairs the phones, then the account moves and cuts over',
      () async {
        // ---------- new phone: PRODUCTION QR build ----------
        // FakeBridge stands in for the ML-KEM keygen native command; the rest
        // (session id, expiry, persistence, qr json) is real production code.
        final bridge = FakeBridge();
        bridge.responses['mlkem.keygen'] = {
          'ok': true,
          'publicKey': 'np-ephemeral-public',
          'secretKey': 'np-ephemeral-secret',
        };
        final (buildResult, buildOutput) = await buildMigrationQrPayload(
          bridge: bridge,
          repository: pairingRepo,
          sessionIdProvider: () => 'full-flow-session',
          now: () => DateTime.now().toUtc(),
          ttl: const Duration(minutes: 5),
          channelNonce: 'channel-nonce',
        );
        expect(buildResult, BuildMigrationQrPayloadResult.success);
        expect(buildOutput, isNotNull);
        expect(bridge.commandLog, contains('mlkem.keygen'));
        // The ephemeral SECRET must never leave the new phone via the QR.
        expect(buildOutput!.qrJson, isNot(contains('np-ephemeral-secret')));

        // The pending session is durably persisted by the real repo.
        final persistedPending = await pairingRepo.loadPendingNewPhoneSession(
          'full-flow-session',
        );
        expect(persistedPending, isNotNull);
        expect(
          persistedPending!.newPhoneEphemeralSecretKey,
          'np-ephemeral-secret',
        );

        // ---------- old phone: SCAN + PARSE the QR ----------
        // The old phone receives only the qr json string (camera scan) and
        // parses it back through the production parser — the leg the existing
        // end-to-end test skipped by hand-building the payload.
        final (parseResult, scannedPayload) = parseMigrationQrPayload(
          qrData: buildOutput.qrJson,
          now: () => DateTime.now().toUtc(),
        );
        expect(parseResult, MigrationQrParseResult.success);
        expect(scannedPayload, isNotNull);
        expect(scannedPayload!.sessionId, 'full-flow-session');
        expect(
          scannedPayload.newPhoneEphemeralPublicKey,
          'np-ephemeral-public',
        );
        expect(scannedPayload.channelNonce, 'channel-nonce');

        // ---------- human pairing confirmation gate ----------
        // Both phones derive the 6-digit code independently: the new phone
        // from its built payload, the old phone from the scanned payload.
        final newPhoneCode = deriveMigrationPairingConfirmationCode(
          buildOutput.payload,
        );
        final oldPhoneCode = deriveMigrationPairingConfirmationCode(
          scannedPayload,
        );
        expect(newPhoneCode, matches(RegExp(r'^\d{6}$')));
        expect(
          oldPhoneCode,
          newPhoneCode,
          reason: 'both phones must show the same pairing code',
        );

        // ---------- new phone: start the receiver on the built QR ----------
        final destinationDocumentsPath = p.join(
          tempDir.path,
          'destination-documents',
        );
        final newAuthority = _MemoryAuthorityRepository();
        final newCutoverRepo = _MemoryCutoverRepository();
        final receiver = AccountMigrationProductionBundleReceiver(
          streamCrypto: _e2eStreamCrypto(),
          secureStorageStaging: MigrationSecureStorageStaging(
            primaryStore: destinationStore,
          ),
          databaseImportStaging: MigrationDatabaseImportStaging(
            secureStorageStaging: MigrationSecureStorageStaging(
              primaryStore: destinationStore,
            ),
            opener: _FfiStagedDatabaseOpener(),
          ),
          activeDatabaseImporter: MigrationDatabaseActiveImporter(
            activeDatabase: activeDb,
          ),
          cutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: newAuthority,
            cutoverRepository: newCutoverRepo,
            now: () => DateTime.utc(2026, 6, 10, 12),
          ),
          authorityRepository: newAuthority,
          stagingDirectoryPath: p.join(tempDir.path, 'incoming'),
          documentsRootPath: destinationDocumentsPath,
        );
        final receiverEvents = <AccountMigrationReceiverEvent>[];
        final newRuntime = AccountMigrationLocalTransferRuntime(
          discovery: newPhoneDiscovery,
          wsServer: newPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleReceiver: receiver,
        );
        final eventsSub = newRuntime.receiverEvents.listen(receiverEvents.add);
        addTearDown(eventsSub.cancel);
        newPhoneServer.configureMigrationTransferHandler(
          newRuntime.handleMigrationTransferRequest,
        );
        expect(
          (await newRuntime.startNewPhoneReceiver(buildOutput)).isStarted,
          isTrue,
        );

        // ---------- old phone: run the transfer over the real wire ----------
        // The transcript is built from the SCANNED payload (not the built
        // one) — proving the parsed-on-the-old-phone data drives the move.
        final oldAuthority = _MemoryAuthorityRepository();
        final oldCutoverRepo = _MemoryCutoverRepository();
        final source = AccountMigrationProductionBundleSource(
          sourceDb: sourceDb,
          primaryStore: sourceStore,
          documentsRootPath: tempDir.path,
          exportDirectoryPath: p.join(tempDir.path, 'exports'),
          snapshotExporter: MigrationDatabaseSnapshotExporter(
            adapter: _FfiSnapshotExportAdapter(),
          ),
          segmentSize: 4096,
        );
        final oldRuntime = AccountMigrationLocalTransferRuntime(
          discovery: oldPhoneDiscovery,
          wsServer: oldPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleSource: source.call,
          streamCrypto: _e2eStreamCrypto(),
          oldPhoneCutoverCoordinator: MigrationCutoverCoordinator(
            authorityRepository: oldAuthority,
            cutoverRepository: oldCutoverRepo,
            now: () => DateTime.utc(2026, 6, 10, 12),
          ),
          oldPhoneLeaseCleanup: _noopLeaseCleanup(),
        );

        final progress = <AccountMigrationTransferStep>[];
        final result = await oldRuntime.runOldPhoneTransfer(
          request: AccountMigrationTransferRequest(
            transcript: _transcriptFromScanned(scannedPayload),
          ),
          onProgress: progress.add,
          isCancelled: () => false,
        );

        // ---------- transfer + cutover outcome ----------
        expect(result.isSuccess, isTrue, reason: result.safeMessage);
        expect(
          progress,
          containsAllInOrder(const [
            AccountMigrationTransferStep.connecting,
            AccountMigrationTransferStep.transferringDatabase,
            AccountMigrationTransferStep.finishing,
          ]),
        );

        // New phone is now the active authority; old phone has ceded.
        expect(
          newAuthority.saved?.state,
          AccountMigrationAuthorityState.active,
        );
        expect(newCutoverRepo.saved?.provesNewActiveCommitted, isTrue);
        expect(
          oldAuthority.saved?.state,
          AccountMigrationAuthorityState.migratedOut,
        );
        expect(oldCutoverRepo.saved?.oldMigratedOutCommitted, isTrue);

        // Receiver reached the activated terminal stage exactly once.
        expect(
          receiverEvents
              .where(
                (event) =>
                    event.type ==
                    AccountMigrationReceiverEventType.activated,
              )
              .length,
          1,
        );
        for (final event in receiverEvents) {
          expect(event.sessionId, 'full-flow-session');
        }

        // ---------- the pairing session is now consumable / one-shot ----------
        // After a successful pairing the QR must be burnt: consuming it once
        // succeeds, a replay reports alreadyConsumed.
        final firstConsume = await pairingRepo.consumeSession(
          payload: scannedPayload,
          consumedAt: DateTime.now().toUtc(),
        );
        expect(firstConsume, MigrationPairingSessionConsumeResult.consumed);
        final replayConsume = await pairingRepo.consumeSession(
          payload: scannedPayload,
          consumedAt: DateTime.now().toUtc(),
        );
        expect(
          replayConsume,
          MigrationPairingSessionConsumeResult.alreadyConsumed,
        );
        expect(await pairingRepo.isSessionConsumed('full-flow-session'), isTrue);

        // ---------- real account data arrived on the new phone ----------
        final identityRows = await activeDb.query('identity');
        expect(identityRows, hasLength(1));
        expect(identityRows.single['peer_id'], 'old-peer');
        expect(identityRows.single['username'], 'alice');

        for (final relativePath in const [
          'media/peer-bob/blob-imported.jpg',
          'media/group-1/blob-group.jpg.enc',
        ]) {
          final sourceBytes = await File(
            p.join(tempDir.path, relativePath),
          ).readAsBytes();
          final importedBytes = await File(
            p.join(destinationDocumentsPath, relativePath),
          ).readAsBytes();
          expect(
            importedBytes,
            sourceBytes,
            reason: '$relativePath must arrive byte-identical',
          );
        }

        // Secrets promoted to the new phone; its own DB key is preserved.
        expect(
          await destinationStore.read('identity_private_key'),
          'value:identity_private_key',
        );
        expect(
          await destinationStore.read('db_encryption_key'),
          'new-active-db-key',
          reason: 'the migrated source DB key must never replace the new key',
        );
      },
    );

    test(
      'an expired scanned QR is rejected before any pairing or transfer',
      () async {
        // QR-pairing leg edge: the parser fails closed on an expired code, so
        // the old phone never enters the transfer. Proven host-side (pure
        // time math, no wire), pinning the production parser gate.
        final bridge = FakeBridge();
        bridge.responses['mlkem.keygen'] = {
          'ok': true,
          'publicKey': 'np-ephemeral-public',
          'secretKey': 'np-ephemeral-secret',
        };
        final expiredAnchor = DateTime.utc(2026, 6, 10, 12);
        final (buildResult, buildOutput) = await buildMigrationQrPayload(
          bridge: bridge,
          repository: pairingRepo,
          sessionIdProvider: () => 'expired-session',
          now: () => expiredAnchor,
          ttl: const Duration(minutes: 5),
        );
        expect(buildResult, BuildMigrationQrPayloadResult.success);

        // The old phone scans the same QR ten minutes later — past expiry.
        final (parseResult, parsed) = parseMigrationQrPayload(
          qrData: buildOutput!.qrJson,
          now: () => expiredAnchor.add(const Duration(minutes: 10)),
        );
        expect(parseResult, MigrationQrParseResult.expired);
        expect(parsed, isNull);

        // And the new phone's own receiver also refuses to start on an expired
        // QR (the runtime's own expiry gate), so neither side proceeds.
        final newRuntime = AccountMigrationLocalTransferRuntime(
          discovery: newPhoneDiscovery,
          wsServer: newPhoneServer,
          pairingSessionRepository: pairingRepo,
          bundleReceiver: _UnusedReceiver(),
          now: () => expiredAnchor.add(const Duration(minutes: 10)),
        );
        final startResult = await newRuntime.startNewPhoneReceiver(buildOutput);
        expect(startResult.isStarted, isFalse);
        expect(
          startResult.failureCode,
          AccountMigrationReceiverStartFailureCode.sessionExpired,
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Fixture: schema + seeded source account
// ---------------------------------------------------------------------------

Future<void> _createSchema(Database db) async {
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

Future<void> _seedSourceAccount(Database db, Directory documentsRoot) async {
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
    'text': '',
    'timestamp': createdAt,
    'status': 'sent',
    'is_incoming': 0,
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
  await db.insert('media_attachments', {
    'id': 'blob-imported',
    'message_id': 'message-1',
    'mime': 'image/jpeg',
    'size': 5,
    'media_type': 'image',
    'local_path': 'media/peer-bob/blob-imported.jpg',
    'download_status': 'done',
    'created_at': createdAt,
  });
  await _writeRelative(
    documentsRoot,
    'media/peer-bob/blob-imported.jpg',
    'image',
  );
  await db.insert('media_attachments', {
    'id': 'blob-group',
    'message_id': 'group-message-1',
    'mime': 'image/jpeg',
    'size': 11,
    'media_type': 'image',
    'local_path': 'media/group-1/blob-group.jpg',
    'download_status': 'done',
    'created_at': createdAt,
    'content_hash': 'a' * 64,
    'encryption_key_base64': 'media-key',
    'encryption_nonce': 'nonce',
    'encryption_scheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  });
  await _writeRelative(
    documentsRoot,
    'media/group-1/blob-group.jpg.enc',
    'encrypted-group-image',
  );
}

Future<void> _writeRelative(
  Directory root,
  String relativePath,
  String contents,
) async {
  final file = File(p.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsString(contents, flush: true);
}

// ---------------------------------------------------------------------------
// Pairing transcript derived from the SCANNED payload (old-phone side).
// ---------------------------------------------------------------------------

AuthenticatedMigrationChannelTranscript _transcriptFromScanned(
  MigrationQrPayload scanned,
) {
  return AuthenticatedMigrationChannelTranscript(
    sessionId: scanned.sessionId,
    newPhoneEphemeralPublicKey: scanned.newPhoneEphemeralPublicKey,
    oldPhonePeerId: 'old-peer',
    authenticatedChannelBinding: 'binding',
    authorizationNonce: scanned.channelNonce ?? 'nonce',
  );
}

MigrationCutoverLeaseCleanup _noopLeaseCleanup() {
  return MigrationCutoverLeaseCleanup(
    unregisterPersonalRendezvous: () async {},
    unregisterInboxPushToken: () async {},
    clearLocalStalePushToken: () async {},
  );
}

// ---------------------------------------------------------------------------
// The two allowed platform-seam fakes (SQLCipher via plain ffi sqlite).
// ---------------------------------------------------------------------------

class _FfiSnapshotExportAdapter implements MigrationSqlCipherExportAdapter {
  @override
  Future<MigrationDatabaseCipherMetadata> captureCipherMetadata(
    Database db,
  ) async {
    return const MigrationDatabaseCipherMetadata(
      cipherVersion: '4.6.0',
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
    final escaped = destinationPath.replaceAll("'", "''");
    await sourceDb.execute("VACUUM INTO '$escaped'");
  }

  @override
  Future<Database> openExportedDatabase({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
  }

  @override
  Future<String> runIntegrityCheck(Database db) async {
    final rows = await db.rawQuery('PRAGMA quick_check');
    return rows.first.values.first.toString();
  }
}

class _FfiStagedDatabaseOpener implements MigrationStagedDatabaseOpener {
  @override
  Future<Database> open({
    required String path,
    required String key,
    required MigrationDatabaseCipherMetadata cipherMetadata,
  }) {
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
  }
}

Future<R> _inlineChunkWork<R>(R Function() work) async => work();

/// Deterministic reversible stream crypto with the REAL hash/AAD pipeline:
/// the production [BridgeMigrationStreamCrypto] over the FakeBridge's
/// deterministic migration command fakes.
BridgeMigrationStreamCrypto _e2eStreamCrypto() {
  return BridgeMigrationStreamCrypto(
    bridge: FakeBridge(retainMessageLog: false),
    executeChunkWork: _inlineChunkWork,
  );
}

// ---------------------------------------------------------------------------
// In-memory authority + cutover repos and shared discovery.
// ---------------------------------------------------------------------------

class _SharedFakeDiscovery implements LocalDiscoveryService {
  final Map<String, LocalPeer> registry;
  final _controller = StreamController<Map<String, LocalPeer>>.broadcast();
  String? advertisedPeerId;

  _SharedFakeDiscovery(this.registry);

  @override
  Future<void> startAdvertising(String peerId, int wsPort) async {
    advertisedPeerId = peerId;
    registry[peerId] = LocalPeer(
      peerId: peerId,
      host: 'localhost',
      port: wsPort,
      discoveredAt: DateTime.now().toUtc(),
    );
    _controller.add(Map<String, LocalPeer>.from(registry));
  }

  @override
  Future<void> stopAdvertising() async {
    final peerId = advertisedPeerId;
    if (peerId != null) {
      registry.remove(peerId);
      advertisedPeerId = null;
    }
    _controller.add(Map<String, LocalPeer>.from(registry));
  }

  @override
  Stream<Map<String, LocalPeer>> get discoveredPeersStream =>
      _controller.stream;

  @override
  Map<String, LocalPeer> get discoveredPeers =>
      Map<String, LocalPeer>.from(registry);

  @override
  bool isLocalPeer(String peerId) => registry.containsKey(peerId);

  @override
  LocalPeer? getLocalPeer(String peerId) => registry[peerId];

  @override
  Future<LocalPeer?> resolvePeer(
    String peerId, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final peer = registry[peerId];
      if (peer != null) return peer;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return registry[peerId];
  }

  @override
  void dispose() {
    _controller.close();
  }
}

class _MemoryAuthorityRepository
    implements AccountMigrationAuthorityRepository {
  AccountMigrationAuthorityRecord? saved;
  final history = <AccountMigrationAuthorityRecord>[];

  @override
  Future<void> clearAuthority() async {
    saved = null;
  }

  @override
  Future<AccountMigrationAuthorityRecord?> loadAuthority() async => saved;

  @override
  Future<void> saveAuthority(AccountMigrationAuthorityRecord record) async {
    saved = record;
    history.add(record);
  }
}

class _MemoryCutoverRepository implements MigrationCutoverRepository {
  MigrationCutoverRecord? saved;

  @override
  Future<void> clearCutover() async {
    saved = null;
  }

  @override
  Future<MigrationCutoverRecord?> loadCutover() async => saved;

  @override
  Future<void> saveCutover(MigrationCutoverRecord record) async {
    saved = record;
  }
}

/// Never invoked: the expired-QR test refuses to start before any transfer.
class _UnusedReceiver implements AccountMigrationLocalBundleReceiver {
  @override
  Future<bool> acceptTranscript({
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async => throw StateError('receiver must not be used on an expired QR');

  @override
  Future<bool> acceptManifest({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async => throw StateError('receiver must not be used on an expired QR');

  @override
  Future<bool> acceptSegment({
    required MigrationTransferManifest manifest,
    required MigrationEncryptedSegment segment,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async => throw StateError('receiver must not be used on an expired QR');

  @override
  Future<bool> complete({
    required MigrationTransferManifest manifest,
    required AuthenticatedMigrationChannelTranscript transcript,
    required MigrationPendingPairingSession pendingSession,
  }) async => throw StateError('receiver must not be used on an expired QR');
}
