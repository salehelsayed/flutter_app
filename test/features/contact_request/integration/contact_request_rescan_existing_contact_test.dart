import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/contact_request/application/accept_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/qr_code/application/build_qr_payload_use_case.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_screen.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/deterministic_contact_request_crypto.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_contact_request_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';

// ---------------------------------------------------------------------------
// Pairing deadlock after a one-sided re-add (device finding 2026-10-16).
//
// A deleted B and re-added B from B's compact QR, which carries no ML-KEM key.
// A now holds B with `mlKemPublicKey == null`, so A's call roster for B is
// empty: A's call button is unavailable and B's invites fail the
// `sender_unknown` gate. B still holds A complete. Only a contact request SENT
// BY B can hand A the key, and B's scanner used to send nothing when A was
// already in B's circle. These tests drive B's real scanner against A's real
// listener over a sqflite-backed contact table, so the production call roster
// (`DatabaseCallTrustedRosterProvider`) is the witness on A's side.
// ---------------------------------------------------------------------------

// Task 12b: real Ed25519 identities, so each peer ID is the libp2p ID of its
// key (the QR parser and the receiver now check that binding).
final _a = TestEd25519Identity.fromSeedByte(0xC8);
final _b = TestEd25519Identity.fromSeedByte(0xC9);
final _aPeerId = _a.peerId;
final _bPeerId = _b.peerId;
final _aPublicKey = _a.publicKey;
final _bPublicKey = _b.publicKey;
const _aPrivateKey = 'a-private-key';
const _bPrivateKey = 'b-private-key';
const _aMlKemKey = 'a-mlkem-public-key';
const _bMlKemKey = 'b-mlkem-public-key';
const _rendezvous = '/dns4/relay.example/tcp/4001/p2p/relay';
const _scannedAt = '2026-01-01T00:00:00.000Z';

IdentityModel _identity({
  required String peerId,
  required String publicKey,
  required String privateKey,
  required String mlKemPublicKey,
}) => IdentityModel(
  peerId: peerId,
  publicKey: publicKey,
  privateKey: privateKey,
  mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
  mlKemPublicKey: mlKemPublicKey,
  mlKemSecretKey: 'secret-$mlKemPublicKey',
  username: 'User-$peerId',
  createdAt: _scannedAt,
  updatedAt: _scannedAt,
);

Future<ContactModel?> _ignoreAvatarDownload({
  required Bridge bridge,
  required ContactRepository contactRepo,
  required String ownerPeerId,
  required String avatarVersion,
  bool retryPendingRequest = false,
}) async => null;

ContactRepositoryImpl _databaseContactRepository(Database db) =>
    ContactRepositoryImpl(
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

Future<void> _pumpFrames(WidgetTester tester, {int count = 12}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A and B over one fake network. A's contacts live in a real sqflite table so
/// the production call roster can read them. B re-scans A's QR through the
/// real scanner widget.
final class _Pair {
  _Pair._({
    required this.db,
    required this.network,
    required this.aBridge,
    required this.bBridge,
    required this.aP2p,
    required this.bP2p,
    required this.aContacts,
    required this.bContacts,
    required this.aIdentity,
    required this.bIdentity,
    required this.aReceivedGrants,
    required this.bGrantForA,
    required this.bRowForABefore,
  }) : aRoster = DatabaseCallTrustedRosterProvider(db);

  final Database db;
  final FakeP2PNetwork network;
  final DeterministicContactRequestBridge aBridge;
  final DeterministicContactRequestBridge bBridge;
  final FakeP2PService aP2p;
  final FakeP2PService bP2p;
  final ContactRepositoryImpl aContacts;
  final InMemoryContactRepository bContacts;
  final FakeIdentityRepository aIdentity;
  final FakeIdentityRepository bIdentity;
  final InMemoryReceivedCallWakeHandleStore aReceivedGrants;
  final DatabaseCallTrustedRosterProvider aRoster;

  /// The grant B issues to A. B holds A complete, so production's resolver
  /// would issue one; the harness stands in for that resolver.
  final CallWakeHandleGrant bGrantForA;
  final Map<String, dynamic> bRowForABefore;

  /// Everything the fake network delivered to A. A's listener is not started:
  /// the test hands each message to `processIncomingMessage` itself so the
  /// returned result is observable.
  final List<ChatMessage> aReceived = <ChatMessage>[];
  final List<(String, CallWakeHandleGrant)> bDistributed =
      <(String, CallWakeHandleGrant)>[];
  late final ContactRequestListener aListener;
  late final ContactRequestListener bListener;
  var aReciprocals = 0;

  static Future<_Pair> create({required bool aHoldsBKey}) async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    final bus = ContactRequestCryptoBus()
      ..privateKeyByPublicKey.addAll(<String, String>{
        _aPublicKey: _aPrivateKey,
        _bPublicKey: _bPrivateKey,
      });
    final network = FakeP2PNetwork();
    final aContacts = _databaseContactRepository(db);
    await aContacts.addContact(
      ContactModel(
        peerId: _bPeerId,
        publicKey: _bPublicKey,
        rendezvous: _rendezvous,
        username: 'B',
        signature: 'b-qr-signature',
        scannedAt: _scannedAt,
        mlKemPublicKey: aHoldsBKey ? _bMlKemKey : null,
      ),
    );
    final bContacts = InMemoryContactRepository()
      ..addTestContact(
        ContactModel(
          peerId: _aPeerId,
          publicKey: _aPublicKey,
          rendezvous: _rendezvous,
          username: 'A',
          signature: 'a-qr-signature',
          scannedAt: _scannedAt,
          mlKemPublicKey: _aMlKemKey,
        ),
      );
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final pair = _Pair._(
      db: db,
      network: network,
      aBridge: DeterministicContactRequestBridge(bus),
      bBridge: DeterministicContactRequestBridge(bus),
      aP2p: FakeP2PService(peerId: _aPeerId, network: network),
      bP2p: FakeP2PService(peerId: _bPeerId, network: network),
      aContacts: aContacts,
      bContacts: bContacts,
      aIdentity: FakeIdentityRepository()
        ..seed(
          _identity(
            peerId: _aPeerId,
            publicKey: _aPublicKey,
            privateKey: _aPrivateKey,
            mlKemPublicKey: _aMlKemKey,
          ),
        ),
      bIdentity: FakeIdentityRepository()
        ..seed(
          _identity(
            peerId: _bPeerId,
            publicKey: _bPublicKey,
            privateKey: _bPrivateKey,
            mlKemPublicKey: _bMlKemKey,
          ),
        ),
      aReceivedGrants: InMemoryReceivedCallWakeHandleStore(),
      bGrantForA: CallWakeHandleGrant(
        handle: '0123456789abcdef0123456789abcdef',
        recipientDevicePeerId: _aPeerId,
        deviceKeyEpoch: 1,
        generation: 1,
        issuedAtMs: nowMs - 1000,
        expiresAtMs: nowMs + const Duration(hours: 1).inMilliseconds,
      ),
      bRowForABefore: (await bContacts.getContact(_aPeerId))!.toMap(),
    );
    pair.aP2p.messageStream.listen(pair.aReceived.add);
    // Same receipt seam as the call-wake backfill test: the fake network has
    // no deferred ACK, so B's reply is built from the challenge B itself
    // signed.
    pair.bP2p.directReplyBuilder = (targetPeerId, message, delivered) {
      final challenge = pair.bBridge.encryptedPlaintexts.last['cwr'];
      return SendMessageResult(
        sent: delivered,
        acked: delivered,
        reply: !delivered
            ? null
            : challenge is String
            ? jsonEncode(<String, String>{'callWakeReceipt': challenge})
            : 'received: $message',
      );
    };
    pair.aListener = ContactRequestListener(
      contactRequestStream: pair.aP2p.messageStream,
      requestRepo: InMemoryContactRequestRepository(),
      contactRepo: aContacts,
      bridge: pair.aBridge,
      getOwnPeerId: () => _aPeerId,
      getOwnPrivateKey: () async => _aPrivateKey,
      downloadProfilePictureFn: _ignoreAvatarDownload,
      receivedCallWakeHandleStore: pair.aReceivedGrants,
      autoAcceptAndReciprocate: (_) async {
        pair.aReciprocals += 1;
        return AcceptContactRequestResult.success;
      },
    );
    pair.bListener = ContactRequestListener(
      contactRequestStream: pair.bP2p.messageStream,
      requestRepo: InMemoryContactRequestRepository(),
      contactRepo: bContacts,
      bridge: pair.bBridge,
      getOwnPeerId: () => _bPeerId,
      getOwnPrivateKey: () async => _bPrivateKey,
      downloadProfilePictureFn: _ignoreAvatarDownload,
    );
    return pair;
  }

  /// B scans A's real signed QR through B's real scanner widget.
  Future<void> rescanAAsB(WidgetTester tester) async {
    final (built, qr) = await buildQRPayload(
      repo: aIdentity,
      callSign: (data, privateKey) => callSignPayload(
        bridge: aBridge,
        dataToSign: data,
        privateKey: privateKey,
      ),
    );
    expect(built, BuildQRPayloadResult.success);

    final bMessages = InMemoryMessageRepository();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QRScannerWired(
          bridge: bBridge,
          contactRepository: bContacts,
          contactRequestRepository: InMemoryContactRequestRepository(),
          contactRequestListener: bListener,
          messageRepository: bMessages,
          mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
          chatMessageListener: ChatMessageListener(
            chatMessageStream: const Stream<ChatMessage>.empty(),
            messageRepo: bMessages,
            contactRepo: bContacts,
            bridge: bBridge,
            getOwnMlKemSecretKey: () async => null,
          ),
          identityRepository: bIdentity,
          p2pService: bP2p,
          mediaFileManager: FakeMediaFileManager(),
          secureKeyStore: FakeSecureKeyStore(),
          imageProcessor: ImageProcessor(
            compressFile:
                ({
                  required path,
                  required quality,
                  required keepExif,
                  minWidth = 1920,
                  minHeight = 1080,
                }) async => null,
            compressVideo:
                ({required path, required compress, onProgress}) async => null,
          ),
          ownPeerId: _bPeerId,
          downloadProfilePictureFn: _ignoreAvatarDownload,
          resolveCallWakeHandle: (peerId) async =>
              peerId == _aPeerId ? bGrantForA : null,
          // No `expect` in here: this runs inside a pump, where
          // flutter_test's guarded expect throws.
          onCallWakeHandleDistributed: (peerId, grant) async =>
              bDistributed.add((peerId, grant)),
        ),
      ),
    );
    await _pumpFrames(tester);
    tester.widget<QRScannerScreen>(find.byType(QRScannerScreen)).onScanned(qr!);
    await _pumpFrames(tester, count: 20);
  }

  Future<void> dispose() async {
    aListener.dispose();
    bListener.dispose();
    aP2p.dispose();
    bP2p.dispose();
    if (db.isOpen) await db.close();
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  testWidgets(
    'B re-scanning A hands A the missing ML-KEM key and opens calls both ways',
    (tester) async {
      final pair = await _Pair.create(aHoldsBKey: false);
      addTearDown(pair.dispose);

      // BEFORE: the deadlock as found. A accepted B but trusts no call device
      // for B, so A cannot place a call to B and B's invites resolve to no
      // sender (the `sender_unknown` admission gate).
      final before = await pair.aRoster.loadForContact(_bPeerId);
      expect(before.contactAccepted, isTrue);
      expect(before.devices, isEmpty);
      expect(
        await pair.aRoster.resolveAuthenticatedTransport(_bPeerId),
        isNull,
      );
      expect(await pair.aReceivedGrants.readForIssuer(_bPeerId), isNull);

      await pair.rescanAAsB(tester);

      expect(find.text('Already in your circle!'), findsOneWidget);
      expect(pair.aReceived, hasLength(1));
      final result = await pair.aListener.processIncomingMessage(
        pair.aReceived.single,
      );
      expect(result, HandleMessageResult.contactKeyUpdated);

      // AFTER: A trusts exactly one call device for B, B's own account target
      // carrying B's ML-KEM key, for outgoing calls...
      final after = await pair.aRoster.loadForContact(_bPeerId);
      expect(after.devices, hasLength(1));
      expect(after.devices.single.devicePeerId, _bPeerId);
      expect(after.devices.single.mlKemPublicKey, _bMlKemKey);
      expect(after.devices.single.signingPublicKey, _bPublicKey);
      // ...and B's transport authenticates for an incoming invite.
      expect(
        (await pair.aRoster.resolveAuthenticatedTransport(
          _bPeerId,
        ))?.devicePeerId,
        _bPeerId,
      );
      expect(
        await pair.aReceivedGrants.readForIssuer(_bPeerId),
        pair.bGrantForA,
      );
      expect(pair.bDistributed, [(_aPeerId, pair.bGrantForA)]);

      expect(await pair.aContacts.getContactCount(), 1);
      expect(
        (await pair.aContacts.getContact(_bPeerId))?.mlKemPublicKey,
        _bMlKemKey,
      );
      expect(pair.aReciprocals, 0);
      expect(await pair.bContacts.getContactCount(), 1);
      expect(
        (await pair.bContacts.getContact(_aPeerId))?.toMap(),
        pair.bRowForABefore,
      );
    },
  );

  testWidgets(
    'B re-scanning A when both already hold keys changes nothing on A and A '
    'sends nothing back',
    (tester) async {
      final pair = await _Pair.create(aHoldsBKey: true);
      addTearDown(pair.dispose);
      final aRowBefore = (await pair.aContacts.getContact(_bPeerId))!.toMap();
      expect(aRowBefore['ml_kem_public_key'], _bMlKemKey);

      await pair.rescanAAsB(tester);

      expect(find.text('Already in your circle!'), findsOneWidget);
      expect(pair.aReceived, hasLength(1));
      final result = await pair.aListener.processIncomingMessage(
        pair.aReceived.single,
      );
      expect(result, HandleMessageResult.alreadyContact);

      expect((await pair.aContacts.getContact(_bPeerId))!.toMap(), aRowBefore);
      expect(await pair.aContacts.getContactCount(), 1);
      expect(pair.aReciprocals, 0);
      // Exactly one frame crossed the network: B's request. A replied with no
      // request of its own, so a re-scan cannot start a loop.
      expect(pair.network.deliverCallCount, 1);
      expect(pair.network.storeInInboxCallCount, 0);
      expect(pair.aBridge.encryptedPlaintexts, isEmpty);
      expect(pair.bBridge.encryptedPlaintexts, hasLength(1));
      expect(await pair.bContacts.getContactCount(), 1);
    },
  );
}
