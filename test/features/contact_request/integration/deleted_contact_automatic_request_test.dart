import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/application/add_contact_use_case.dart';
import 'package:flutter_app/features/contacts/application/delete_contact_use_case.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../presentation/support/contact_request_sql_fixture.dart';
import '../support/contact_repair_harness.dart';

// No profile transport or delayed avatar retry is needed to observe the real
// listener's prompt stream. Return a settled projection even for a pending peer.
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

// The presentation fixture omits lifecycle recovery. Contact deletion must
// inspect that inventory too, using the same SQL closure as production.
MessageRepositoryImpl _deletionMessageRepository(Database db) {
  final sql = buildWidgetMessageRepository(db);
  return MessageRepositoryImpl(
    dbInsertMessage: sql.dbInsertMessage,
    dbLoadMessagesForContact: sql.dbLoadMessagesForContact,
    dbLoadLatestMessageForContact: sql.dbLoadLatestMessageForContact,
    dbUpdateMessageStatus: sql.dbUpdateMessageStatus,
    dbLoadMessage: sql.dbLoadMessage,
    dbCountMessagesForContact: sql.dbCountMessagesForContact,
    dbMarkConversationAsRead: sql.dbMarkConversationAsRead,
    dbCountUnreadForContact: sql.dbCountUnreadForContact,
    dbCountTotalUnread: sql.dbCountTotalUnread,
    dbCountTotalUnreadExcludingArchived:
        sql.dbCountTotalUnreadExcludingArchived,
    dbDeleteMessagesForContact: sql.dbDeleteMessagesForContact,
    dbDeleteMessage: sql.dbDeleteMessage,
    dbExistsMessageByContent: sql.dbExistsMessageByContent,
    dbLoadMessagesPage: sql.dbLoadMessagesPage,
    dbLoadFailedOutgoingMessages: sql.dbLoadFailedOutgoingMessages,
    dbLoadUnackedOutgoingMessages: sql.dbLoadUnackedOutgoingMessages,
    dbLoadConversationThreadSummaries: sql.dbLoadConversationThreadSummaries,
    dbRecoverStuckSendingMessages: sql.dbRecoverStuckSendingMessages,
    dbLoadStuckSendingOutgoingMessages: sql.dbLoadStuckSendingOutgoingMessages,
    dbLoadSendingOutgoingMessages: sql.dbLoadSendingOutgoingMessages,
    dbConditionalTransitionStatus: sql.dbConditionalTransitionStatus,
    dbLoadDirectPrivateMediaRecoveryCandidates: ({limit = 100}) =>
        dbLoadDirectPrivateMediaRecoveryCandidates(db, limit: limit),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final receiver = TestEd25519Identity.fromSeedByte(0x61);
  final sender = TestEd25519Identity.fromSeedByte(0x62);
  final wrongSigner = TestEd25519Identity.fromSeedByte(0x63);
  late Database receiverDb;
  late Database senderDb;
  late ContactRepositoryImpl contacts;
  late ContactRequestRepositoryImpl requests;
  late SqlContactRepairRepository repairs;
  late Ed25519ContactRequestCryptoBus crypto;
  late Ed25519ContactRequestBridge receiverBridge;
  late Ed25519ContactRequestBridge senderBridge;
  late FakeP2PService receiverTransport;
  late FakeP2PService senderTransport;
  late ContactRequestListener listener;
  late StreamSubscription<ContactRequestModel> promptSubscription;
  late List<ContactRequestModel> prompts;

  setUp(() async {
    receiverDb = await openRepairTestDatabase();
    senderDb = await openRepairTestDatabase();
    contacts = buildWidgetContactRepository(receiverDb);
    requests = buildWidgetRequestRepository(receiverDb);
    repairs = SqlContactRepairRepository(receiverDb);
    crypto = Ed25519ContactRequestCryptoBus()
      ..register(receiver)
      ..register(sender)
      ..register(wrongSigner);
    receiverBridge = Ed25519ContactRequestBridge(crypto);
    senderBridge = Ed25519ContactRequestBridge(crypto);
    final network = FakeP2PNetwork();
    receiverTransport = FakeP2PService(
      peerId: receiver.peerId,
      network: network,
    );
    senderTransport = FakeP2PService(peerId: sender.peerId, network: network);
    prompts = [];
    listener = ContactRequestListener(
      // Capture the actual sender packet separately, then await the production
      // inbox entry point so transport ACK timing cannot stand in for handling.
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: requests,
      contactRepo: contacts,
      bridge: receiverBridge,
      getOwnPeerId: () => receiver.peerId,
      getOwnPrivateKey: () async => receiver.privateKey,
      getOwnPublicKey: () async => receiver.publicKey,
      getOwnAccountPeerId: () async => receiver.peerId,
      repairRepository: repairs,
      downloadProfilePictureFn: _settledAvatar,
    );
    promptSubscription = listener.requestStream.listen(prompts.add);
    // The attach replay has already queued its empty SQL read. Await a read on
    // that same database before sending; no timer guesses listener readiness.
    expect(await requests.getPendingRequests(), isEmpty);
  });

  tearDown(() async {
    await promptSubscription.cancel();
    listener.dispose();
    receiverTransport.dispose();
    senderTransport.dispose();
    await receiverDb.close();
    await senderDb.close();
  });

  Future<ContactRelationshipConsent> deleteFriend() async {
    // This is the existing local QR-add owner, followed by the real delete
    // use case and SQL-backed message/request/contact repositories.
    expect(
      await addContact(repository: contacts, contact: contactFor(sender)),
      AddContactResult.success,
    );
    await deleteContactAndMessages(
      contactRepo: contacts,
      messageRepo: _deletionMessageRepository(receiverDb),
      contactRequestRepo: requests,
      peerId: sender.peerId,
    );
    expect(await contacts.getContact(sender.peerId), isNull);
    expect(await requests.getPendingRequests(), isEmpty);
    final consent = (await repairs.readConsent(sender.peerId))!;
    expect(consent.state, ContactRelationshipState.withdrawn);
    return consent;
  }

  Future<ChatMessage> automaticRetry({
    required bool marked,
    int? signedAfterMs,
  }) async {
    // Exercise the actual missing-key retry owner, including its intent and
    // signed-marker choices. The remote still has us as a contact: our local
    // delete did not revoke that independent retry obligation.
    final senderContacts = buildWidgetContactRepository(senderDb);
    await senderContacts.addContact(contactFor(receiver));
    final senderIdentity = buildWidgetIdentityRepository(
      senderDb,
      FakeSecureKeyStore(),
    );
    await senderIdentity.saveIdentity(
      testIdentityModel(
        sender,
        username: 'Sender',
        mlKemPublicKey: 'sender-key',
      ),
    );
    if (signedAfterMs != null) {
      // Production send samples DateTime itself. Wait for that specific clock
      // boundary, rather than relying on SQL latency to advance a millisecond.
      // This is independent of listener completion and bounded if time regresses.
      final deadline = Stopwatch()..start();
      while (DateTime.now().toUtc().millisecondsSinceEpoch <= signedAfterMs) {
        if (deadline.elapsed > const Duration(seconds: 2)) {
          fail('Wall clock did not advance beyond the deletion cutoff');
        }
        await Future<void>(() {});
      }
    }
    final delivered = receiverTransport.messageStream.first.timeout(
      const Duration(seconds: 5),
    );
    expect(
      await retryIncompleteKeyExchanges(
        contactRepo: senderContacts,
        identityRepo: senderIdentity,
        p2pService: senderTransport,
        bridge: senderBridge,
        shouldMarkAsNewRequest: (_) async => marked,
      ),
      1,
    );
    final wire = await delivered;
    final envelope = jsonDecode(wire.content) as Map<String, dynamic>;
    expect(envelope['intent'], 'key_exchange_retry');
    final payload = senderBridge.encrypts.single.payload;
    if (marked) {
      expect((payload['cr'] as Map<String, dynamic>)['kind'], 'new_request');
    } else {
      expect(payload.containsKey('cr'), isFalse);
    }
    return wire;
  }

  Future<HandleMessageResult> deliver(ChatMessage wire) async {
    final result = await listener.processIncomingMessage(wire);
    // Processing includes prompt routing. The subsequent real SQL completion
    // also lets its already-enqueued asynchronous broadcast reach our listener.
    await requests.getPendingRequests();
    return result;
  }

  Future<void> expectNoPendingOrPrompt() async {
    expect(
      {
        'durable pending requests':
            (await requests.getPendingRequests()).length,
        'listener prompts': prompts.length,
      },
      {'durable pending requests': 0, 'listener prompts': 0},
    );
  }

  for (final marked in [false, true]) {
    test(
      'deleted friend fresh automatic ${marked ? 'signed new_request' : 'unmarked'} '
      'retry creates no pending request or prompt',
      () async {
        final withdrawn = await deleteFriend();
        final wire = await automaticRetry(
          marked: marked,
          signedAfterMs: withdrawn.updatedAtMs,
        );
        final signedTs = senderBridge.encrypts.single.payload['ts'] as String;
        expect(
          DateTime.parse(signedTs).millisecondsSinceEpoch,
          greaterThan(withdrawn.updatedAtMs),
          reason: 'Exercise fresh automatic traffic, not the existing cutoff.',
        );
        await deliver(wire);
        expect(receiverBridge.verifiedData, hasLength(1));
        expect(await contacts.getContact(sender.peerId), isNull);
        final after = (await repairs.readConsent(sender.peerId))!;
        expect(after.state, ContactRelationshipState.withdrawn);
        expect(after.revision, withdrawn.revision);
        expect(after.updatedAtMs, withdrawn.updatedAtMs);
        await expectNoPendingOrPrompt();
      },
    );
  }

  test('initial legitimate request still persists and prompts once', () async {
    final wire = await buildRepairWire(
      bus: crypto,
      signer: sender,
      recipientPublicKey: receiver.publicKey,
    );
    expect(await deliver(wire), HandleMessageResult.contactAutoAdded);
    expect(receiverBridge.verifiedData, hasLength(1));
    expect(prompts, hasLength(1));
    final pending = (await requests.getPendingRequests()).single;
    expect(pending.peerId, sender.peerId);
    expect(pending.signature, prompts.single.signature);
    expect(await contacts.getContact(sender.peerId), isNull);
  });

  test(
    'blocked contact automatic retry creates no pending or prompt',
    () async {
      await contacts.addContact(contactFor(sender).copyWith(isBlocked: true));
      final wire = await automaticRetry(marked: true);
      expect(await deliver(wire), HandleMessageResult.alreadyContact);
      expect(receiverBridge.verifiedData, hasLength(1));
      expect((await contacts.getContact(sender.peerId))!.isBlocked, isTrue);
      await expectNoPendingOrPrompt();
    },
  );

  test('invalid signature creates no pending request or prompt', () async {
    final wire = await buildRepairWire(
      bus: crypto,
      signer: wrongSigner,
      claimedPeerId: sender.peerId,
      claimedPublicKey: sender.publicKey,
      recipientPublicKey: receiver.publicKey,
    );
    expect(await deliver(wire), HandleMessageResult.invalidMessage);
    expect(receiverBridge.verifyCalls, 1);
    expect(receiverBridge.verifiedData, isEmpty);
    await expectNoPendingOrPrompt();
  });

  test('signed request before deletion cutoff stays suppressed', () async {
    final withdrawn = await deleteFriend();
    final ts = DateTime.fromMillisecondsSinceEpoch(
      withdrawn.updatedAtMs - 1,
      isUtc: true,
    ).toIso8601String();
    final wire = await buildRepairWire(
      bus: crypto,
      signer: sender,
      recipientPublicKey: receiver.publicKey,
      ts: ts,
      outerTs: ts,
    );
    expect(await deliver(wire), HandleMessageResult.invalidMessage);
    expect(receiverBridge.verifiedData, hasLength(1));
    await expectNoPendingOrPrompt();
  });

  test(
    'explicit local re-add still permits automatic key completion',
    () async {
      final withdrawn = await deleteFriend();
      expect(
        await addContact(repository: contacts, contact: contactFor(sender)),
        AddContactResult.success,
      );
      final active = (await repairs.readConsent(sender.peerId))!;
      expect(active.state, ContactRelationshipState.active);
      expect(active.revision, greaterThan(withdrawn.revision));
      final wire = await automaticRetry(marked: false);
      expect(await deliver(wire), HandleMessageResult.contactKeyUpdated);
      expect(receiverBridge.verifiedData, hasLength(1));
      expect(
        (await contacts.getContact(sender.peerId))!.mlKemPublicKey,
        'sender-key',
      );
      await expectNoPendingOrPrompt();
    },
  );
}
