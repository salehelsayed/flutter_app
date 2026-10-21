import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
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
final _aliceId = TestEd25519Identity.fromSeedByte(0x41);
final _bobId = TestEd25519Identity.fromSeedByte(0x42);

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

ContactRepositoryImpl _buildContactRepo(
  Database db, {
  void Function()? onLoadContactCompleted,
}) => ContactRepositoryImpl(
  dbLoadAllContacts: () => dbLoadAllContacts(db),
  dbLoadContact: (peerId) async {
    final row = await dbLoadContact(db, peerId);
    onLoadContactCompleted?.call();
    return row;
  },
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
    tempDir = await Directory.systemTemp.createTemp('cr013_it_');
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

  group('CR-013 accepting survives a crash halfway through', () {
    test(
      'crash between adding the contact and marking the request accepted leaves one contact and does not re-prompt on restart',
      () async {
        var crashOnStatusUpdate = true;
        var aliceContacts = _buildContactRepo(aliceDb);
        var aliceRequests = ContactRequestRepositoryImpl(
          dbLoadPendingRequests: () => dbLoadPendingRequests(aliceDb),
          dbLoadRequest: (peerId) => dbLoadRequest(aliceDb, peerId),
          dbUpsertRequest: (row) => dbUpsertRequest(aliceDb, row),
          dbUpdateRequestStatus: (peerId, status) async {
            if (crashOnStatusUpdate) {
              throw StateError(
                'simulated crash after contactRepo.addContact and before requestRepo.updateStatus',
              );
            }
            await dbUpdateRequestStatus(aliceDb, peerId, status);
          },
          dbDeleteRequest: (peerId) => dbDeleteRequest(aliceDb, peerId),
          dbRequestExists: (peerId) => dbRequestExists(aliceDb, peerId),
        );

        final bobIdentities = _buildIdentityRepo(bobDb, FakeSecureKeyStore());
        await bobIdentities.saveIdentity(
          testIdentityModel(
            _bobId,
            username: 'Bob',
            mlKemPublicKey: 'mlkem-bob-initial',
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
        final initialPrompts = <ContactRequestModel>[];
        final firstPromptBarrier = Completer<void>();
        var promptSub = aliceListener.requestStream.listen((request) {
          initialPrompts.add(request);
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

        // 1. Bob sends a valid v2 request; Alice stores it pending.
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
        expect(initialPrompts, hasLength(1));

        // 2. Alice accepts, and the process crashes between adding the contact
        // and updating the request status to accepted.
        await acceptContactRequest(
          requestRepo: aliceRequests,
          contactRepo: aliceContacts,
          peerId: _bobId.peerId,
        );

        // 3. Simulate app restart on the same SQLite database file.
        await promptSub.cancel();
        aliceListener.dispose();
        aliceP2p.dispose();
        await aliceDb.close();

        crashOnStatusUpdate = false;
        aliceDb = await _openDb(aliceDbPath);
        final attachReplayBarrier = Completer<void>();
        aliceContacts = _buildContactRepo(
          aliceDb,
          onLoadContactCompleted: () {
            if (!attachReplayBarrier.isCompleted) {
              attachReplayBarrier.complete();
            }
          },
        );
        aliceRequests = ContactRequestRepositoryImpl(
          dbLoadPendingRequests: () async {
            final rows = await dbLoadPendingRequests(aliceDb);
            if (rows.isEmpty && !attachReplayBarrier.isCompleted) {
              attachReplayBarrier.complete();
            }
            return rows;
          },
          dbLoadRequest: (peerId) => dbLoadRequest(aliceDb, peerId),
          dbUpsertRequest: (row) => dbUpsertRequest(aliceDb, row),
          dbUpdateRequestStatus: (peerId, status) =>
              dbUpdateRequestStatus(aliceDb, peerId, status),
          dbDeleteRequest: (peerId) => dbDeleteRequest(aliceDb, peerId),
          dbRequestExists: (peerId) => dbRequestExists(aliceDb, peerId),
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

        final replayedAfterCrash = <ContactRequestModel>[];
        promptSub = aliceListener.requestStream.listen(replayedAfterCrash.add);
        aliceListener.start();
        await attachReplayBarrier.future;
        await Future<void>(() {});

        expect(await aliceContacts.getContactCount(), 1);
        expect(
          replayedAfterCrash,
          isEmpty,
          reason:
              'A request whose contact was already added before a crash must not re-prompt on restart',
        );
      },
      skip:
          'KNOWN GAP CR-013: acceptContactRequest writes contact and request status non-atomically so a crash after addContact leaves the request pending and re-prompts on attach, lib/features/contact_request/application/accept_contact_request_use_case.dart:70-82. Remove when fixed.',
    );

    test(
      'repeated accept after a mid-accept crash preserves rotated ML-KEM key, archive, and block state on the existing contact',
      () async {
        var crashOnStatusUpdate = true;
        final aliceContacts = _buildContactRepo(aliceDb);
        final aliceRequests = ContactRequestRepositoryImpl(
          dbLoadPendingRequests: () => dbLoadPendingRequests(aliceDb),
          dbLoadRequest: (peerId) => dbLoadRequest(aliceDb, peerId),
          dbUpsertRequest: (row) => dbUpsertRequest(aliceDb, row),
          dbUpdateRequestStatus: (peerId, status) async {
            if (crashOnStatusUpdate) {
              throw StateError(
                'simulated crash after contactRepo.addContact and before requestRepo.updateStatus',
              );
            }
            await dbUpdateRequestStatus(aliceDb, peerId, status);
          },
          dbDeleteRequest: (peerId) => dbDeleteRequest(aliceDb, peerId),
          dbRequestExists: (peerId) => dbRequestExists(aliceDb, peerId),
        );

        final bobIdentities = _buildIdentityRepo(bobDb, FakeSecureKeyStore());
        await bobIdentities.saveIdentity(
          testIdentityModel(
            _bobId,
            username: 'Bob',
            mlKemPublicKey: 'mlkem-bob-initial',
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

        // First accept crashes after adding the contact and before marking the
        // request row accepted.
        await acceptContactRequest(
          requestRepo: aliceRequests,
          contactRepo: aliceContacts,
          peerId: _bobId.peerId,
        );
        expect(await aliceContacts.getContactCount(), 1);
        expect(
          (await aliceRequests.getRequest(_bobId.peerId))?.status,
          ContactRequestStatus.pending,
        );

        // Update Bob's contact state (rotated ML-KEM key, archived, blocked)
        // and run a repeated accept: it must not clobber the contact's current
        // key, archive, or block state.
        crashOnStatusUpdate = false;
        final currentBob = (await aliceContacts.getContact(_bobId.peerId))!;
        await aliceContacts.addContact(
          currentBob.copyWith(
            mlKemPublicKey: 'mlkem-bob-rotated',
            mlKemKeyUpdatedTs: '2026-10-19T15:00:00.000Z',
          ),
        );
        await aliceContacts.archiveContact(_bobId.peerId);
        await aliceContacts.blockContact(_bobId.peerId);

        await acceptContactRequest(
          requestRepo: aliceRequests,
          contactRepo: aliceContacts,
          peerId: _bobId.peerId,
        );

        expect(await aliceContacts.getContactCount(), 1);
        final bobAfterRepeatAccept = (await aliceContacts.getContact(
          _bobId.peerId,
        ))!;
        expect(bobAfterRepeatAccept.mlKemPublicKey, 'mlkem-bob-rotated');
        expect(bobAfterRepeatAccept.isArchived, isTrue);
        expect(bobAfterRepeatAccept.isBlocked, isTrue);
        expect(
          (await aliceRequests.getRequest(_bobId.peerId))?.status,
          ContactRequestStatus.accepted,
        );
      },
      skip:
          'KNOWN GAP CR-013: repeated acceptContactRequest on a leftover pending row overwrites an existing contact via request.toContactModel() with default flags and older key, lib/features/contact_request/application/accept_contact_request_use_case.dart:68-70. Remove when fixed.',
    );
  });
}
