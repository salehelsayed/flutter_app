import 'dart:async';
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
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/application/add_contact_use_case.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';

final _cryptoBus = Ed25519ContactRequestCryptoBus();
final _aliceId = TestEd25519Identity.fromSeedByte(0x21);
final _bobId = TestEd25519Identity.fromSeedByte(0x22);

Future<ContactModel?> _settledAvatar({
  required Bridge bridge,
  required ContactRepository contactRepo,
  required String ownerPeerId,
  required String avatarVersion,
  bool retryPendingRequest = false,
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
    tempDir = await Directory.systemTemp.createTemp('cr002_it_');
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

  group('CR-002 declining a request adds no contact', () {
    test(
      'decline adds no contact on Alice, sends nothing to Bob, ignores an old replayed envelope, survives restart, and forces a fresh request onto manual consent',
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
            mlKemPublicKey: 'mlkem-bob-1',
          ),
        );

        final aliceBridge = Ed25519ContactRequestBridge(_cryptoBus);
        final bobBridge = Ed25519ContactRequestBridge(_cryptoBus);
        var aliceP2p = FakeP2PService(
          peerId: _aliceId.peerId,
          network: network,
        );
        final bobP2p = FakeP2PService(peerId: _bobId.peerId, network: network);

        final bobIncoming = <String>[];
        final bobReciprocalBarrier = Completer<void>();
        final bobIncomingSub = bobP2p.messageStream.listen((msg) {
          bobIncoming.add(msg.content);
          if (!bobReciprocalBarrier.isCompleted) {
            bobReciprocalBarrier.complete();
          }
        });

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
        final alicePrompted = <ContactRequestModel>[];
        final firstPromptBarrier = Completer<void>();
        var alicePromptSub = aliceListener.requestStream.listen((request) {
          alicePrompted.add(request);
          if (!firstPromptBarrier.isCompleted) {
            firstPromptBarrier.complete();
          }
        });
        StreamSubscription<ContactModel>? autoSub;
        aliceListener.start();
        addTearDown(() async {
          await autoSub?.cancel();
          await alicePromptSub.cancel();
          await bobIncomingSub.cancel();
          aliceListener.dispose();
          aliceP2p.dispose();
          bobP2p.dispose();
        });

        // 1. Bob scans Alice's signed compact QR, adds Alice one-sidedly
        // (without Alice's ML-KEM key), and sends a v2 encrypted request.
        final (builtQr, qrString) = await buildQRPayload(
          repo: aliceIdentities,
          callSign: (data, privateKey) => callSignPayload(
            bridge: aliceBridge,
            dataToSign: data,
            privateKey: privateKey,
          ),
        );
        expect(builtQr, BuildQRPayloadResult.success);

        final (parsedQr, scannedAlice) = await parseQRPayload(
          qrString: qrString!,
          bridge: bobBridge,
          ownPeerId: _bobId.peerId,
        );
        expect(parsedQr, ParseQRResult.success);
        expect(scannedAlice!.peerId, _aliceId.peerId);
        expect(scannedAlice.mlKemPublicKey, isNull);
        expect(
          await addContact(repository: bobContacts, contact: scannedAlice),
          AddContactResult.success,
        );

        final firstWireFuture = aliceP2p.messageStream.first;
        final firstSend = await sendContactRequest(
          p2pService: bobP2p,
          identityRepo: bobIdentities,
          bridge: bobBridge,
          targetPeerId: _aliceId.peerId,
          recipientPublicKey: scannedAlice.publicKey,
        );
        expect(firstSend, SendContactRequestResult.success);
        final firstDeliveredWire = await firstWireFuture;
        await firstPromptBarrier.future;

        expect(alicePrompted, hasLength(1));
        expect(alicePrompted.single.peerId, _bobId.peerId);
        expect(alicePrompted.single.username, 'Bob');
        expect(alicePrompted.single.status, ContactRequestStatus.pending);

        // 2. Alice taps Decline -> status becomes declined, Alice has 0
        // contacts, and nothing is sent to Bob or his relay inbox.
        network.resetCounters();
        final declineResult = await declineContactRequest(
          requestRepo: aliceRequests,
          peerId: _bobId.peerId,
        );
        expect(declineResult, DeclineContactRequestResult.success);

        expect(await aliceContacts.getContact(_bobId.peerId), isNull);
        expect(await aliceContacts.getContactCount(), 0);
        final declinedRow = await aliceRequests.getRequest(_bobId.peerId);
        expect(declinedRow, isNotNull);
        expect(declinedRow!.status, ContactRequestStatus.declined);
        expect(await aliceRequests.getPendingRequests(), isEmpty);
        expect(network.deliverCallCount, 0);
        expect(network.inboxCount(_bobId.peerId), 0);
        expect(bobIncoming, isEmpty);

        // Bob keeps only his one-sided QR contact with null ML-KEM key.
        final bobSideAlice = await bobContacts.getContact(_aliceId.peerId);
        expect(bobSideAlice, isNotNull);
        expect(bobSideAlice!.mlKemPublicKey, isNull);
        expect(await bobRequests.getPendingRequests(), isEmpty);

        // 3. Replaying the old request envelope does not re-prompt Alice or
        // flip the declined status back to pending.
        alicePrompted.clear();
        final replayResult = await aliceListener.processIncomingMessage(
          firstDeliveredWire,
        );
        expect(replayResult, HandleMessageResult.invalidMessage);
        expect(alicePrompted, isEmpty);
        expect(
          (await aliceRequests.getRequest(_bobId.peerId))?.status,
          ContactRequestStatus.declined,
        );
        expect(await aliceContacts.getContact(_bobId.peerId), isNull);

        // 4. Restart Alice on the same SQLite database file: the declined
        // decision survives restart and attach replay does not re-prompt.
        await alicePromptSub.cancel();
        aliceListener.dispose();
        aliceP2p.dispose();
        await aliceDb.close();

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

        var autoAddCalls = 0;
        aliceListener = ContactRequestListener(
          contactRequestStream: aliceP2p.messageStream,
          requestRepo: aliceRequests,
          contactRepo: aliceContacts,
          bridge: aliceBridge,
          getOwnPeerId: () => _aliceId.peerId,
          getOwnPrivateKey: () async => _aliceId.privateKey,
          getOwnPublicKey: () async => _aliceId.publicKey,
          downloadProfilePictureFn: _settledAvatar,
          // Even if auto-accept is wired, a previously-declined peer must
          // stay on manual consent and never be auto-added.
          autoAcceptAndReciprocate: (_) async {
            autoAddCalls++;
            return AcceptContactRequestResult.success;
          },
        );
        final aliceAutoAdded = <ContactModel>[];
        autoSub = aliceListener.autoAddedStream.listen(aliceAutoAdded.add);
        final secondPromptBarrier = Completer<void>();
        alicePromptSub = aliceListener.requestStream.listen((request) {
          alicePrompted.add(request);
          if (!secondPromptBarrier.isCompleted) {
            secondPromptBarrier.complete();
          }
        });
        aliceListener.start();
        await restartAttachBarrier.future;
        await Future<void>(() {});

        expect(
          alicePrompted,
          isEmpty,
          reason: 'declined request must not replay on attach after restart',
        );
        expect(
          (await aliceRequests.getRequest(_bobId.peerId))?.status,
          ContactRequestStatus.declined,
        );
        expect(await aliceContacts.getContact(_bobId.peerId), isNull);

        // 5. A later fresh request from Bob overwrites the declined row back
        // to pending, emits on the manual requestStream, and is never
        // auto-added without a fresh tap.
        await bobIdentities.saveIdentity(
          testIdentityModel(
            _bobId,
            username: 'Bob',
            mlKemPublicKey: 'mlkem-bob-fresh',
          ),
        );
        final secondSend = await sendContactRequest(
          p2pService: bobP2p,
          identityRepo: bobIdentities,
          bridge: bobBridge,
          targetPeerId: _aliceId.peerId,
          recipientPublicKey: scannedAlice.publicKey,
        );
        expect(secondSend, SendContactRequestResult.success);
        await secondPromptBarrier.future;

        expect(autoAddCalls, 0);
        expect(aliceAutoAdded, isEmpty);
        expect(alicePrompted, hasLength(1));
        expect(alicePrompted.single.peerId, _bobId.peerId);
        expect(alicePrompted.single.status, ContactRequestStatus.pending);
        expect(alicePrompted.single.mlKemPublicKey, 'mlkem-bob-fresh');
        expect(
          await aliceContacts.getContact(_bobId.peerId),
          isNull,
          reason: 'fresh request from declined peer requires a fresh tap',
        );

        // 6. When Alice explicitly taps Accept on the fresh request, the
        // contact is added with the fresh key and status becomes accepted.
        final acceptResult = await acceptAndReciprocateContactRequest(
          requestRepo: aliceRequests,
          contactRepo: aliceContacts,
          peerId: _bobId.peerId,
          p2pService: aliceP2p,
          identityRepo: aliceIdentities,
          bridge: aliceBridge,
          downloadProfilePictureFn: _settledAvatar,
        );
        expect(acceptResult, AcceptContactRequestResult.success);
        await bobReciprocalBarrier.future;
        await Future<void>(() {});

        final acceptedBob = await aliceContacts.getContact(_bobId.peerId);
        expect(acceptedBob, isNotNull);
        expect(acceptedBob!.username, 'Bob');
        expect(acceptedBob.publicKey, _bobId.publicKey);
        expect(acceptedBob.mlKemPublicKey, 'mlkem-bob-fresh');
        expect(
          (await aliceRequests.getRequest(_bobId.peerId))?.status,
          ContactRequestStatus.accepted,
        );
      },
    );

    test(
      'an old envelope replayed after restart does not overwrite a declined decision or re-prompt the decliner',
      () async {
        final bobKeyStore = FakeSecureKeyStore();
        var aliceContacts = _buildContactRepo(aliceDb);
        var aliceRequests = _buildRequestRepo(aliceDb);
        final bobIdentities = _buildIdentityRepo(bobDb, bobKeyStore);
        await bobIdentities.saveIdentity(
          testIdentityModel(
            _bobId,
            username: 'Bob',
            mlKemPublicKey: 'mlkem-bob-1',
          ),
        );
        final aliceBridge = Ed25519ContactRequestBridge(_cryptoBus);
        final bobBridge = Ed25519ContactRequestBridge(_cryptoBus);
        var aliceP2p = FakeP2PService(
          peerId: _aliceId.peerId,
          network: network,
        );
        final bobP2p = FakeP2PService(peerId: _bobId.peerId, network: network);

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
        final alicePrompted = <ContactRequestModel>[];
        final firstPromptBarrier = Completer<void>();
        var sub = aliceListener.requestStream.listen((request) {
          alicePrompted.add(request);
          if (!firstPromptBarrier.isCompleted) {
            firstPromptBarrier.complete();
          }
        });
        aliceListener.start();
        addTearDown(() async {
          await sub.cancel();
          aliceListener.dispose();
          aliceP2p.dispose();
          bobP2p.dispose();
        });

        final firstWireFuture = aliceP2p.messageStream.first;
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
        final oldEnvelope = await firstWireFuture;
        await firstPromptBarrier.future;
        expect(alicePrompted, hasLength(1));

        expect(
          await declineContactRequest(
            requestRepo: aliceRequests,
            peerId: _bobId.peerId,
          ),
          DeclineContactRequestResult.success,
        );
        expect(
          (await aliceRequests.getRequest(_bobId.peerId))?.status,
          ContactRequestStatus.declined,
        );

        // Simulate app restart (new listener with empty in-memory ReplayCache
        // on the same SQLite database) and replay the exact old envelope.
        await sub.cancel();
        aliceListener.dispose();
        aliceP2p.dispose();
        await aliceDb.close();

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
        alicePrompted.clear();
        sub = aliceListener.requestStream.listen(alicePrompted.add);
        aliceListener.start();
        await restartAttachBarrier.future;
        await Future<void>(() {});

        await aliceListener.processIncomingMessage(oldEnvelope);

        expect(
          alicePrompted,
          isEmpty,
          reason:
              'An old replayed envelope after restart must not re-prompt the decliner',
        );
        expect(
          (await aliceRequests.getRequest(_bobId.peerId))?.status,
          ContactRequestStatus.declined,
        );
      },
      skip:
          'KNOWN GAP CR-002: ReplayCache is in-memory only and handleIncomingMessage overwrites a declined row back to pending without durable msgId or timestamp ordering, lib/features/contact_request/application/handle_incoming_message_use_case.dart:818-835. Remove when fixed.',
    );
  });
}
