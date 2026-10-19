import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introduction_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introductions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_introduction_responses_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/introduction/application/accept_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/handle_incoming_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/application/send_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/data/repositories/introduction_repository_impl.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/introduction/domain/models/pending_introduction_response.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';

Future<Database> _openAccountDb() {
  sqfliteFfiInit();
  return databaseFactoryFfiNoIsolate.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: currentIdentityDatabaseVersion,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    ),
  );
}

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

IntroductionRepositoryImpl _buildIntroRepo(Database db) =>
    IntroductionRepositoryImpl(
      dbInsertIntroduction: (row) => dbInsertIntroduction(db, row),
      dbLoadIntroduction: (id) => dbLoadIntroduction(db, id),
      dbDeleteIntroduction: (id) => dbDeleteIntroduction(db, id),
      dbLoadIntroductionsByRecipient: (id) =>
          dbLoadIntroductionsByRecipient(db, id),
      dbLoadIntroductionsByIntroduced: (id) =>
          dbLoadIntroductionsByIntroduced(db, id),
      dbLoadIntroductionsByIntroducer: (id) =>
          dbLoadIntroductionsByIntroducer(db, id),
      dbLoadIntroductionsForRecipientAndIntroducer: (recipient, introducer) =>
          dbLoadIntroductionsForRecipientAndIntroducer(
            db,
            recipient,
            introducer,
          ),
      dbUpdateRecipientStatus: (id, status, respondedAt) =>
          dbUpdateRecipientStatus(db, id, status, respondedAt),
      dbUpdateIntroducedStatus: (id, status, respondedAt) =>
          dbUpdateIntroducedStatus(db, id, status, respondedAt),
      dbUpdateOverallStatus: (id, status) =>
          dbUpdateOverallStatus(db, id, status),
      dbLoadPendingIntroductionsForUser: (peerId) =>
          dbLoadPendingIntroductionsForUser(db, peerId),
      dbCountPendingIntroductions: (peerId) =>
          dbCountPendingIntroductions(db, peerId),
      dbUpsertPendingIntroductionResponse: (row) =>
          dbUpsertPendingIntroductionResponse(db, row),
      dbLoadPendingIntroductionResponses: (id) =>
          dbLoadPendingIntroductionResponses(db, id),
      dbDeletePendingIntroductionResponse: (key) =>
          dbDeletePendingIntroductionResponse(db, key),
      dbUpsertIntroductionOutboxDelivery: (row) =>
          dbUpsertIntroductionOutboxDelivery(db, row),
      dbSaveIntroductionWithOutboxDeliveries: (intro, deliveries) =>
          dbSaveIntroductionWithOutboxDeliveries(db, intro, deliveries),
      dbReplaceIntroductionWithPendingResponseMigration:
          ({
            required introductionRow,
            required deliveryRows,
            required replacedIntroductionIds,
          }) => dbReplaceIntroductionWithPendingResponseMigration(
            db,
            introductionRow: introductionRow,
            deliveryRows: deliveryRows,
            replacedIntroductionIds: replacedIntroductionIds,
          ),
      dbSaveIntroductionResponseWithOutboxDeliveries:
          ({
            required introductionId,
            required isRecipient,
            required responseStatus,
            required respondedAt,
            required overallStatus,
            required deliveryRows,
          }) => dbSaveIntroductionResponseWithOutboxDeliveries(
            db,
            introductionId: introductionId,
            isRecipient: isRecipient,
            responseStatus: responseStatus,
            respondedAt: respondedAt,
            overallStatus: overallStatus,
            deliveryRows: deliveryRows,
          ),
      dbLoadIntroductionOutboxDeliveriesForIntroduction: (id) =>
          dbLoadIntroductionOutboxDeliveriesForIntroduction(db, id),
      dbLoadRetryableIntroductionOutboxDeliveries:
          ({required olderThan, limit = 100}) =>
              dbLoadRetryableIntroductionOutboxDeliveries(
                db,
                olderThan: olderThan,
                limit: limit,
              ),
      dbDeleteIntroductionOutboxDelivery: (id) =>
          dbDeleteIntroductionOutboxDelivery(db, id),
      dbDeleteIntroductionOutboxDeliveriesForIntroduction: (id) =>
          dbDeleteIntroductionOutboxDeliveriesForIntroduction(db, id),
    );

MessageRepositoryImpl _buildMessageRepo(Database db) => MessageRepositoryImpl(
  dbInsertMessage: (row) => dbInsertMessage(db, row),
  dbLoadMessagesForContact: (peerId) => dbLoadMessagesForContact(db, peerId),
  dbLoadLatestMessageForContact: (peerId) =>
      dbLoadLatestMessageForContact(db, peerId),
  dbUpdateMessageStatus: (id, status) => dbUpdateMessageStatus(db, id, status),
  dbLoadMessage: (id) => dbLoadMessage(db, id),
  dbMarkIncomingQuietRecovery: (expected) =>
      dbMarkIncomingQuietRecovery(db, expected.toMap()),
  dbCountMessagesForContact: (peerId) => dbCountMessagesForContact(db, peerId),
  dbMarkConversationAsRead: (peerId) => dbMarkConversationAsRead(db, peerId),
  dbCountUnreadForContact: (peerId) => dbCountUnreadForContact(db, peerId),
  dbCountTotalUnread: () => dbCountTotalUnread(db),
  dbCountTotalUnreadExcludingArchived: () =>
      dbCountTotalUnreadExcludingArchived(db),
  dbDeleteMessagesForContact: (peerId) =>
      dbDeleteMessagesForContact(db, peerId),
  dbDeleteMessage: (id) => dbDeleteMessage(db, id),
  dbExistsMessageByContent: (peerId, senderPeerId, text, timestamp) =>
      dbExistsMessageByContent(db, peerId, senderPeerId, text, timestamp),
  dbExistsMessageByDedupKey: (peerId, senderPeerId, dedupKey) =>
      dbExistsMessageByDedupKey(db, peerId, senderPeerId, dedupKey),
  dbLoadMessagesPage: (peerId, {limit = 50, beforeTimestamp}) =>
      dbLoadMessagesPage(
        db,
        peerId,
        limit: limit,
        beforeTimestamp: beforeTimestamp,
      ),
  dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(db),
  dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) =>
      dbLoadUnackedOutgoingMessages(db, olderThan: olderThan, limit: limit),
  dbLoadConversationThreadSummaries: (peerIds) =>
      dbLoadConversationThreadSummaries(db, peerIds),
  dbRecoverStuckSendingMessages:
      ({required DateTime olderThan, int limit = 50}) =>
          dbRecoverStuckSendingMessages(db, olderThan: olderThan, limit: limit),
  dbLoadStuckSendingOutgoingMessages:
      ({required DateTime olderThan, int limit = 50}) =>
          dbLoadStuckSendingOutgoingMessages(
            db,
            olderThan: olderThan,
            limit: limit,
          ),
  dbLoadSendingOutgoingMessages: () => dbLoadSendingOutgoingMessages(db),
  dbConditionalTransitionStatus:
      (id, {required fromStatus, required toStatus}) =>
          dbConditionalTransitionStatus(
            db,
            id,
            fromStatus: fromStatus,
            toStatus: toStatus,
          ),
);

final class _SqlIntroNode {
  final String peerId;
  final String username;
  final String publicKey;
  final String mlKemPublicKey;
  final Database db;
  final ContactRepositoryImpl contactRepo;
  final IntroductionRepositoryImpl introRepo;
  final MessageRepositoryImpl messageRepo;
  final FakeP2PService p2pService;
  final IncomingMessageRouter router;
  final IntroductionListener listener;
  final Bridge bridge;

  _SqlIntroNode._({
    required this.peerId,
    required this.username,
    required this.publicKey,
    required this.mlKemPublicKey,
    required this.db,
    required this.contactRepo,
    required this.introRepo,
    required this.messageRepo,
    required this.p2pService,
    required this.router,
    required this.listener,
    required this.bridge,
  });

  static Future<_SqlIntroNode> create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
  }) async {
    final db = await _openAccountDb();
    final contactRepo = _buildContactRepo(db);
    final introRepo = _buildIntroRepo(db);
    final messageRepo = _buildMessageRepo(db);
    final bridge = PassthroughCryptoBridge();
    final p2p = FakeP2PService(peerId: peerId, network: network);
    final router = IncomingMessageRouter(p2pService: p2p);
    final listener = IntroductionListener(
      introductionStream: router.introductionStream,
      introRepo: introRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => 'mlkem-sk-$peerId',
      getOwnPeerId: () async => peerId,
      messageRepo: messageRepo,
    );
    router.start();
    listener.start();
    return _SqlIntroNode._(
      peerId: peerId,
      username: username,
      publicKey: 'ed25519-pk-$peerId',
      mlKemPublicKey: 'mlkem-pk-$peerId',
      db: db,
      contactRepo: contactRepo,
      introRepo: introRepo,
      messageRepo: messageRepo,
      p2pService: p2p,
      router: router,
      listener: listener,
      bridge: bridge,
    );
  }

  Future<void> seedContact(
    _SqlIntroNode other, {
    String? publicKeyOverride,
    String? mlKemOverride,
    bool isBlocked = false,
  }) async {
    await contactRepo.addContact(
      ContactModel(
        peerId: other.peerId,
        publicKey: publicKeyOverride ?? other.publicKey,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: other.username,
        signature: 'sig-${other.peerId}',
        scannedAt: '2026-01-01T00:00:00.000Z',
        mlKemPublicKey: mlKemOverride ?? other.mlKemPublicKey,
      ),
    );
    if (isBlocked) {
      await contactRepo.blockContact(other.peerId);
    }
  }

  Future<void> dispose() async {
    listener.dispose();
    router.dispose();
    p2pService.dispose();
    await db.close();
  }
}

String _encodeV2IntroEnvelope({
  required String messageId,
  required String senderPeerId,
  required IntroductionPayload payload,
}) {
  return IntroductionPayload.buildEncryptedEnvelope(
    introductionId: payload.introductionId,
    messageId: messageId,
    senderPeerId: senderPeerId,
    kem: 'passthrough-kem',
    ciphertext: payload.toInnerJson(),
    nonce: 'passthrough-nonce',
  );
}

void main() {
  late FakeP2PNetwork network;
  late _SqlIntroNode nodeA;
  late _SqlIntroNode nodeB;
  late _SqlIntroNode nodeC;
  late _SqlIntroNode nodeD;

  setUp(() async {
    network = FakeP2PNetwork();
    nodeA = await _SqlIntroNode.create(
      peerId: 'peer-A-introducer',
      username: 'Noor',
      network: network,
    );
    nodeB = await _SqlIntroNode.create(
      peerId: 'peer-B-recipient',
      username: 'Lina',
      network: network,
    );
    nodeC = await _SqlIntroNode.create(
      peerId: 'peer-C-introduced',
      username: 'Sarah',
      network: network,
    );
    nodeD = await _SqlIntroNode.create(
      peerId: 'peer-D-outsider',
      username: 'Dana',
      network: network,
    );

    await nodeA.seedContact(nodeB);
    await nodeA.seedContact(nodeC);
    await nodeA.seedContact(nodeD);
    await nodeB.seedContact(nodeA);
    await nodeC.seedContact(nodeA);
    await nodeD.seedContact(nodeA);
  });

  tearDown(() async {
    await nodeA.dispose();
    await nodeB.dispose();
    await nodeC.dispose();
    await nodeD.dispose();
  });

  group('IN-006 fake introductions are rejected', () {
    test(
      'wrong-recipient offer and mismatched-sender offer or response are rejected without creating introductions or contacts',
      () async {
        // 1. Wrong-recipient offer: addressed to B and C, delivered to D.
        final wrongRecipientPayload = IntroductionPayload(
          action: 'send',
          introductionId: 'intro-wrong-recipient',
          introducerId: nodeA.peerId,
          introducerUsername: nodeA.username,
          recipientId: nodeB.peerId,
          recipientUsername: nodeB.username,
          recipientPublicKey: nodeB.publicKey,
          recipientMlKemPublicKey: nodeB.mlKemPublicKey,
          introducedId: nodeC.peerId,
          introducedUsername: nodeC.username,
          introducedPublicKey: nodeC.publicKey,
          introducedMlKemPublicKey: nodeC.mlKemPublicKey,
          timestamp: '2026-10-19T12:00:00.000Z',
        );
        final wrongRecipientOutcome = await nodeD.listener
            .processIncomingMessage(
              ChatMessage(
                from: nodeA.peerId,
                to: nodeD.peerId,
                content: _encodeV2IntroEnvelope(
                  messageId: 'intro-wrong-recipient',
                  senderPeerId: nodeA.peerId,
                  payload: wrongRecipientPayload,
                ),
                timestamp: '2026-10-19T12:00:00.000Z',
                isIncoming: true,
              ),
            );
        expect(
          wrongRecipientOutcome.state,
          IntroductionMessageProcessState.rejected,
        );
        expect(wrongRecipientOutcome.reasonCode, 'handler_rejected');
        expect(
          await nodeD.introRepo.getIntroduction('intro-wrong-recipient'),
          isNull,
        );
        expect(await nodeD.db.query('introductions'), isEmpty);
        expect(
          (await nodeD.contactRepo.getAllContacts())
              .map((c) => c.peerId)
              .toList(),
          <String>[nodeA.peerId],
        );

        // 2. Mismatched transport sender on offer: D claims to be introducer A.
        final spoofedOfferPayload = IntroductionPayload(
          action: 'send',
          introductionId: 'intro-spoofed-sender',
          introducerId: nodeA.peerId,
          introducerUsername: nodeA.username,
          recipientId: nodeB.peerId,
          recipientUsername: nodeB.username,
          recipientPublicKey: nodeB.publicKey,
          recipientMlKemPublicKey: nodeB.mlKemPublicKey,
          introducedId: nodeC.peerId,
          introducedUsername: nodeC.username,
          introducedPublicKey: nodeC.publicKey,
          introducedMlKemPublicKey: nodeC.mlKemPublicKey,
          timestamp: '2026-10-19T12:01:00.000Z',
        );
        final spoofedOuterOutcome = await nodeB.listener.processIncomingMessage(
          ChatMessage(
            from: nodeD.peerId,
            to: nodeB.peerId,
            content: _encodeV2IntroEnvelope(
              messageId: 'intro-spoofed-sender',
              senderPeerId: nodeD.peerId,
              payload: spoofedOfferPayload,
            ),
            timestamp: '2026-10-19T12:01:00.000Z',
            isIncoming: true,
          ),
        );
        expect(
          spoofedOuterOutcome.state,
          IntroductionMessageProcessState.rejected,
        );
        expect(spoofedOuterOutcome.reasonCode, 'transport_sender_mismatch');
        expect(
          await nodeB.introRepo.getIntroduction('intro-spoofed-sender'),
          isNull,
        );

        // 3. Legitimate offer from A to B and C succeeds, then forged responses
        // from D (impersonating C or acting as non-party D) are rejected.
        final friendC = (await nodeA.contactRepo.getContact(nodeC.peerId))!;
        final bOfferReceived = nodeB.listener.introReceivedStream.first;
        final cOfferReceived = nodeC.listener.introReceivedStream.first;
        final sentIntros = await sendIntroductions(
          contactRepo: nodeA.contactRepo,
          introRepo: nodeA.introRepo,
          p2pService: nodeA.p2pService,
          bridge: nodeA.bridge,
          introducerPeerId: nodeA.peerId,
          introducerUsername: nodeA.username,
          recipientPeerId: nodeB.peerId,
          recipientUsername: nodeB.username,
          recipientMlKemPublicKey: nodeB.mlKemPublicKey,
          friendsToIntroduce: <ContactModel>[friendC],
        );
        expect(sentIntros, hasLength(1));
        final validIntroId = sentIntros.single.id;
        await Future.wait(<Future<Object?>>[bOfferReceived, cOfferReceived]);

        final bStoredIntro = await nodeB.introRepo.getIntroduction(
          validIntroId,
        );
        expect(bStoredIntro, isNotNull);
        expect(bStoredIntro!.status, IntroductionOverallStatus.pending);

        // B accepts legitimately -> B's side is accepted, waiting on C.
        final bAccepted = await acceptIntroduction(
          introRepo: nodeB.introRepo,
          contactRepo: nodeB.contactRepo,
          p2pService: nodeB.p2pService,
          bridge: nodeB.bridge,
          introductionId: validIntroId,
          ownPeerId: nodeB.peerId,
          ownUsername: nodeB.username,
          messageRepo: nodeB.messageRepo,
        );
        expect(bAccepted?.recipientStatus, IntroductionStatus.accepted);
        expect(bAccepted?.introducedStatus, IntroductionStatus.pending);
        expect(bAccepted?.status, IntroductionOverallStatus.pending);

        // D attempts to forge C's accept response so B creates a contact for C
        // without C's consent.
        final forgedAcceptFromD = IntroductionPayload(
          action: 'accept',
          introductionId: validIntroId,
          responderId: nodeC.peerId,
          responderUsername: nodeC.username,
          timestamp: '2026-10-19T12:02:00.000Z',
        );
        final forgedAcceptOutcome = await nodeB.listener.processIncomingMessage(
          ChatMessage(
            from: nodeD.peerId,
            to: nodeB.peerId,
            content: _encodeV2IntroEnvelope(
              messageId: '$validIntroId:accept:${nodeC.peerId}',
              senderPeerId: nodeD.peerId,
              payload: forgedAcceptFromD,
            ),
            timestamp: '2026-10-19T12:02:00.000Z',
            isIncoming: true,
          ),
        );
        expect(
          forgedAcceptOutcome.state,
          IntroductionMessageProcessState.rejected,
        );
        expect(forgedAcceptOutcome.reasonCode, 'transport_sender_mismatch');

        // D also attempts to send an accept as responder D (non-party).
        final nonPartyAccept = IntroductionPayload(
          action: 'accept',
          introductionId: validIntroId,
          responderId: nodeD.peerId,
          responderUsername: nodeD.username,
          timestamp: '2026-10-19T12:02:30.000Z',
        );
        final nonPartyOutcome = await nodeB.listener.processIncomingMessage(
          ChatMessage(
            from: nodeD.peerId,
            to: nodeB.peerId,
            content: _encodeV2IntroEnvelope(
              messageId: '$validIntroId:accept:${nodeD.peerId}',
              senderPeerId: nodeD.peerId,
              payload: nonPartyAccept,
            ),
            timestamp: '2026-10-19T12:02:30.000Z',
            isIncoming: true,
          ),
        );
        expect(nonPartyOutcome.state, IntroductionMessageProcessState.rejected);
        expect(nonPartyOutcome.reasonCode, 'handler_rejected');

        final bAfterForgeries = await nodeB.introRepo.getIntroduction(
          validIntroId,
        );
        expect(bAfterForgeries!.status, IntroductionOverallStatus.pending);
        expect(bAfterForgeries.introducedStatus, IntroductionStatus.pending);
        expect(await nodeB.contactRepo.getContact(nodeC.peerId), isNull);
      },
    );

    test(
      'conflicting key authority blocks acceptance and preserves existing trusted contact keys',
      () async {
        // B already has a trusted contact for C with pinned keys.
        await nodeB.seedContact(
          nodeC,
          publicKeyOverride: 'trusted-ed25519-pk-C',
          mlKemOverride: 'trusted-mlkem-pk-C',
        );

        // Seed a pending introduction on B that carries a conflicting ML-KEM
        // key for C (simulating an offer that arrived before C was pinned or
        // with mismatched key authority).
        const conflictingIntroId = 'intro-key-conflict';
        await nodeB.introRepo.saveIntroduction(
          IntroductionModel(
            id: conflictingIntroId,
            introducerId: nodeA.peerId,
            recipientId: nodeB.peerId,
            introducedId: nodeC.peerId,
            createdAt: '2026-10-19T12:05:00.000Z',
            introducerUsername: nodeA.username,
            recipientUsername: nodeB.username,
            introducedUsername: nodeC.username,
            recipientPublicKey: nodeB.publicKey,
            recipientMlKemPublicKey: nodeB.mlKemPublicKey,
            introducedPublicKey: 'untrusted-ed25519-pk-C',
            introducedMlKemPublicKey: 'untrusted-mlkem-pk-C',
          ),
        );

        network.resetCounters();
        final acceptResult = await acceptIntroduction(
          introRepo: nodeB.introRepo,
          contactRepo: nodeB.contactRepo,
          p2pService: nodeB.p2pService,
          bridge: nodeB.bridge,
          introductionId: conflictingIntroId,
          ownPeerId: nodeB.peerId,
          ownUsername: nodeB.username,
          messageRepo: nodeB.messageRepo,
        );

        expect(acceptResult, isNull);
        final storedIntro = await nodeB.introRepo.getIntroduction(
          conflictingIntroId,
        );
        expect(storedIntro!.recipientStatus, IntroductionStatus.pending);
        expect(storedIntro.status, IntroductionOverallStatus.pending);
        expect(
          await nodeB.introRepo.loadOutboxDeliveriesForIntroduction(
            conflictingIntroId,
          ),
          isEmpty,
        );
        expect(network.deliverCallCount, 0);

        // Even if C's accept arrives, B's trusted contact keys for C are never
        // overwritten.
        await handleIncomingIntroduction(
          payload: IntroductionPayload(
            action: 'accept',
            introductionId: conflictingIntroId,
            responderId: nodeC.peerId,
            responderUsername: nodeC.username,
            timestamp: '2026-10-19T12:06:00.000Z',
          ),
          introRepo: nodeB.introRepo,
          contactRepo: nodeB.contactRepo,
          ownPeerId: nodeB.peerId,
          transportSenderPeerId: nodeC.peerId,
          messageRepo: nodeB.messageRepo,
          bridge: nodeB.bridge,
        );

        final trustedContactC = await nodeB.contactRepo.getContact(
          nodeC.peerId,
        );
        expect(trustedContactC, isNotNull);
        expect(trustedContactC!.publicKey, 'trusted-ed25519-pk-C');
        expect(trustedContactC.mlKemPublicKey, 'trusted-mlkem-pk-C');
      },
    );

    test(
      'blocked senders cannot create new offers while existing responses still reconcile and forged deferred responses are dropped',
      () async {
        // 1. Legitimate offer intro-1 arrives on B before A is blocked, and B
        // accepts it.
        final friendC = (await nodeA.contactRepo.getContact(nodeC.peerId))!;
        final bOfferReceived = nodeB.listener.introReceivedStream.first;
        final cOfferReceived = nodeC.listener.introReceivedStream.first;
        final sentIntros = await sendIntroductions(
          contactRepo: nodeA.contactRepo,
          introRepo: nodeA.introRepo,
          p2pService: nodeA.p2pService,
          bridge: nodeA.bridge,
          introducerPeerId: nodeA.peerId,
          introducerUsername: nodeA.username,
          recipientPeerId: nodeB.peerId,
          recipientUsername: nodeB.username,
          recipientMlKemPublicKey: nodeB.mlKemPublicKey,
          friendsToIntroduce: <ContactModel>[friendC],
        );
        final existingIntroId = sentIntros.single.id;
        await Future.wait(<Future<Object?>>[bOfferReceived, cOfferReceived]);

        await acceptIntroduction(
          introRepo: nodeB.introRepo,
          contactRepo: nodeB.contactRepo,
          p2pService: nodeB.p2pService,
          bridge: nodeB.bridge,
          introductionId: existingIntroId,
          ownPeerId: nodeB.peerId,
          ownUsername: nodeB.username,
          messageRepo: nodeB.messageRepo,
        );

        // 2. B blocks A. A new offer from blocked A is rejected with
        // blockedSender and does not persist in SQL.
        await nodeB.contactRepo.blockContact(nodeA.peerId);
        final blockedOfferPayload = IntroductionPayload(
          action: 'send',
          introductionId: 'intro-from-blocked-A',
          introducerId: nodeA.peerId,
          introducerUsername: nodeA.username,
          recipientId: nodeB.peerId,
          recipientUsername: nodeB.username,
          recipientPublicKey: nodeB.publicKey,
          recipientMlKemPublicKey: nodeB.mlKemPublicKey,
          introducedId: nodeD.peerId,
          introducedUsername: nodeD.username,
          introducedPublicKey: nodeD.publicKey,
          introducedMlKemPublicKey: nodeD.mlKemPublicKey,
          timestamp: '2026-10-19T12:10:00.000Z',
        );
        final blockedOutcome = await nodeB.listener.processIncomingMessage(
          ChatMessage(
            from: nodeA.peerId,
            to: nodeB.peerId,
            content: _encodeV2IntroEnvelope(
              messageId: 'intro-from-blocked-A',
              senderPeerId: nodeA.peerId,
              payload: blockedOfferPayload,
            ),
            timestamp: '2026-10-19T12:10:00.000Z',
            isIncoming: true,
          ),
        );
        expect(
          blockedOutcome.state,
          IntroductionMessageProcessState.blockedSender,
        );
        expect(blockedOutcome.reasonCode, 'blocked_sender');
        expect(
          await nodeB.introRepo.getIntroduction('intro-from-blocked-A'),
          isNull,
        );

        // 3. Even when A has C blocked, C's response on the existing offer
        // still reconciles on both A (blocked responder) and B (blocked
        // introducer).
        await nodeA.contactRepo.blockContact(nodeC.peerId);
        final cAcceptPayload = IntroductionPayload(
          action: 'accept',
          introductionId: existingIntroId,
          responderId: nodeC.peerId,
          responderUsername: nodeC.username,
          timestamp: '2026-10-19T12:11:00.000Z',
        );
        final aBlockedResponderReconcile = await nodeA.listener
            .processIncomingMessage(
              ChatMessage(
                from: nodeC.peerId,
                to: nodeA.peerId,
                content: _encodeV2IntroEnvelope(
                  messageId: '$existingIntroId:accept:${nodeC.peerId}',
                  senderPeerId: nodeC.peerId,
                  payload: cAcceptPayload,
                ),
                timestamp: '2026-10-19T12:11:00.000Z',
                isIncoming: true,
              ),
            );
        expect(
          aBlockedResponderReconcile.state,
          IntroductionMessageProcessState.stored,
        );
        expect(
          (await nodeA.introRepo.getIntroduction(existingIntroId))
              ?.introducedStatus,
          IntroductionStatus.accepted,
        );
        await nodeA.contactRepo.unblockContact(nodeC.peerId);

        final reconcileOutcome = await nodeB.listener.processIncomingMessage(
          ChatMessage(
            from: nodeC.peerId,
            to: nodeB.peerId,
            content: _encodeV2IntroEnvelope(
              messageId: '$existingIntroId:accept:${nodeC.peerId}',
              senderPeerId: nodeC.peerId,
              payload: cAcceptPayload,
            ),
            timestamp: '2026-10-19T12:11:00.000Z',
            isIncoming: true,
          ),
        );
        expect(reconcileOutcome.state, IntroductionMessageProcessState.stored);
        final settledIntro = await nodeB.introRepo.getIntroduction(
          existingIntroId,
        );
        expect(settledIntro!.status, IntroductionOverallStatus.mutualAccepted);
        final createdContactC = await nodeB.contactRepo.getContact(
          nodeC.peerId,
        );
        expect(createdContactC, isNotNull);
        expect(createdContactC!.publicKey, nodeC.publicKey);
        expect(createdContactC.mlKemPublicKey, nodeC.mlKemPublicKey);

        // 4. Deferred response with mismatched transportSenderPeerId is purged
        // without applying when the matching offer arrives.
        await nodeB.contactRepo.unblockContact(nodeA.peerId);
        const deferredIntroId = 'intro-deferred-spoof';
        await nodeB.introRepo.savePendingResponse(
          PendingIntroductionResponse.fromPayload(
            IntroductionPayload(
              action: 'accept',
              introductionId: deferredIntroId,
              responderId: nodeD.peerId,
              responderUsername: nodeD.username,
              timestamp: '2026-10-19T12:12:00.000Z',
            ),
            transportSenderPeerId: nodeC.peerId,
          ),
        );
        final offerAfterSpoofedDeferred = IntroductionPayload(
          action: 'send',
          introductionId: deferredIntroId,
          introducerId: nodeA.peerId,
          introducerUsername: nodeA.username,
          recipientId: nodeB.peerId,
          recipientUsername: nodeB.username,
          recipientPublicKey: nodeB.publicKey,
          recipientMlKemPublicKey: nodeB.mlKemPublicKey,
          introducedId: nodeD.peerId,
          introducedUsername: nodeD.username,
          introducedPublicKey: nodeD.publicKey,
          introducedMlKemPublicKey: nodeD.mlKemPublicKey,
          timestamp: '2026-10-19T12:13:00.000Z',
        );
        final deferredOfferOutcome = await nodeB.listener
            .processIncomingMessage(
              ChatMessage(
                from: nodeA.peerId,
                to: nodeB.peerId,
                content: _encodeV2IntroEnvelope(
                  messageId: deferredIntroId,
                  senderPeerId: nodeA.peerId,
                  payload: offerAfterSpoofedDeferred,
                ),
                timestamp: '2026-10-19T12:13:00.000Z',
                isIncoming: true,
              ),
            );
        expect(
          deferredOfferOutcome.state,
          IntroductionMessageProcessState.stored,
        );
        final afterDeferredReplay = await nodeB.introRepo.getIntroduction(
          deferredIntroId,
        );
        expect(afterDeferredReplay!.introducedStatus, IntroductionStatus.pending);
        expect(afterDeferredReplay.status, IntroductionOverallStatus.pending);
        expect(
          await nodeB.introRepo.loadPendingResponses(deferredIntroId),
          isEmpty,
        );
        expect(await nodeB.contactRepo.getContact(nodeD.peerId), isNull);
      },
    );
  });
}
