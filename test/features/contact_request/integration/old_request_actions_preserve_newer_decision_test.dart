import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_notification_materializer.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
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
final _aliceId = TestEd25519Identity.fromSeedByte(0x51);
final _bobId = TestEd25519Identity.fromSeedByte(0x52);

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

ContactRequestRepositoryImpl _buildRequestRepo(Database db) =>
    ContactRequestRepositoryImpl(
      dbLoadPendingRequests: () => dbLoadPendingRequests(db),
      dbLoadRequest: (peerId) => dbLoadRequest(db, peerId),
      dbUpsertRequest: (row) => dbUpsertRequest(db, row),
      dbUpdateRequestStatus: (peerId, status) =>
          dbUpdateRequestStatus(db, peerId, status),
      dbDeleteRequest: (peerId) => dbDeleteRequest(db, peerId),
      dbRequestExists: (peerId) => dbRequestExists(db, peerId),
    );

void main() {
  late Directory tempDir;
  late Database aliceDb;
  late Database bobDb;
  late FakeP2PNetwork network;

  setUp(() async {
    _cryptoBus
      ..register(_aliceId)
      ..register(_bobId);
    tempDir = await Directory.systemTemp.createTemp('cr017_it_');
    aliceDb = await _openDb('${tempDir.path}/alice.db');
    bobDb = await _openDb('${tempDir.path}/bob.db');
    network = FakeP2PNetwork();
  });

  tearDown(() async {
    await aliceDb.close();
    await bobDb.close();
    await tempDir.delete(recursive: true);
  });

  group('CR-017 old request actions cannot undo a newer decision', () {
    test(
      'stale notification accept after the request was declined does not open a conversation without a current contact',
      () async {
        final aliceContacts = _buildContactRepo(aliceDb);
        final aliceRequests = _buildRequestRepo(aliceDb);
        final aliceIdentities = _buildIdentityRepo(
          aliceDb,
          FakeSecureKeyStore(),
        );
        final bobIdentities = _buildIdentityRepo(bobDb, FakeSecureKeyStore());
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
            mlKemPublicKey: 'mlkem-bob-old',
          ),
        );

        final aliceBridge = Ed25519ContactRequestBridge(_cryptoBus);
        final bobBridge = Ed25519ContactRequestBridge(_cryptoBus);
        final aliceP2p = FakeP2PService(
          peerId: _aliceId.peerId,
          network: network,
        );
        final bobP2p = FakeP2PService(peerId: _bobId.peerId, network: network);

        final aliceListener = ContactRequestListener(
          contactRequestStream: aliceP2p.messageStream,
          requestRepo: aliceRequests,
          contactRepo: aliceContacts,
          bridge: aliceBridge,
          getOwnPeerId: () => _aliceId.peerId,
          getOwnPrivateKey: () async => _aliceId.privateKey,
          getOwnPublicKey: () async => _aliceId.publicKey,
          downloadProfilePictureFn: _settledAvatar,
        );
        final firstPromptBarrier = Completer<ContactRequestModel>();
        final promptSub = aliceListener.requestStream.listen((request) {
          if (!firstPromptBarrier.isCompleted) {
            firstPromptBarrier.complete(request);
          }
        });
        aliceListener.start();
        addTearDown(() async {
          await promptSub.cancel();
          aliceListener.dispose();
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
        final pendingRequest = await firstPromptBarrier.future;
        expect(pendingRequest.status, ContactRequestStatus.pending);

        final openedConversations = <ContactModel>[];
        final errors = <String>[];
        final materializer = ContactRequestNotificationMaterializer(
          requestRepository: aliceRequests,
          contactRepository: aliceContacts,
          identityRepository: aliceIdentities,
          p2pService: aliceP2p,
          bridge: aliceBridge,
          presentPendingRequest:
              ({
                required navigator,
                required request,
                required onAccept,
                required onDecline,
              }) async {},
          openConversation: ({required navigator, required contact}) async {
            openedConversations.add(contact);
          },
          showError: ({required navigator, required message}) {
            errors.add(message);
          },
        );

        expect(
          await declineContactRequest(
            requestRepo: aliceRequests,
            peerId: _bobId.peerId,
          ),
          DeclineContactRequestResult.success,
        );
        expect(await aliceContacts.getContact(_bobId.peerId), isNull);

        await materializer.acceptRequest(
          navigator: NavigatorState(),
          request: pendingRequest,
        );

        expect(
          openedConversations,
          isEmpty,
          reason:
              'Accepting from a stale dialog after the request was declined must not open a conversation without a current contact',
        );
        expect(await aliceContacts.getContact(_bobId.peerId), isNull);
      },
      skip:
          'KNOWN GAP CR-017: ContactRequestNotificationMaterializer.acceptRequest treats notPending on a declined request as success and opens a synthesized contact when no contact row exists, lib/features/contact_request/application/contact_request_notification_materializer.dart:103-108. Remove when fixed.',
    );

    test(
      'stale decline action does not turn an already-accepted request back into declined',
      () async {
        final aliceContacts = _buildContactRepo(aliceDb);
        final aliceRequests = _buildRequestRepo(aliceDb);
        final bobIdentities = _buildIdentityRepo(bobDb, FakeSecureKeyStore());
        await bobIdentities.saveIdentity(
          testIdentityModel(
            _bobId,
            username: 'Bob',
            mlKemPublicKey: 'mlkem-bob-old',
          ),
        );

        final aliceBridge = Ed25519ContactRequestBridge(_cryptoBus);
        final bobBridge = Ed25519ContactRequestBridge(_cryptoBus);
        final aliceP2p = FakeP2PService(
          peerId: _aliceId.peerId,
          network: network,
        );
        final bobP2p = FakeP2PService(peerId: _bobId.peerId, network: network);

        final aliceListener = ContactRequestListener(
          contactRequestStream: aliceP2p.messageStream,
          requestRepo: aliceRequests,
          contactRepo: aliceContacts,
          bridge: aliceBridge,
          getOwnPeerId: () => _aliceId.peerId,
          getOwnPrivateKey: () async => _aliceId.privateKey,
          getOwnPublicKey: () async => _aliceId.publicKey,
          downloadProfilePictureFn: _settledAvatar,
        );
        final firstPromptBarrier = Completer<void>();
        final promptSub = aliceListener.requestStream.listen((_) {
          if (!firstPromptBarrier.isCompleted) {
            firstPromptBarrier.complete();
          }
        });
        aliceListener.start();
        addTearDown(() async {
          await promptSub.cancel();
          aliceListener.dispose();
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

        expect(
          await acceptContactRequest(
            requestRepo: aliceRequests,
            contactRepo: aliceContacts,
            peerId: _bobId.peerId,
          ),
          AcceptContactRequestResult.success,
        );
        expect(
          (await aliceRequests.getRequest(_bobId.peerId))?.status,
          ContactRequestStatus.accepted,
        );

        await declineContactRequest(
          requestRepo: aliceRequests,
          peerId: _bobId.peerId,
        );
        expect(
          (await aliceRequests.getRequest(_bobId.peerId))?.status,
          ContactRequestStatus.accepted,
          reason:
              'A stale decline action must not turn an already-accepted request into declined',
        );
      },
      skip:
          'KNOWN GAP CR-017: declineContactRequest updates any existing request row by peerId without checking that its status is still pending, lib/features/contact_request/application/decline_contact_request_use_case.dart:45-47. Remove when fixed.',
    );

    test(
      'stale accept action on a leftover pending row does not overwrite a newer blocked contact or its newer ML-KEM key',
      () async {
        final aliceContacts = _buildContactRepo(aliceDb);
        final aliceRequests = _buildRequestRepo(aliceDb);
        final bobIdentities = _buildIdentityRepo(bobDb, FakeSecureKeyStore());
        await bobIdentities.saveIdentity(
          testIdentityModel(
            _bobId,
            username: 'Bob',
            mlKemPublicKey: 'mlkem-bob-old',
          ),
        );

        final aliceBridge = Ed25519ContactRequestBridge(_cryptoBus);
        final bobBridge = Ed25519ContactRequestBridge(_cryptoBus);
        final aliceP2p = FakeP2PService(
          peerId: _aliceId.peerId,
          network: network,
        );
        final bobP2p = FakeP2PService(peerId: _bobId.peerId, network: network);

        final aliceListener = ContactRequestListener(
          contactRequestStream: aliceP2p.messageStream,
          requestRepo: aliceRequests,
          contactRepo: aliceContacts,
          bridge: aliceBridge,
          getOwnPeerId: () => _aliceId.peerId,
          getOwnPrivateKey: () async => _aliceId.privateKey,
          getOwnPublicKey: () async => _aliceId.publicKey,
          downloadProfilePictureFn: _settledAvatar,
        );
        final firstPromptBarrier = Completer<void>();
        final promptSub = aliceListener.requestStream.listen((_) {
          if (!firstPromptBarrier.isCompleted) {
            firstPromptBarrier.complete();
          }
        });
        aliceListener.start();
        addTearDown(() async {
          await promptSub.cancel();
          aliceListener.dispose();
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

        // Bob is already added with a newer ML-KEM key and blocked while the
        // older pending request row remains in contact_requests.
        await aliceContacts.addContact(
          ContactModel(
            peerId: _bobId.peerId,
            publicKey: _bobId.publicKey,
            rendezvous: 'rv-bob',
            username: 'Bob',
            signature: 'sig-bob',
            scannedAt: '2026-10-19T16:00:00.000Z',
            mlKemPublicKey: 'mlkem-bob-newer',
            mlKemKeyUpdatedTs: '2026-10-19T16:00:00.000Z',
          ),
        );
        await aliceContacts.blockContact(_bobId.peerId);

        await acceptContactRequest(
          requestRepo: aliceRequests,
          contactRepo: aliceContacts,
          peerId: _bobId.peerId,
        );

        final bobAfterStaleAccept = (await aliceContacts.getContact(
          _bobId.peerId,
        ))!;
        expect(bobAfterStaleAccept.isBlocked, isTrue);
        expect(bobAfterStaleAccept.mlKemPublicKey, 'mlkem-bob-newer');
      },
      skip:
          'KNOWN GAP CR-017: acceptContactRequest checks only that the request row is pending and overwrites an existing blocked contact with default flags and the stale request key, lib/features/contact_request/application/accept_contact_request_use_case.dart:47-70. Remove when fixed.',
    );
  });
}
