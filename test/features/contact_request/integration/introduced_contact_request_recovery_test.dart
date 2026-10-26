import 'dart:async';

import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/handle_incoming_message_use_case.dart';
import 'package:flutter_app/features/contact_request/application/recover_intro_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/data/repositories/sql_contact_repair_repository.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/introduction/application/accept_introduction_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/core/database/helpers/introduction_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introductions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_introduction_responses_db_helpers.dart';
import 'package:flutter_app/features/introduction/data/repositories/introduction_repository_impl.dart';
import 'package:flutter_app/features/introduction/application/handle_incoming_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';

Future<Database> _openDb() {
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
  dbApplyIncomingOrdinaryTextMutationWithAuthority:
      ({
        required incomingRow,
        required kind,
        required authenticatedTransportPeerId,
      }) => dbApplyIncomingOrdinaryTextMutation(
        db,
        incomingRow: incomingRow,
        kind: kind,
        authenticatedTransportPeerId: authenticatedTransportPeerId,
      ),
  dbApplyIncomingDirectMessageDeletionWithAuthority:
      ({
        required messageId,
        required senderPeerId,
        required deletedAt,
        required transport,
        required createdAt,
        required authenticatedTransportPeerId,
      }) => dbApplyIncomingDirectMessageDeletion(
        db,
        messageId: messageId,
        senderPeerId: senderPeerId,
        deletedAt: deletedAt,
        transport: transport,
        createdAt: createdAt,
        authenticatedTransportPeerId: authenticatedTransportPeerId,
      ),
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
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('CR-024 verified request completes an accepted introduction', () {
    for (final scenario in [
      'recipient',
      'introduced',
      'one qualifying same introducer',
      'declined',
      'deleted',
      'two qualifying',
      'two introducers',
    ]) {
      test(scenario, () async {
        final db = await _openDb();
        addTearDown(db.close);
        final senderDb = await _openDb();
        addTearDown(senderDb.close);
        final owner = TestEd25519Identity.fromSeedByte(0x76);
        final sender = TestEd25519Identity.fromSeedByte(0x77);
        final introducer = TestEd25519Identity.fromSeedByte(0x78);
        final ownerIdentities = _buildIdentityRepo(db, FakeSecureKeyStore());
        final senderIdentities = _buildIdentityRepo(
          senderDb,
          FakeSecureKeyStore(),
        );
        await ownerIdentities.saveIdentity(
          testIdentityModel(
            owner,
            username: 'Owner',
            mlKemPublicKey: 'owner-mlkem',
          ),
        );
        await senderIdentities.saveIdentity(
          testIdentityModel(
            sender,
            username: 'Sender',
            mlKemPublicKey: 'sender-mlkem',
          ),
        );
        final ownerIdentity = (await ownerIdentities.loadIdentity())!;
        final contacts = _buildContactRepo(db);
        final messages = _buildMessageRepo(db);
        final intros = _buildIntroRepo(db);
        final initialPendingRead = Completer<void>();
        final requests = ContactRequestRepositoryImpl(
          dbLoadPendingRequests: () async {
            final rows = await dbLoadPendingRequests(db);
            if (!initialPendingRead.isCompleted) initialPendingRead.complete();
            return rows;
          },
          dbLoadRequest: (id) => dbLoadRequest(db, id),
          dbUpsertRequest: (row) => dbUpsertRequest(db, row),
          dbUpdateRequestStatus: (id, status) =>
              dbUpdateRequestStatus(db, id, status),
          dbDeleteRequest: (id) => dbDeleteRequest(db, id),
          dbDecideRequest: (expected, accept, existingOnly, before) =>
              dbDecideContactRequest(
                db,
                expected,
                accept,
                existingOnly,
                before,
              ),
          dbRequestExists: (id) => dbRequestExists(db, id),
        );
        final network = FakeP2PNetwork();
        final ownerP2p = FakeP2PService(peerId: owner.peerId, network: network);
        addTearDown(ownerP2p.dispose);
        final senderP2p = FakeP2PService(
          peerId: sender.peerId,
          network: network,
        );
        addTearDown(senderP2p.dispose);
        final crypto = Ed25519ContactRequestCryptoBus()
          ..register(owner)
          ..register(sender);
        final receiveBridge = Ed25519ContactRequestBridge(crypto);
        addTearDown(receiveBridge.dispose);
        final sendBridge = Ed25519ContactRequestBridge(crypto);
        addTearDown(sendBridge.dispose);
        final introBridge = PassthroughCryptoBridge();
        addTearDown(introBridge.dispose);
        await contacts.addContact(
          ContactModel(
            peerId: introducer.peerId,
            publicKey: introducer.publicKey,
            rendezvous: 'introducer-rendezvous',
            username: 'Introducer',
            signature: 'introducer-signature',
            mlKemPublicKey: 'introducer-mlkem',
            scannedAt: '2026-01-01T00:00:00.000Z',
          ),
        );
        final ownIsRecipient = scenario != 'introduced';
        final now = DateTime.now().toUtc().toIso8601String();
        final offered = await handleIncomingIntroduction(
          payload: IntroductionPayload(
            action: 'send',
            introductionId: 'recovery-intro',
            introducerId: introducer.peerId,
            introducerUsername: 'Introducer',
            recipientId: ownIsRecipient ? owner.peerId : sender.peerId,
            recipientUsername: ownIsRecipient ? 'Owner' : 'Sender',
            introducedId: ownIsRecipient ? sender.peerId : owner.peerId,
            introducedUsername: ownIsRecipient ? 'Sender' : 'Owner',
            recipientPublicKey: ownIsRecipient
                ? owner.publicKey
                : sender.publicKey,
            recipientMlKemPublicKey: ownIsRecipient
                ? 'owner-mlkem'
                : 'sender-mlkem',
            introducedPublicKey: ownIsRecipient
                ? sender.publicKey
                : owner.publicKey,
            introducedMlKemPublicKey: ownIsRecipient
                ? 'sender-mlkem'
                : 'owner-mlkem',
            timestamp: now,
          ),
          introRepo: intros,
          contactRepo: contacts,
          ownPeerId: owner.peerId,
          transportSenderPeerId: introducer.peerId,
        );
        expect(offered.$1, HandleIntroductionResult.success);
        final accepted = await acceptIntroduction(
          introRepo: intros,
          contactRepo: contacts,
          p2pService: ownerP2p,
          bridge: introBridge,
          introductionId: 'recovery-intro',
          ownPeerId: owner.peerId,
          ownUsername: 'Owner',
        );
        expect(accepted?.status, IntroductionOverallStatus.pending);
        expect(
          ownIsRecipient
              ? accepted?.recipientStatus
              : accepted?.introducedStatus,
          IntroductionStatus.accepted,
        );
        if (scenario == 'two qualifying' ||
            scenario == 'two introducers' ||
            scenario == 'one qualifying same introducer') {
          // Legacy/replayed SQL rows can coexist; the recovery query must
          // count qualifying introductions separately from distinct introducers.
          await intros.saveIntroduction(
            IntroductionModel(
              id: 'additional-intro',
              introducerId: scenario == 'two introducers'
                  ? TestEd25519Identity.fromSeedByte(0x79).peerId
                  : introducer.peerId,
              recipientId: owner.peerId,
              introducedId: sender.peerId,
              recipientStatus: scenario == 'two qualifying'
                  ? IntroductionStatus.accepted
                  : IntroductionStatus.pending,
              createdAt: now,
            ),
          );
        }
        final pendingRequest = ContactRequestModel(
          peerId: sender.peerId,
          publicKey: sender.publicKey,
          rendezvous: 'old-request-rendezvous',
          username: 'Sender',
          signature: 'old-request-signature',
          receivedAt: now,
          mlKemPublicKey: 'sender-mlkem',
        );
        if (scenario == 'declined') {
          await requests.addRequest(pendingRequest);
          expect(
            await declineContactRequest(
              requestRepo: requests,
              peerId: sender.peerId,
            ),
            DeclineContactRequestResult.success,
          );
        } else if (scenario == 'deleted') {
          await contacts.addContact(
            ContactModel(
              peerId: sender.peerId,
              publicKey: sender.publicKey,
              rendezvous: 'previous-rendezvous',
              username: 'Sender',
              signature: 'previous-signature',
              scannedAt: now,
            ),
          );
          await contacts.deleteContact(sender.peerId);
        }
        final prompts = <ContactRequestModel>[];
        final recoveredStatuses = <IntroductionModel>[];
        var recoveryCalls = 0;
        final listener = ContactRequestListener(
          contactRequestStream: const Stream<ChatMessage>.empty(),
          requestRepo: requests,
          contactRepo: contacts,
          bridge: receiveBridge,
          getOwnPeerId: () => ownerIdentity.peerId,
          getOwnPrivateKey: () async =>
              (await ownerIdentities.loadIdentity())?.privateKey,
          getOwnPublicKey: () async =>
              (await ownerIdentities.loadIdentity())?.publicKey,
          repairRepository: SqlContactRepairRepository(db),
          // Match production_application_bootstrap.dart:6553-6565: the owner
          // chose Accept/Decline presentation rather than tap-free auto-add.
          autoAcceptAndReciprocate: null,
          downloadProfilePictureFn:
              ({
                required bridge,
                required contactRepo,
                required ownerPeerId,
                required avatarVersion,
                bool retryPendingRequest = false,
              }) async => null,
          attemptSilentIntroRecovery: (request) {
            recoveryCalls++;
            return recoverIntroContactRequest(
              introRepo: intros,
              requestRepo: requests,
              contactRepo: contacts,
              ownPeerId: ownerIdentity.peerId,
              request: request,
              messageRepo: messages,
            );
          },
          emitRecoveredIntroductionStatus: recoveredStatuses.add,
        );
        addTearDown(listener.dispose);
        final subscription = listener.requestStream.listen(prompts.add);
        addTearDown(subscription.cancel);
        // Drain the initial empty durable replay before creating a duplicate
        // pending row. Future(event) flushes queued microtasks, not wall time.
        await initialPendingRead.future;
        await Future<void>(() {});
        expect(prompts, isEmpty);
        final shouldRecover =
            scenario == 'recipient' ||
            scenario == 'introduced' ||
            scenario == 'one qualifying same introducer';
        if (shouldRecover) await requests.addRequest(pendingRequest);
        final wireFuture = ownerP2p.messageStream.first;
        expect(
          await sendContactRequest(
            p2pService: senderP2p,
            identityRepo: senderIdentities,
            bridge: sendBridge,
            targetPeerId: owner.peerId,
            recipientPublicKey: owner.publicKey,
          ),
          SendContactRequestResult.success,
        );
        final wire = await wireFuture;
        final result = await listener.processIncomingMessage(wire);
        // The receive call has completed; flush its broadcast notifications.
        await Future<void>(() {});
        expect(receiveBridge.verifyCalls, greaterThan(0));
        final after = (await intros.getIntroduction('recovery-intro'))!;
        if (shouldRecover) {
          expect(result, HandleMessageResult.silentIntroRecovered);
          expect(recoveryCalls, 1);
          expect(after.status, IntroductionOverallStatus.mutualAccepted);
          expect(after.recipientStatus, IntroductionStatus.accepted);
          expect(after.introducedStatus, IntroductionStatus.accepted);
          final contact = (await contacts.getContact(sender.peerId))!;
          expect(contact.username, 'Sender');
          expect(contact.publicKey, sender.publicKey);
          expect(contact.mlKemPublicKey, 'sender-mlkem');
          expect(contact.introducedBy, 'Introducer');
          expect(contact.introducedByPeerId, introducer.peerId);
          expect(await contacts.getContactCount(), 2);
          expect(await requests.getRequest(sender.peerId), isNull);
          expect(prompts, isEmpty);
          expect(recoveredStatuses.map((intro) => intro.id), [
            'recovery-intro',
          ]);
          final history = await messages.getMessagesForContact(sender.peerId);
          expect(history.length, 1);
          expect(
            history.single.text,
            'You and Sender are now connected — introduced by Introducer',
          );
          // Same envelope cannot create another contact/system row or prompt.
          await listener.processIncomingMessage(wire);
          await Future<void>(() {});
          expect(await contacts.getContactCount(), 2);
          expect(await messages.getMessageCountForContact(sender.peerId), 1);
          expect(prompts, isEmpty);
          expect(recoveredStatuses.length, 1);
        } else {
          expect(prompts.length, 1);
          expect(prompts.single.username, 'Sender');
          expect(await contacts.getContact(sender.peerId), isNull);
          expect(await contacts.getContactCount(), 1);
          expect(after.status, IntroductionOverallStatus.pending);
          expect(after.recipientStatus, IntroductionStatus.accepted);
          expect(after.introducedStatus, IntroductionStatus.pending);
          expect(recoveredStatuses, isEmpty);
          expect(await messages.getMessageCountForContact(sender.peerId), 0);
          expect(
            (await requests.getRequest(sender.peerId))?.status,
            ContactRequestStatus.pending,
          );
          expect(
            recoveryCalls,
            scenario == 'declined' || scenario == 'deleted' ? 0 : 1,
          );
        }
      });
    }
  });
}
