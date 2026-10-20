import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/contact_requests_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Shared wiring only: all persistence decisions run in production helpers and repositories.
Future<Database> openContactWidgetDatabase() {
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

IdentityRepositoryImpl buildWidgetIdentityRepository(
  Database db,
  SecureKeyStore keyStore,
) => IdentityRepositoryImpl(
  dbLoadIdentityRow: () => dbLoadIdentityRow(db),
  dbUpsertIdentityRow: (row) => dbUpsertIdentityRow(db, row),
  secureKeyStore: keyStore,
);

ContactRepositoryImpl buildWidgetContactRepository(Database db) =>
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

MessageRepositoryImpl buildWidgetMessageRepository(Database db) =>
    MessageRepositoryImpl(
      dbInsertMessage: (row) => dbInsertMessage(db, row),
      dbLoadMessagesForContact: (peerId) =>
          dbLoadMessagesForContact(db, peerId),
      dbLoadLatestMessageForContact: (peerId) =>
          dbLoadLatestMessageForContact(db, peerId),
      dbUpdateMessageStatus: (id, status) =>
          dbUpdateMessageStatus(db, id, status),
      dbLoadMessage: (id) => dbLoadMessage(db, id),
      dbMarkIncomingQuietRecovery: (expected) =>
          dbMarkIncomingQuietRecovery(db, expected.toMap()),
      dbCountMessagesForContact: (peerId) =>
          dbCountMessagesForContact(db, peerId),
      dbMarkConversationAsRead: (peerId) =>
          dbMarkConversationAsRead(db, peerId),
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
              dbRecoverStuckSendingMessages(
                db,
                olderThan: olderThan,
                limit: limit,
              ),
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

ContactRequestRepositoryImpl buildWidgetRequestRepository(Database db) =>
    ContactRequestRepositoryImpl(
      dbLoadPendingRequests: () => dbLoadPendingRequests(db),
      dbLoadRequest: (peerId) => dbLoadRequest(db, peerId),
      dbUpsertRequest: (row) => dbUpsertRequest(db, row),
      dbUpdateRequestStatus: (peerId, status) =>
          dbUpdateRequestStatus(db, peerId, status),
      dbDeleteRequest: (peerId) => dbDeleteRequest(db, peerId),
      dbRequestExists: (peerId) => dbRequestExists(db, peerId),
    );
