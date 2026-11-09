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
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/application/add_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/delete_contact_use_case.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/domain/received_wake_token_store.dart';
import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../support/contact_repair_harness.dart'
    show buildRepairWire, contactFor, newRequestControl;

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
  dbDecideRequest: (expected, accept, existingOnly, before) =>
      dbDecideContactRequest(db, expected, accept, existingOnly, before),
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
      'CR-006 late signature alias envelopes after restart preserve declined consent and wake authority',
      () async {
        final bobKeyStore = FakeSecureKeyStore();
        final wakeTokens = _RecordingWakeTokenStore();
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
          receivedWakeTokenStore: wakeTokens,
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

        final lateTs = DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 25))
            .toIso8601String();
        final oldEnvelope = await buildRepairWire(
          bus: _cryptoBus,
          signer: _bobId,
          recipientPublicKey: _aliceId.publicKey,
          ts: lateTs,
          outerTs: lateTs,
          mlKem: 'mlkem-bob-1',
          wakeToken: 'signed-wake-token',
        );
        expect(
          await aliceListener.processIncomingMessage(oldEnvelope),
          HandleMessageResult.contactAutoAdded,
        );
        await firstPromptBarrier.future;
        expect(alicePrompted, hasLength(1));
        expect(wakeTokens.writes, 1);
        await wakeTokens.clear();
        final wakeWritesBeforeReplay = wakeTokens.writes;

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
          receivedWakeTokenStore: wakeTokens,
          getOwnPublicKey: () async => _aliceId.publicKey,
          downloadProfilePictureFn: _settledAvatar,
        );
        alicePrompted.clear();
        sub = aliceListener.requestStream.listen(alicePrompted.add);
        aliceListener.start();
        await restartAttachBarrier.future;
        await Future<void>(() {});

        await aliceListener.processIncomingMessage(oldEnvelope);

        final oldOuter =
            jsonDecode(oldEnvelope.content) as Map<String, dynamic>;
        final oldEncrypted = oldOuter['encrypted'] as Map<String, dynamic>;
        final opened = await callDecryptContactRequest(
          bridge: aliceBridge,
          ownPrivateKey: _aliceId.privateKey,
          ephemeralPublicKey: oldEncrypted['ephemeralPublicKey'] as String,
          ciphertext: oldEncrypted['ciphertext'] as String,
          nonce: oldEncrypted['nonce'] as String,
          msgId: oldOuter['msgId'] as String,
          ts: oldOuter['ts'] as String,
        );
        expect(opened['ok'], isTrue);
        final originalPayload =
            jsonDecode(opened['plaintext'] as String) as Map<String, dynamic>;
        final signature = originalPayload['sig'] as String;
        expect(signature.endsWith('=='), isTrue);
        const alphabet =
            'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        final last = alphabet.indexOf(signature[signature.length - 3]);
        final paddingAlias = signature.replaceRange(
          signature.length - 3,
          signature.length - 2,
          alphabet[last | 1],
        );
        for (final encoded in [signature, paddingAlias]) {
          final alias =
              '${encoded.substring(0, 32)}\r\n${encoded.substring(32)}';
          final outer = jsonDecode(oldEnvelope.content) as Map<String, dynamic>;
          final encrypted = await callEncryptContactRequest(
            bridge: bobBridge,
            recipientPublicKey: _aliceId.publicKey,
            signedPayloadJson: jsonEncode({...originalPayload, 'sig': alias}),
            msgId: outer['msgId'] as String,
            ts: outer['ts'] as String,
          );
          expect(encrypted['ok'], isTrue);
          final verifiedBeforeAlias = aliceBridge.verifiedData.length;
          final aliasResult = await aliceListener.processIncomingMessage(
            ChatMessage(
              from: oldEnvelope.from,
              to: oldEnvelope.to,
              timestamp: oldEnvelope.timestamp,
              isIncoming: true,
              content: jsonEncode({
                ...outer,
                'encrypted': {
                  'ephemeralPublicKey': encrypted['ephemeralPublicKey'],
                  'ciphertext': encrypted['ciphertext'],
                  'nonce': encrypted['nonce'],
                },
              }),
            ),
          );
          await Future<void>(() {});
          expect(
            aliceBridge.verifiedData.length,
            verifiedBeforeAlias + 1,
            reason: 'The CR/LF alias must pass real signature verification',
          );
          expect(
            wakeTokens.writes,
            wakeWritesBeforeReplay,
            reason: 'A declined alias must not restore cleared wake authority',
          );
          expect(await wakeTokens.readTokenFor(_bobId.peerId), isNull);
          expect(aliasResult, HandleMessageResult.invalidMessage);
        }

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
    );
  });

  group('CR-006 late admission with durable SQL state', () {
    late ContactRepositoryImpl contacts;
    late ContactRequestRepositoryImpl requests;
    late Ed25519ContactRequestBridge bridge;
    late ChatMessage lateWire;
    ContactRequestListener? receiver;
    StreamSubscription<ContactRequestModel>? promptSub;
    late List<ContactRequestModel> prompted;
    late Completer<ContactRequestModel> firstPrompt;
    var autoAddCalls = 0;

    Future<void> attach({bool enableAutoAdd = false}) async {
      final loaded = Completer<void>();
      contacts = _buildContactRepo(aliceDb);
      requests = _buildRequestRepo(
        aliceDb,
        onLoadPendingCompleted: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
      );
      receiver = ContactRequestListener(
        contactRequestStream: const Stream<ChatMessage>.empty(),
        requestRepo: requests,
        contactRepo: contacts,
        bridge: bridge,
        getOwnPeerId: () => _aliceId.peerId,
        getOwnPrivateKey: () async => _aliceId.privateKey,
        getOwnPublicKey: () async => _aliceId.publicKey,
        repairRepository: SqlContactRepairRepository(aliceDb),
        downloadProfilePictureFn: _settledAvatar,
        autoAcceptAndReciprocate: enableAutoAdd
            ? (_) async {
                autoAddCalls++;
                return AcceptContactRequestResult.success;
              }
            : null,
      );
      prompted = [];
      firstPrompt = Completer<ContactRequestModel>();
      promptSub = receiver!.requestStream.listen((request) {
        prompted.add(request);
        if (!firstPrompt.isCompleted) firstPrompt.complete(request);
      });
      await loaded.future;
      await Future<void>(() {});
    }

    Future<void> reopen({bool enableAutoAdd = false}) async {
      await promptSub?.cancel();
      receiver?.dispose();
      await aliceDb.close();
      aliceDb = await _openDb(aliceDbPath);
      await attach(enableAutoAdd: enableAutoAdd);
    }

    Future<int> decisionTimeMs() async {
      final rows = await aliceDb.query(
        'contact_relationship_consent',
        columns: ['updated_at_ms'],
        where: 'peer_id = ?',
        whereArgs: [_bobId.peerId],
      );
      return rows.single['updated_at_ms']! as int;
    }

    setUp(() async {
      contacts = _buildContactRepo(aliceDb);
      requests = _buildRequestRepo(aliceDb);
      bridge = Ed25519ContactRequestBridge(_cryptoBus);
      receiver = null;
      promptSub = null;
      autoAddCalls = 0;
      final ts = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 25))
          .toIso8601String();
      lateWire = await buildRepairWire(
        bus: _cryptoBus,
        signer: _bobId,
        recipientPublicKey: _aliceId.publicKey,
        ts: ts,
        outerTs: ts,
        mlKem: 'old-signed-key',
      );
    });

    tearDown(() async {
      await promptSub?.cancel();
      receiver?.dispose();
    });

    test(
      'late pending request presents once and survives SQL reopen at 30 days',
      () async {
        // The documented null callback retains the manual-dialog fallback.
        await attach();
        expect(
          await receiver!.processIncomingMessage(lateWire),
          HandleMessageResult.contactAutoAdded,
        );
        final stored = await firstPrompt.future;
        expect(prompted, hasLength(1));
        expect(bridge.verifiedData, hasLength(1));
        expect(await contacts.getContact(_bobId.peerId), isNull);
        expect(
          (await requests.getPendingRequests()).single.signature,
          stored.signature,
        );
        expect(
          await receiver!.processIncomingMessage(lateWire),
          HandleMessageResult.invalidMessage,
        );
        expect(prompted, hasLength(1));

        final oldReceivedAt = DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 30))
            .toIso8601String();
        await requests.addRequest(stored.copyWith(receivedAt: oldReceivedAt));
        await reopen();
        final replayed = await firstPrompt.future;
        expect(replayed.receivedAt, oldReceivedAt);
        expect(replayed.signature, stored.signature);
        expect(replayed.status, ContactRequestStatus.pending);
        expect(
          await receiver!.processIncomingMessage(lateWire),
          HandleMessageResult.duplicateRequest,
        );
        expect(bridge.verifiedData, hasLength(2));
        expect(prompted, hasLength(1));
        final pending = await requests.getPendingRequests();
        expect(pending, hasLength(1));
        expect(pending.single.toMap(), replayed.toMap());
      },
    );

    for (final reopenBeforeRetry in [false, true]) {
      test('fresh automatic retry preserves decline '
          '${reopenBeforeRetry ? 'after SQL reopen' : 'in the live receiver'} '
          'while a fresh manual request can prompt', () async {
        await attach();
        expect(
          await receiver!.processIncomingMessage(lateWire),
          HandleMessageResult.contactAutoAdded,
        );
        final original = await firstPrompt.future;
        expect(
          await declineContactRequest(
            requestRepo: requests,
            peerId: _bobId.peerId,
            expectedRequest: original,
          ),
          DeclineContactRequestResult.success,
        );
        final declined = (await requests.getRequest(_bobId.peerId))!;
        expect(declined.status, ContactRequestStatus.declined);
        final cutoffMs = await decisionTimeMs();
        final consentBefore = await aliceDb.query(
          'contact_relationship_consent',
          where: 'peer_id = ?',
          whereArgs: [_bobId.peerId],
        );

        if (reopenBeforeRetry) {
          await reopen(enableAutoAdd: true);
        } else {
          prompted.clear();
          firstPrompt = Completer<ContactRequestModel>();
        }
        final retryTs = DateTime.fromMillisecondsSinceEpoch(
          cutoffMs + 1,
          isUtc: true,
        ).toIso8601String();
        final automaticRetry = await buildRepairWire(
          bus: _cryptoBus,
          signer: _bobId,
          recipientPublicKey: _aliceId.publicKey,
          intent: 'key_exchange_retry',
          signedControl: newRequestControl(to: _aliceId.peerId),
          ts: retryTs,
          outerTs: retryTs,
          mlKem: 'automatic-retry-after-decline',
        );
        final verifiedBefore = bridge.verifiedData.length;
        final retryResult = await receiver!.processIncomingMessage(
          automaticRetry,
        );
        await Future<void>(() {});

        expect(bridge.verifiedData.length, verifiedBefore + 1);
        expect(prompted, isEmpty);
        expect(
          (await requests.getRequest(_bobId.peerId))?.toMap(),
          declined.toMap(),
        );
        expect(await requests.getPendingRequests(), isEmpty);
        expect(await contacts.getContact(_bobId.peerId), isNull);
        expect(retryResult, HandleMessageResult.invalidMessage);
        expect(autoAddCalls, 0);
        expect(await decisionTimeMs(), cutoffMs);
        expect(
          await aliceDb.query(
            'contact_relationship_consent',
            where: 'peer_id = ?',
            whereArgs: [_bobId.peerId],
          ),
          consentBefore,
        );

        final manualTs = DateTime.fromMillisecondsSinceEpoch(
          cutoffMs + 2,
          isUtc: true,
        ).toIso8601String();
        final manualRequest = await buildRepairWire(
          bus: _cryptoBus,
          signer: _bobId,
          recipientPublicKey: _aliceId.publicKey,
          intent: 'new_request',
          signedControl: newRequestControl(to: _aliceId.peerId),
          ts: manualTs,
          outerTs: manualTs,
          mlKem: 'manual-request-after-decline',
        );
        expect(
          await receiver!.processIncomingMessage(manualRequest),
          HandleMessageResult.contactRequest,
        );
        final manual = await firstPrompt.future;
        expect(manual.signature, isNot(declined.signature));
        expect(prompted, hasLength(1));
        expect(
          (await requests.getPendingRequests()).single.toMap(),
          manual.toMap(),
        );
        expect(await contacts.getContact(_bobId.peerId), isNull);
        expect(autoAddCalls, 0);
      });
    }

    test(
      'automatic retry can deliver a first request without a decline',
      () async {
        await attach();
        final ts = DateTime.now().toUtc().toIso8601String();
        final automaticRetry = await buildRepairWire(
          bus: _cryptoBus,
          signer: _bobId,
          recipientPublicKey: _aliceId.publicKey,
          intent: 'key_exchange_retry',
          signedControl: newRequestControl(to: _aliceId.peerId),
          ts: ts,
          outerTs: ts,
          mlKem: 'first-request-recovered-by-retry',
        );

        expect(
          await receiver!.processIncomingMessage(automaticRetry),
          HandleMessageResult.contactAutoAdded,
        );
        final request = await firstPrompt.future;
        expect(bridge.verifiedData, hasLength(1));
        expect(prompted, hasLength(1));
        expect(request.status, ContactRequestStatus.pending);
        expect(
          (await requests.getPendingRequests()).single.toMap(),
          request.toMap(),
        );
        expect(await contacts.getContact(_bobId.peerId), isNull);
        expect(autoAddCalls, 0);
      },
    );

    for (final replay in [
      'same 25h wire',
      'same +1min future wire',
      'signature at decision cutoff',
    ]) {
      test(
        'accepted then deleted request stays withdrawn after SQL reopen ($replay)',
        () async {
          await attach();
          var acceptedWire = lateWire;
          if (replay == 'same +1min future wire') {
            final ts = DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 1))
                .toIso8601String();
            acceptedWire = await buildRepairWire(
              bus: _cryptoBus,
              signer: _bobId,
              recipientPublicKey: _aliceId.publicKey,
              ts: ts,
              outerTs: ts,
              mlKem: 'future-accepted-key',
            );
          }
          expect(
            await receiver!.processIncomingMessage(acceptedWire),
            HandleMessageResult.contactAutoAdded,
          );
          final stored = await firstPrompt.future;
          expect(
            await acceptContactRequest(
              requestRepo: requests,
              contactRepo: contacts,
              peerId: _bobId.peerId,
              expectedRequest: stored,
            ),
            AcceptContactRequestResult.success,
          );
          expect(await contacts.getContact(_bobId.peerId), isNotNull);
          await deleteContactAndMessages(
            contactRepo: contacts,
            messageRepo: InMemoryMessageRepository(),
            contactRequestRepo: requests,
            peerId: _bobId.peerId,
          );
          final cutoffMs = await decisionTimeMs();
          final withdrawn = await SqlContactRepairRepository(
            aliceDb,
          ).readConsent(_bobId.peerId);
          expect(withdrawn?.state, ContactRelationshipState.withdrawn);

          var replayWire = acceptedWire;
          if (replay == 'signature at decision cutoff') {
            final ts = DateTime.fromMillisecondsSinceEpoch(
              cutoffMs,
              isUtc: true,
            ).toIso8601String();
            replayWire = await buildRepairWire(
              bus: _cryptoBus,
              signer: _bobId,
              recipientPublicKey: _aliceId.publicKey,
              ts: ts,
              outerTs: ts,
              mlKem: 'signed-at-withdrawal-cutoff',
            );
          }

          await reopen(enableAutoAdd: true);
          final verifiedBefore = bridge.verifiedData.length;
          final result = await receiver!.processIncomingMessage(replayWire);
          expect(bridge.verifiedData.length, verifiedBefore + 1);
          expect(result, HandleMessageResult.invalidMessage);
          expect(await contacts.getContact(_bobId.peerId), isNull);
          expect(await requests.getPendingRequests(), isEmpty);
          final remaining = await requests.getRequest(_bobId.peerId);
          if (remaining != null) {
            expect(remaining.status, isNot(ContactRequestStatus.pending));
          }
          expect(prompted, isEmpty);
          expect(autoAddCalls, 0);
          final currentConsent = await SqlContactRepairRepository(
            aliceDb,
          ).readConsent(_bobId.peerId);
          expect(currentConsent?.state, ContactRelationshipState.withdrawn);
          expect(currentConsent?.revision, withdrawn?.revision);
        },
      );
    }

    test(
      'older of two declined signed requests stays declined after SQL reopen',
      () async {
        await attach();
        expect(
          await receiver!.processIncomingMessage(lateWire),
          HandleMessageResult.contactAutoAdded,
        );
        final first = await firstPrompt.future;
        expect(
          await declineContactRequest(
            requestRepo: requests,
            peerId: _bobId.peerId,
            expectedRequest: first,
          ),
          DeclineContactRequestResult.success,
        );

        final firstDecisionMs = await decisionTimeMs();
        final secondTs = DateTime.fromMillisecondsSinceEpoch(
          firstDecisionMs + 1,
          isUtc: true,
        ).toIso8601String();
        final secondWire = await buildRepairWire(
          bus: _cryptoBus,
          signer: _bobId,
          recipientPublicKey: _aliceId.publicKey,
          ts: secondTs,
          outerTs: secondTs,
          mlKem: 'second-signed-request',
        );
        expect(
          await receiver!.processIncomingMessage(secondWire),
          HandleMessageResult.contactRequest,
        );
        final second = (await requests.getRequest(_bobId.peerId))!;
        expect(second.signature, isNot(first.signature));
        final intermediateMs = DateTime.now().toUtc().millisecondsSinceEpoch;
        final intermediateTs = DateTime.fromMillisecondsSinceEpoch(
          intermediateMs,
          isUtc: true,
        ).toIso8601String();
        final intermediateWire = await buildRepairWire(
          bus: _cryptoBus,
          signer: _bobId,
          recipientPublicKey: _aliceId.publicKey,
          ts: intermediateTs,
          outerTs: intermediateTs,
          mlKem: 'undelivered-request-between-decisions',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          await declineContactRequest(
            requestRepo: requests,
            peerId: _bobId.peerId,
            expectedRequest: second,
          ),
          DeclineContactRequestResult.success,
        );
        final declined = (await requests.getRequest(_bobId.peerId))!;
        final cutoffMs = await decisionTimeMs();

        await reopen(enableAutoAdd: true);
        for (final replayWire in [lateWire, intermediateWire]) {
          final verifiedBefore = bridge.verifiedData.length;
          final replayResult = await receiver!.processIncomingMessage(
            replayWire,
          );
          expect(bridge.verifiedData.length, verifiedBefore + 1);
          expect(replayResult, HandleMessageResult.invalidMessage);
          expect(
            (await requests.getRequest(_bobId.peerId))?.toMap(),
            declined.toMap(),
          );
          expect(await requests.getPendingRequests(), isEmpty);
          expect(await contacts.getContact(_bobId.peerId), isNull);
          expect(prompted, isEmpty);
          expect(autoAddCalls, 0);
        }
        expect(cutoffMs, greaterThan(firstDecisionMs));
        expect(cutoffMs, greaterThan(intermediateMs));

        // A genuinely different signed request strictly after the last
        // decision remains eligible for a new manual decision.
        final freshTs = DateTime.fromMillisecondsSinceEpoch(
          cutoffMs + 1,
          isUtc: true,
        ).toIso8601String();
        final freshWire = await buildRepairWire(
          bus: _cryptoBus,
          signer: _bobId,
          recipientPublicKey: _aliceId.publicKey,
          ts: freshTs,
          outerTs: freshTs,
          mlKem: 'new-signed-request-after-decisions',
        );
        expect(
          await receiver!.processIncomingMessage(freshWire),
          HandleMessageResult.contactRequest,
        );
        final fresh = await firstPrompt.future;
        expect(fresh.signature, isNot(declined.signature));
        expect(prompted, hasLength(1));
        expect(
          (await requests.getPendingRequests()).single.signature,
          fresh.signature,
        );
        expect(await contacts.getContact(_bobId.peerId), isNull);
        expect(autoAddCalls, 0);
      },
    );

    for (final state in ['accepted', 'blocked']) {
      test(
        'late arrival preserves reopened $state authority and consent',
        () async {
          final now = DateTime.now().toUtc().toIso8601String();
          final current =
              contactFor(_bobId, mlKem: 'current-key', scannedAt: now).copyWith(
                mlKemKeyUpdatedTs: now,
                isArchived: true,
                isBlocked: state == 'blocked',
              );
          await contacts.addContact(current);
          await requests.addRequest(
            ContactRequestModel(
              peerId: _bobId.peerId,
              publicKey: _bobId.publicKey,
              rendezvous: current.rendezvous,
              username: 'Bob',
              signature: 'previous-request-signature',
              receivedAt: now,
              status: state == 'accepted'
                  ? ContactRequestStatus.accepted
                  : ContactRequestStatus.pending,
            ),
          );

          await reopen(enableAutoAdd: true);
          final before = await contacts.getContact(_bobId.peerId);
          expect(
            await receiver!.processIncomingMessage(lateWire),
            HandleMessageResult.alreadyContact,
          );
          expect(bridge.verifiedData, hasLength(1));
          expect(autoAddCalls, 0);
          expect(
            (await contacts.getContact(_bobId.peerId))?.toMap(),
            before?.toMap(),
          );
          expect(prompted, isEmpty);
          expect(
            (await requests.getRequest(_bobId.peerId))?.status,
            state == 'accepted'
                ? ContactRequestStatus.accepted
                : ContactRequestStatus.pending,
          );
        },
      );
    }
  });
}

class _RecordingWakeTokenStore implements ReceivedWakeTokenStore {
  final tokens = <String, Map<String, String>>{};
  int writes = 0;

  @override
  Future<Map<String, String>?> readTokenFor(String peerId) async =>
      tokens[peerId];

  @override
  Future<void> writeTokenFor(
    String peerId,
    String token,
    String ts, {
    Future<bool> Function(Future<void> Function() write)? writeIfAuthorized,
  }) async {
    Future<void> write() async {
      if (writeIfAuthorized != null) {
        final incoming = DateTime.tryParse(ts);
        final previous = DateTime.tryParse(tokens[peerId]?['ts'] ?? '');
        if (incoming == null ||
            (previous != null && !incoming.isAfter(previous))) {
          return;
        }
      }
      writes++;
      tokens[peerId] = {'tok': token, 'ts': ts};
    }

    if (writeIfAuthorized == null) {
      await write();
    } else {
      await writeIfAuthorized(write);
    }
  }

  @override
  Future<void> removeTokenFor(String peerId) async {
    tokens.remove(peerId);
  }

  @override
  Future<void> clear() async {
    tokens.clear();
  }
}
