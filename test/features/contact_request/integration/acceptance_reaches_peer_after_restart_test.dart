import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contact_request/application/accept_and_reciprocate_use_case.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';

final _cryptoBus = Ed25519ContactRequestCryptoBus();
final _aliceId = TestEd25519Identity.fromSeedByte(0x61);
final _bobId = TestEd25519Identity.fromSeedByte(0x62);

Future<ContactModel?> _settledAvatar({
  required Bridge bridge,
  required ContactRepository contactRepo,
  required String ownerPeerId,
  required String avatarVersion,
}) async =>
    await contactRepo.getContact(ownerPeerId) ??
    ContactModel(
      peerId: ownerPeerId,
      publicKey: '',
      rendezvous: '',
      username: 'Peer',
      signature: '',
      scannedAt: '2026-01-01T00:00:00.000Z',
    );

Future<Database> _openDb(String path) {
  sqfliteFfiInit();
  return databaseFactoryFfiNoIsolate.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: currentIdentityDatabaseVersion,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    ),
  );
}

IdentityRepositoryImpl _buildIdentityRepo(
  Database db,
  SecureKeyStore keyStore,
) => IdentityRepositoryImpl(
  dbLoadIdentityRow: () => dbLoadIdentityRow(db),
  dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
  secureKeyStore: keyStore,
);

ContactRepositoryImpl _buildContactRepo(Database db) => ContactRepositoryImpl(
  dbLoadAllContacts: () => dbLoadAllContacts(db),
  dbLoadContact: (peerId) => dbLoadContact(db, peerId),
  dbUpsertContact: (row) => dbUpsertContact(db, row),
  dbDeleteContact: (peerId) => dbDeleteContact(db, peerId),
  dbGetContactCount: () => dbGetContactCount(db),
  dbContactExists: (peerId) => dbContactExists(db, peerId),
  dbArchiveContact: (peerId) => dbArchiveContact(db, peerId),
  dbUnarchiveContact: (peerId) => dbUnarchiveContact(db, peerId),
  dbLoadActiveContacts: () => dbLoadActiveContacts(db),
  dbLoadArchivedContacts: () => dbLoadArchivedContacts(db),
  dbBlockContact: (peerId) => dbBlockContact(db, peerId),
  dbUnblockContact: (peerId) => dbUnblockContact(db, peerId),
  dbDismissIntroBanner: (peerId) => dbDismissIntroBanner(db, peerId),
  dbSetIntrosSentAt: (peerId, timestamp) =>
      dbSetIntrosSentAt(db, peerId, timestamp),
);

ContactRequestRepositoryImpl _buildRequestRepo(
  Database db, {
  void Function(List<Map<String, Object?>>)? onLoadPendingCompleted,
}) => ContactRequestRepositoryImpl(
  dbLoadPendingRequests: () async {
    final rows = await dbLoadPendingRequests(db);
    onLoadPendingCompleted?.call(rows);
    return rows;
  },
  dbLoadRequest: (peerId) => dbLoadRequest(db, peerId),
  dbUpsertRequest: (row) => dbUpsertRequest(db, row),
  dbUpdateRequestStatus: (peerId, status) =>
      dbUpdateRequestStatus(db, peerId, status),
  dbDeleteRequest: (peerId) => dbDeleteRequest(db, peerId),
  dbRequestExists: (peerId) => dbRequestExists(db, peerId),
);

class _FailOnceEncryptBridge extends Bridge {
  _FailOnceEncryptBridge(Ed25519ContactRequestCryptoBus bus)
    : _inner = Ed25519ContactRequestBridge(bus);

  final Ed25519ContactRequestBridge _inner;
  bool failEncrypt = false;
  Completer<void> failedEncryptBarrier = Completer<void>();

  @override
  bool get isInitialized => _inner.isInitialized;

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<bool> checkHealth() => _inner.checkHealth();

  @override
  Future<void> reinitialize() => _inner.reinitialize();

  @override
  void dispose() => _inner.dispose();

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    if (failEncrypt && request['cmd'] == 'contactrequest.encrypt') {
      if (!failedEncryptBarrier.isCompleted) {
        failedEncryptBarrier.complete();
      }
      return jsonEncode(<String, Object>{
        'ok': false,
        'error': 'simulated pre-egress encryption failure on reciprocal send',
      });
    }
    return _inner.send(message);
  }
}

void main() {
  late Directory tempDir;
  late String aliceDbPath;
  late String bobDbPath;
  late Database aliceDb;
  late Database bobDb;
  late FakeP2PNetwork network;

  setUp(() async {
    _cryptoBus
      ..register(_aliceId)
      ..register(_bobId);
    tempDir = await Directory.systemTemp.createTemp('cr018_it_');
    aliceDbPath = '${tempDir.path}/alice.db';
    bobDbPath = '${tempDir.path}/bob.db';
    aliceDb = await _openDb(aliceDbPath);
    bobDb = await _openDb(bobDbPath);
    network = FakeP2PNetwork();
  });

  tearDown(() async {
    await aliceDb.close();
    await bobDb.close();
    await tempDir.delete(recursive: true);
  });

  group('CR-018 acceptance still reaches the other person after a restart', () {
    test(
      'pre-egress encryption failure on the reciprocal send after local acceptance is recovered on restart and delivers the accepter ML-KEM key without a second prompt or duplicate contact',
      () async {
        final aliceKeyStore = FakeSecureKeyStore();
        final bobKeyStore = FakeSecureKeyStore();
        var aliceContacts = _buildContactRepo(aliceDb);
        var aliceRequests = _buildRequestRepo(aliceDb);
        var aliceIdentities = _buildIdentityRepo(aliceDb, aliceKeyStore);
        final bobContacts = _buildContactRepo(bobDb);
        final bobRequests = _buildRequestRepo(bobDb);
        final bobIdentities = _buildIdentityRepo(bobDb, bobKeyStore);

        await aliceIdentities.saveIdentity(
          testIdentityModel(
            _aliceId,
            username: 'Alice',
            mlKemPublicKey: 'mlkem-alice',
          ),
        );
        await bobIdentities.saveIdentity(
          testIdentityModel(
            _bobId,
            username: 'Bob',
            mlKemPublicKey: 'mlkem-bob',
          ),
        );

        final aliceBridge = _FailOnceEncryptBridge(_cryptoBus);
        final bobBridge = Ed25519ContactRequestBridge(_cryptoBus);
        var aliceP2p = FakeP2PService(peerId: _aliceId.peerId, network: network);
        final bobP2p = FakeP2PService(peerId: _bobId.peerId, network: network);

        // 1. Bob scans Alice's compact QR (Alice's contact row on Bob starts
        // with mlKemPublicKey == null) and sends his v2 contact request.
        await bobContacts.addContact(
          ContactModel(
            peerId: _aliceId.peerId,
            username: 'Alice',
            publicKey: _aliceId.publicKey,
            rendezvous: 'rv-alice',
            signature: 'sig-alice',
            scannedAt: '2026-10-19T12:00:00.000Z',
          ),
        );

        var aliceListener = ContactRequestListener(
          contactRequestStream: aliceP2p.messageStream,
          requestRepo: aliceRequests,
          contactRepo: aliceContacts,
          bridge: aliceBridge,
          getOwnPeerId: () => _aliceId.peerId,
          getOwnPrivateKey: () async => _aliceId.privateKey,
          getOwnPublicKey: () async => _aliceId.publicKey,
          downloadProfilePictureFn: _settledAvatar,
        );
        final bobListener = ContactRequestListener(
          contactRequestStream: bobP2p.messageStream,
          requestRepo: bobRequests,
          contactRepo: bobContacts,
          bridge: bobBridge,
          getOwnPeerId: () => _bobId.peerId,
          getOwnPrivateKey: () async => _bobId.privateKey,
          getOwnPublicKey: () async => _bobId.publicKey,
          downloadProfilePictureFn: _settledAvatar,
        );

        final aliceInitialPrompts = <ContactRequestModel>[];
        final bobPrompts = <ContactRequestModel>[];
        final firstPromptBarrier = Completer<void>();
        var alicePromptSub = aliceListener.requestStream.listen((request) {
          aliceInitialPrompts.add(request);
          if (!firstPromptBarrier.isCompleted) {
            firstPromptBarrier.complete();
          }
        });
        final bobPromptSub = bobListener.requestStream.listen(bobPrompts.add);
        aliceListener.start();
        bobListener.start();
        addTearDown(() async {
          await alicePromptSub.cancel();
          await bobPromptSub.cancel();
          aliceListener.dispose();
          bobListener.dispose();
          aliceP2p.dispose();
          bobP2p.dispose();
        });

        expect(
          await sendContactRequest(
            p2pService: bobP2p,
            identityRepo: bobIdentities,
            bridge: bobBridge,
            targetPeerId: _aliceId.peerId,
            recipientPublicKey: _aliceId.publicKey,
          ),
          SendContactRequestResult.success,
        );
        await firstPromptBarrier.future;
        expect(aliceInitialPrompts, hasLength(1));

        // 2. Alice accepts, and the fire-and-forget reciprocal send fails at
        // contactrequest.encrypt before egress after the local contact and
        // accepted status are persisted.
        aliceBridge.failEncrypt = true;
        expect(
          await acceptAndReciprocateContactRequest(
            requestRepo: aliceRequests,
            contactRepo: aliceContacts,
            peerId: _bobId.peerId,
            p2pService: aliceP2p,
            identityRepo: aliceIdentities,
            bridge: aliceBridge,
            downloadProfilePictureFn: _settledAvatar,
          ),
          AcceptContactRequestResult.success,
        );
        await aliceBridge.failedEncryptBarrier.future;
        await Future<void>(() {});

        expect(await aliceContacts.getContactCount(), 1);
        expect(
          (await aliceRequests.getRequest(_bobId.peerId))?.status,
          ContactRequestStatus.accepted,
        );
        expect(
          (await bobContacts.getContact(_aliceId.peerId))?.mlKemPublicKey,
          isNull,
        );

        // 3. Alice restarts on the same SQLite DB and secure key store with
        // working encryption.
        await alicePromptSub.cancel();
        aliceListener.dispose();
        aliceP2p.dispose();
        await aliceDb.close();

        aliceBridge.failEncrypt = false;
        aliceDb = await _openDb(aliceDbPath);
        final restartAttachBarrier = Completer<void>();
        aliceContacts = _buildContactRepo(aliceDb);
        aliceRequests = _buildRequestRepo(
          aliceDb,
          onLoadPendingCompleted: (_) {
            if (!restartAttachBarrier.isCompleted) {
              restartAttachBarrier.complete();
            }
          },
        );
        aliceIdentities = _buildIdentityRepo(aliceDb, aliceKeyStore);
        aliceP2p = FakeP2PService(peerId: _aliceId.peerId, network: network);
        aliceListener = ContactRequestListener(
          contactRequestStream: aliceP2p.messageStream,
          requestRepo: aliceRequests,
          contactRepo: aliceContacts,
          bridge: aliceBridge,
          getOwnPeerId: () => _aliceId.peerId,
          getOwnPrivateKey: () async => _aliceId.privateKey,
          getOwnPublicKey: () async => _aliceId.publicKey,
          downloadProfilePictureFn: _settledAvatar,
        );
        final aliceRestartPrompts = <ContactRequestModel>[];
        alicePromptSub =
            aliceListener.requestStream.listen(aliceRestartPrompts.add);
        aliceListener.start();
        await restartAttachBarrier.future;
        await Future<void>(() {});

        // Run reconnect key-exchange recovery and repeat accept.
        await retryIncompleteKeyExchanges(
          contactRepo: aliceContacts,
          identityRepo: aliceIdentities,
          p2pService: aliceP2p,
          bridge: aliceBridge,
          secureKeyStore: aliceKeyStore,
        );
        await acceptAndReciprocateContactRequest(
          requestRepo: aliceRequests,
          contactRepo: aliceContacts,
          peerId: _bobId.peerId,
          p2pService: aliceP2p,
          identityRepo: aliceIdentities,
          bridge: aliceBridge,
          downloadProfilePictureFn: _settledAvatar,
        );
        await bobP2p.drainOfflineInbox();
        await Future<void>(() {});

        expect(await aliceContacts.getContactCount(), 1);
        expect(aliceRestartPrompts, isEmpty);
        expect(bobPrompts, isEmpty);
        expect(
          (await bobContacts.getContact(_aliceId.peerId))?.mlKemPublicKey,
          'mlkem-alice',
          reason:
              'After Alice restarts from a failed reciprocal send, Bob must receive Alice ML-KEM public key',
        );
      },
      skip:
          'KNOWN GAP CR-018: acceptAndReciprocateContactRequest fire-and-forgets the reciprocal send without durable recovery on pre-egress encryption failure and retryIncompleteKeyExchanges skips peers whose incoming ML-KEM key is already stored when no reannounce, wake-token, or call-wake marker is pending, lib/features/contact_request/application/accept_and_reciprocate_use_case.dart:44-101. Remove when fixed.',
    );
  });
}
