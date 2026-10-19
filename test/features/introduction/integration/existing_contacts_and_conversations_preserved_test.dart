import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/core/database/helpers/introduction_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introductions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_introduction_responses_db_helpers.dart';
import 'package:flutter_app/features/introduction/data/repositories/introduction_repository_impl.dart';
import 'package:flutter_app/features/introduction/application/handle_incoming_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/application/handle_mutual_acceptance_use_case.dart';
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
  group('IN-007 introductions preserve existing contacts and conversations', () {
    for (final ownIsRecipient in [true, false]) {
      for (final mutuallyAccepted in [false, true]) {
        test(
          '${ownIsRecipient ? "recipient" : "introduced"}: '
          '${mutuallyAccepted ? "mutual acceptance preserves contact created meanwhile" : "offer becomes alreadyConnected"}',
          () async {
            final db = await _openDb();
            addTearDown(db.close);
            final identityRepo = _buildIdentityRepo(db, FakeSecureKeyStore());
            final owner = TestEd25519Identity.fromSeedByte(0x73);
            final other = TestEd25519Identity.fromSeedByte(0x74);
            final introducer = TestEd25519Identity.fromSeedByte(0x75);
            await identityRepo.saveIdentity(
              testIdentityModel(
                owner,
                username: 'Owner',
                mlKemPublicKey: 'owner-mlkem',
              ),
            );
            final ownPeerId = (await identityRepo.loadIdentity())!.peerId;
            final contacts = _buildContactRepo(db);
            final messages = _buildMessageRepo(db);
            final intros = _buildIntroRepo(db);
            await contacts.addContact(
              ContactModel(
                peerId: introducer.peerId,
                publicKey: introducer.publicKey,
                rendezvous: 'introducer-rendezvous',
                username: 'Introducer',
                signature: 'introducer-signature',
                scannedAt: '2026-01-01T00:00:00.000Z',
              ),
            );
            // The incumbent identity is deliberately different from the offer.
            final incumbent = ContactModel(
              peerId: other.peerId,
              publicKey: other.publicKey,
              mlKemPublicKey: 'trusted-mlkem',
              rendezvous: 'trusted-rendezvous',
              username: 'Saved contact name',
              signature: 'trusted-signature',
              scannedAt: '2026-01-01T00:00:00.000Z',
              isArchived: true,
              archivedAt: '2026-01-01T01:00:00.000Z',
              introsBannerDismissed: true,
              introducedBy: 'Original introducer',
              introducedByPeerId: introducer.peerId,
            );
            final offer = IntroductionPayload(
              action: 'send',
              introductionId: 'preservation-intro',
              introducerId: introducer.peerId,
              introducerUsername: 'Introducer',
              recipientId: ownIsRecipient ? ownPeerId : other.peerId,
              recipientUsername: ownIsRecipient ? 'Owner' : 'Offered name',
              introducedId: ownIsRecipient ? other.peerId : ownPeerId,
              introducedUsername: ownIsRecipient ? 'Offered name' : 'Owner',
              recipientPublicKey: 'offered-recipient-key',
              recipientMlKemPublicKey: 'offered-recipient-mlkem',
              introducedPublicKey: 'offered-introduced-key',
              introducedMlKemPublicKey: 'offered-introduced-mlkem',
              timestamp: '2026-01-02T00:00:00.000Z',
            );
            if (mutuallyAccepted) {
              // Persist a pending offer first; a different flow adds the contact
              // before mutual acceptance is applied.
              final incoming = await handleIncomingIntroduction(
                payload: offer,
                introRepo: intros,
                contactRepo: contacts,
                ownPeerId: ownPeerId,
                transportSenderPeerId: introducer.peerId,
                messageRepo: messages,
              );
              expect(incoming.$1, HandleIntroductionResult.success);
              expect(incoming.$2?.status, IntroductionOverallStatus.pending);
            }
            await contacts.addContact(incumbent);
            await messages.saveMessage(
              ConversationMessage(
                id: 'existing-history',
                contactPeerId: other.peerId,
                senderPeerId: other.peerId,
                text: 'Keep this conversation',
                timestamp: '2026-01-01T02:00:00.000Z',
                status: 'delivered',
                isIncoming: true,
                createdAt: '2026-01-01T02:00:00.000Z',
                readAt: '2026-01-01T03:00:00.000Z',
              ),
            );
            await messages.saveMessage(
              ConversationMessage(
                id: 'unrelated-history',
                contactPeerId: introducer.peerId,
                senderPeerId: ownPeerId,
                text: 'Keep the other conversation too',
                timestamp: '2026-01-01T04:00:00.000Z',
                status: 'delivered',
                isIncoming: false,
                createdAt: '2026-01-01T04:00:00.000Z',
              ),
            );
            if (mutuallyAccepted) {
              // Use real SQL status transitions and the production contact-
              // creation use case; this case isolates the existing-contact guard.
              await intros.updateRecipientStatus(
                'preservation-intro',
                IntroductionStatus.accepted,
              );
              await intros.updateIntroducedStatus(
                'preservation-intro',
                IntroductionStatus.accepted,
              );
              await intros.updateOverallStatus(
                'preservation-intro',
                IntroductionOverallStatus.mutualAccepted,
              );
              final mutual = (await intros.getIntroduction(
                'preservation-intro',
              ))!;
              expect(
                await handleMutualAcceptance(
                  introduction: mutual,
                  contactRepo: contacts,
                  ownPeerId: ownPeerId,
                  messageRepo: messages,
                ),
                isNull,
              );
            } else {
              final incoming = await handleIncomingIntroduction(
                payload: offer,
                introRepo: intros,
                contactRepo: contacts,
                ownPeerId: ownPeerId,
                transportSenderPeerId: introducer.peerId,
                messageRepo: messages,
              );
              expect(incoming.$1, HandleIntroductionResult.success);
              expect(
                incoming.$2?.status,
                IntroductionOverallStatus.alreadyConnected,
              );
              expect(
                (await intros.getIntroduction('preservation-intro'))?.status,
                IntroductionOverallStatus.alreadyConnected,
              );
            }
            // All production work above is awaited before absence assertions.
            final preserved = (await contacts.getContact(other.peerId))!;
            expect(await contacts.getContactCount(), 2);
            expect(preserved.publicKey, other.publicKey);
            expect(preserved.mlKemPublicKey, 'trusted-mlkem');
            expect(preserved.rendezvous, 'trusted-rendezvous');
            expect(preserved.username, 'Saved contact name');
            expect(preserved.signature, 'trusted-signature');
            expect(preserved.isArchived, isTrue);
            expect(preserved.introsBannerDismissed, isTrue);
            expect(preserved.introducedBy, 'Original introducer');
            expect(preserved.toMap(), incumbent.toMap());
            expect(await messages.getMessageCountForContact(other.peerId), 1);
            expect(
              await messages.getMessageCountForContact(introducer.peerId),
              1,
            );
            final history = (await messages.getMessage('existing-history'))!;
            expect(history.text, 'Keep this conversation');
            expect(history.readAt, '2026-01-01T03:00:00.000Z');
            expect(history.status, 'delivered');
            expect(
              (await messages.getMessage('unrelated-history'))?.text,
              'Keep the other conversation too',
            );
          },
        );
      }
    }
  });
}
