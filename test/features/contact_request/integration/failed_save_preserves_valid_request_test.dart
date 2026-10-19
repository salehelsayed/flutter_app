import 'dart:async';

import 'package:flutter_app/app/bootstrap/production_canonical_direct_replay_composition.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introduction_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introductions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_library_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_introduction_responses_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart'
    show RecoveredInboxChatDisposition;
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/data/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/data/repositories/introduction_repository_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';

final _cryptoBus = Ed25519ContactRequestCryptoBus();
final _aliceId = TestEd25519Identity.fromSeedByte(0x31);
final _bobId = TestEd25519Identity.fromSeedByte(0x32);

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

MediaAttachmentRepositoryImpl _buildMediaAttachmentRepo(
  Database db,
  SecureKeyStore keyStore,
) => MediaAttachmentRepositoryImpl(
  dbSaveMediaAttachmentPreservingLocalState: (row) =>
      dbSaveMediaAttachmentPreservingLocalState(db, row),
  dbCanApplyGenericMediaAttachmentSave: (row) =>
      dbCanApplyGenericMediaAttachmentSave(db, row),
  dbLoadMediaForMessage: (messageId, ownerLane) =>
      dbLoadMediaForMessage(db, messageId, ownerLane: ownerLane),
  dbLoadMediaById: (id) => dbLoadMediaById(db, id),
  dbLoadMediaForMessages: (messageIds, ownerLane) =>
      dbLoadMediaForMessages(db, messageIds, ownerLane: ownerLane),
  dbUpdateMediaLocalPath: (id, path, status) =>
      dbUpdateMediaLocalPath(db, id, path, status),
  dbUpdateMediaDownloadStatus: (id, status) =>
      dbUpdateMediaDownloadStatus(db, id, status),
  dbDeleteMediaForMessage: (messageId, ownerLane) =>
      dbDeleteMediaForMessage(db, messageId, ownerLane: ownerLane),
  dbDeleteMediaForContact: (peerId) => dbDeleteMediaForContact(db, peerId),
  dbMarkUploadPendingAttachmentsFailedForMessage: (messageId, ownerLane) =>
      dbMarkUploadPendingAttachmentsFailedForMessage(
        db,
        messageId,
        ownerLane: ownerLane,
      ),
  dbLoadPendingMediaDownloads: () => dbLoadPendingMediaDownloads(db),
  dbLoadUploadPendingAttachments: ({limit = 50, required ownerLane}) =>
      dbLoadUploadPendingAttachments(db, limit: limit, ownerLane: ownerLane),
  dbSetMediaBookmarked: (id, bookmarked) =>
      dbSetMediaBookmarked(db, id, bookmarked: bookmarked),
  dbUpdateMediaPlaybackPosition: (id, positionMs) =>
      dbUpdateMediaPlaybackPosition(db, id, positionMs),
  dbLoadMediaLibraryPage:
      ({
        required scopeKind,
        required scopeId,
        required mediaTypes,
        required bookmarkedOnly,
        incomingOnly = false,
        required limit,
        afterTimestamp,
        afterMessageId,
        afterAttachmentId,
      }) => dbLoadMediaLibraryPage(
        db,
        scopeKind: scopeKind,
        scopeId: scopeId,
        mediaTypes: mediaTypes,
        bookmarkedOnly: bookmarkedOnly,
        incomingOnly: incomingOnly,
        limit: limit,
        afterTimestamp: afterTimestamp,
        afterMessageId: afterMessageId,
        afterAttachmentId: afterAttachmentId,
      ),
  dbSaveDirectPrivateMediaAttachmentGuarded:
      (row, {required messageId, required nowMs}) =>
          dbSaveDirectPrivateMediaAttachmentGuarded(
            db,
            row,
            messageId: messageId,
            nowMs: nowMs,
          ),
  secureKeyStore: keyStore,
);

ReactionRepositoryImpl _buildReactionRepo(Database db) =>
    ReactionRepositoryImpl(
      dbInsertReaction: (row) => dbInsertReaction(db, row),
      dbApplyIncomingAdd: (row) async {
        final result = await dbApplyIncomingReactionMutation(
          db,
          row,
          mutation: DbIncomingReactionMutation.add,
        );
        return switch (result) {
          DbIncomingReactionApplyResult.inserted =>
            ReactionAddApplyResult.inserted,
          DbIncomingReactionApplyResult.updated =>
            ReactionAddApplyResult.updated,
          DbIncomingReactionApplyResult.exactReplay =>
            ReactionAddApplyResult.exactReplay,
          DbIncomingReactionApplyResult.stale => ReactionAddApplyResult.stale,
          DbIncomingReactionApplyResult.removed => throw StateError(
            'ADD returned REMOVE',
          ),
        };
      },
      dbApplyIncomingRemove: (row) async {
        final result = await dbApplyIncomingReactionMutation(
          db,
          row,
          mutation: DbIncomingReactionMutation.remove,
        );
        return switch (result) {
          DbIncomingReactionApplyResult.removed =>
            ReactionRemoveApplyResult.applied,
          DbIncomingReactionApplyResult.exactReplay =>
            ReactionRemoveApplyResult.exactReplay,
          DbIncomingReactionApplyResult.stale =>
            ReactionRemoveApplyResult.stale,
          DbIncomingReactionApplyResult.inserted ||
          DbIncomingReactionApplyResult.updated => throw StateError(
            'REMOVE returned ADD',
          ),
        };
      },
      dbLoadReactionsForMessage: (messageId) =>
          dbLoadReactionsForMessage(db, messageId),
      dbLoadReactionsForMessages: (messageIds) =>
          dbLoadReactionsForMessages(db, messageIds),
      dbLoadActiveOrTombstonedReactionForSender: (messageId, senderPeerId) =>
          dbLoadActiveOrTombstonedReactionForSender(
            db,
            messageId,
            senderPeerId,
          ),
      dbDeleteReaction: (messageId, senderPeerId, {removedAtTimestamp}) =>
          dbDeleteReaction(
            db,
            messageId,
            senderPeerId,
            removedAtTimestamp: removedAtTimestamp,
          ),
      dbDeleteReactionsForMessage: (messageId) =>
          dbDeleteReactionsForMessage(db, messageId),
      dbDeleteReactionsForContact: (peerId) =>
          dbDeleteReactionsForContact(db, peerId),
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
  late Database aliceDb;
  late Database bobDb;
  late FakeP2PNetwork network;

  setUp(() async {
    _cryptoBus
      ..register(_aliceId)
      ..register(_bobId);
    aliceDb = await _openDb();
    bobDb = await _openDb();
    network = FakeP2PNetwork();
  });

  tearDown(() async {
    await aliceDb.close();
    await bobDb.close();
  });

  group('CR-020 a failed save does not lose a valid request', () {
    test(
      'storage failure on a valid incoming request withholds direct ACK, keeps ProductionCanonicalDirectReplayComposition.replayContactRequest retryable, and surfaces the request once across duplicate replays after storage recovers',
      () async {
        var failUpsert = true;
        final aliceKeyStore = FakeSecureKeyStore();
        final bobKeyStore = FakeSecureKeyStore();
        final aliceIdentities = _buildIdentityRepo(aliceDb, aliceKeyStore);
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

        final aliceContacts = _buildContactRepo(aliceDb);
        final aliceMessages = _buildMessageRepo(aliceDb);
        final aliceMedia = _buildMediaAttachmentRepo(aliceDb, aliceKeyStore);
        final aliceReactions = _buildReactionRepo(aliceDb);
        final aliceIntros = _buildIntroRepo(aliceDb);
        final aliceRequests = ContactRequestRepositoryImpl(
          dbLoadPendingRequests: () => dbLoadPendingRequests(aliceDb),
          dbLoadRequest: (peerId) => dbLoadRequest(aliceDb, peerId),
          dbUpsertRequest: (row) async {
            if (failUpsert) {
              throw StateError(
                'simulated SQLite write failure on contact_requests upsert',
              );
            }
            await dbUpsertRequest(aliceDb, row);
          },
          dbUpdateRequestStatus: (peerId, status) =>
              dbUpdateRequestStatus(aliceDb, peerId, status),
          dbDeleteRequest: (peerId) => dbDeleteRequest(aliceDb, peerId),
          dbRequestExists: (peerId) => dbRequestExists(aliceDb, peerId),
        );

        final aliceBridge = Ed25519ContactRequestBridge(_cryptoBus);
        final bobBridge = Ed25519ContactRequestBridge(_cryptoBus);
        final aliceP2p = FakeP2PService(
          peerId: _aliceId.peerId,
          network: network,
        );
        final bobP2p = FakeP2PService(peerId: _bobId.peerId, network: network);
        addTearDown(() {
          aliceP2p.dispose();
          bobP2p.dispose();
        });

        // Capture the real v2 encrypted wire envelope built by sendContactRequest
        // using a stream completion barrier (no wall-clock sleep).
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
        final wireEnvelope = await firstWireFuture;

        final directMessage = ChatMessage(
          from: wireEnvelope.from,
          to: wireEnvelope.to,
          content: wireEnvelope.content,
          timestamp: wireEnvelope.timestamp,
          isIncoming: true,
          confirmNonce: 'direct-nonce-cr020',
        );
        final inboxMessage = ChatMessage(
          from: wireEnvelope.from,
          to: wireEnvelope.to,
          content: wireEnvelope.content,
          timestamp: wireEnvelope.timestamp,
          isIncoming: true,
        );

        final aliceChatListener = ChatMessageListener(
          transportAuthority: DatabaseDirectTransportAuthority(
            database: aliceDb,
          ),
          chatMessageStream: const Stream<ChatMessage>.empty(),
          messageRepo: aliceMessages,
          contactRepo: aliceContacts,
          bridge: aliceBridge,
          getOwnMlKemSecretKey: () async =>
              (await aliceIdentities.loadIdentity())?.mlKemSecretKey,
          mediaAttachmentRepo: aliceMedia,
          mediaFileManager: MediaFileManager(),
        );
        final aliceIntroListener = IntroductionListener(
          introductionStream: const Stream<ChatMessage>.empty(),
          introRepo: aliceIntros,
          contactRepo: aliceContacts,
          bridge: aliceBridge,
          messageRepo: aliceMessages,
          getOwnMlKemSecretKey: () async =>
              (await aliceIdentities.loadIdentity())?.mlKemSecretKey,
          getOwnPeerId: () async => _aliceId.peerId,
        );
        final aliceListener = ContactRequestListener(
          contactRequestStream: const Stream<ChatMessage>.empty(),
          requestRepo: aliceRequests,
          contactRepo: aliceContacts,
          bridge: aliceBridge,
          getOwnPeerId: () => _aliceId.peerId,
          getOwnPrivateKey: () async => _aliceId.privateKey,
          getOwnPublicKey: () async => _aliceId.publicKey,
          downloadProfilePictureFn: _settledAvatar,
        );
        final prompted = <ContactRequestModel>[];
        final promptSub = aliceListener.requestStream.listen(prompted.add);
        aliceListener.start();
        addTearDown(() async {
          await promptSub.cancel();
          aliceListener.dispose();
          aliceIntroListener.dispose();
          aliceChatListener.dispose();
        });

        final directReplay = ProductionCanonicalDirectReplayComposition(
          loadIdentity: aliceIdentities.loadIdentity,
          chatMessageListener: () => aliceChatListener,
          introductionListener: () => aliceIntroListener,
          contactRequestListener: () => aliceListener,
          introductionRepository: aliceIntros,
          contactRepository: aliceContacts,
          messageRepository: aliceMessages,
          reactionRepository: aliceReactions,
          mediaAttachmentRepository: aliceMedia,
          transportAuthority: DatabaseDirectTransportAuthority(
            database: aliceDb,
          ),
          bridge: aliceBridge,
          secureKeyStore: aliceKeyStore,
          mediaFileManager: MediaFileManager(),
          sendDeliveryReceipt: ({
            required contactPeerId,
            required messageIds,
            mutationEventIds,
          }) async {},
          notificationOwner: () => null,
          reactionNotificationDependencies: () => null,
          publishPersistedReactionChange: () => null,
        );

        // 1. Live direct delivery while SQLite upsert fails: listener must
        // report ok=false via message:confirm so the sender falls back to the
        // relay inbox.
        try {
          await aliceListener.processIncomingMessage(directMessage);
        } catch (_) {}

        final confirmPayloads = aliceBridge.commands
            .where((c) => c['cmd'] == 'message:confirm')
            .map((c) => c['payload'] as Map<String, dynamic>)
            .toList();
        expect(confirmPayloads, <Map<String, Object>>[
          <String, Object>{'nonce': 'direct-nonce-cr020', 'ok': false},
        ]);
        expect(await aliceRequests.getPendingRequests(), isEmpty);
        expect(prompted, isEmpty);

        // 2. Relay inbox replay through ProductionCanonicalDirectReplayComposition
        // while SQLite upsert still fails: disposition must be retryable (not
        // committed) so the relay/staging copy is retained.
        final failedReplayOutcome = await directReplay.replayContactRequest(
          inboxMessage,
        );
        expect(
          failedReplayOutcome.disposition,
          RecoveredInboxChatDisposition.retryable,
          reason:
              'A failed SQLite save during inbox replay must stay retryable rather than committing custody',
        );
        expect(await aliceRequests.getPendingRequests(), isEmpty);

        // 3. Storage recovers: retrying the same inbox message commits once,
        // and replaying the recovered envelope a second time keeps exactly one
        // pending row and one presentation with no contact added before consent.
        failUpsert = false;
        final recoveredOutcome = await directReplay.replayContactRequest(
          inboxMessage,
        );
        expect(
          recoveredOutcome.disposition,
          RecoveredInboxChatDisposition.committed,
        );

        final secondReplayOutcome = await directReplay.replayContactRequest(
          inboxMessage,
        );
        expect(
          secondReplayOutcome.disposition,
          RecoveredInboxChatDisposition.committed,
        );

        final pendingRows = await aliceRequests.getPendingRequests();
        expect(pendingRows, hasLength(1));
        expect(pendingRows.single.peerId, _bobId.peerId);
        expect(pendingRows.single.username, 'Bob');
        expect(pendingRows.single.status, ContactRequestStatus.pending);
        expect(prompted, hasLength(1));
        expect(prompted.single.peerId, _bobId.peerId);
        expect(await aliceContacts.getContact(_bobId.peerId), isNull);
      },
      skip:
          'KNOWN GAP CR-020: handleIncomingMessage turns addRequest write failure into invalidMessage so ContactRequestListener confirms ok=true and ProductionCanonicalDirectReplayComposition.replayContactRequest commits custody without saving, lib/features/contact_request/application/handle_incoming_message_use_case.dart:834-842. Remove when fixed.',
    );
  });
}
