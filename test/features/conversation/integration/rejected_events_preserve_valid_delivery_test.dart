import 'dart:async';
import 'dart:convert';

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
import 'package:flutter_app/features/contacts/application/direct_transport_authority.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../core/bridge/fake_bridge.dart';

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
  dbApplyIncomingOrdinaryTextMutation:
      ({required incomingRow, required kind}) =>
          dbApplyIncomingOrdinaryTextMutation(
            db,
            incomingRow: incomingRow,
            kind: kind,
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

// The bridge is the only fault-injection seam: SQL and receive policy are real.
class _RejectOneCiphertextBridge extends PassthroughCryptoBridge {
  @override
  Future<String> send(String message) {
    final request = jsonDecode(message) as Map<String, dynamic>;
    if (request['cmd'] == 'message.decrypt' &&
        (request['payload'] as Map<String, dynamic>)['ciphertext'] ==
            'authentication-failure-fixture') {
      return Future.value(
        jsonEncode({
          'ok': false,
          'errorCode': 'INTERNAL_ERROR',
          'errorMessage': 'message authentication failed',
        }),
      );
    }
    return super.send(message);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('RG-004 rejected events preserve subsequent direct-chat delivery', () {
    for (final malformed in [true, false]) {
      test(
        malformed
            ? 'malformed JSON then valid message'
            : 'failed decryption then valid message',
        () async {
          final db = await _openDb();
          addTearDown(db.close);
          final identityRepo = _buildIdentityRepo(db, FakeSecureKeyStore());
          final owner = TestEd25519Identity.fromSeedByte(0x71);
          final sender = TestEd25519Identity.fromSeedByte(0x72);
          await identityRepo.saveIdentity(
            testIdentityModel(
              owner,
              username: 'Owner',
              mlKemPublicKey: 'owner-mlkem',
            ),
          );
          final contacts = _buildContactRepo(db);
          final messages = _buildMessageRepo(db);
          final contact = ContactModel(
            peerId: sender.peerId,
            publicKey: sender.publicKey,
            rendezvous: 'fixture-rendezvous',
            username: 'Sender',
            signature: 'fixture-signature',
            scannedAt: '2026-01-01T00:00:00.000Z',
            mlKemPublicKey: 'sender-mlkem',
          );
          await contacts.addContact(contact);
          await messages.saveMessage(
            ConversationMessage(
              id: 'preserved-message',
              contactPeerId: sender.peerId,
              senderPeerId: owner.peerId,
              text: 'Existing history',
              timestamp: '2026-01-01T00:00:00.000Z',
              status: 'delivered',
              isIncoming: false,
              createdAt: '2026-01-01T00:00:00.000Z',
            ),
          );
          final bridge = _RejectOneCiphertextBridge();
          addTearDown(bridge.dispose);
          final incoming = StreamController<ChatMessage>();
          addTearDown(incoming.close);
          final listener = ChatMessageListener(
            chatMessageStream: incoming.stream,
            messageRepo: messages,
            contactRepo: contacts,
            bridge: bridge,
            transportAuthority: DatabaseDirectTransportAuthority(database: db),
            getOwnMlKemSecretKey: () async =>
                (await identityRepo.loadIdentity())?.mlKemSecretKey,
            downloadProfilePictureFn:
                ({
                  required bridge,
                  required contactRepo,
                  required ownerPeerId,
                  required avatarVersion,
                  bool retryPendingRequest = false,
                }) async => contact,
          );
          addTearDown(listener.dispose);
          String envelope(String id, String ciphertext) => jsonEncode({
            'type': 'chat_message',
            'version': '2',
            'id': id,
            'senderPeerId': sender.peerId,
            'encrypted': {
              'kem': 'fixture-kem',
              'ciphertext': ciphertext,
              'nonce': 'fixture-nonce',
            },
          });
          ChatMessage wire(String content) => ChatMessage(
            from: sender.peerId,
            to: owner.peerId,
            content: content,
            timestamp: '2026-01-02T00:00:00.000Z',
            isIncoming: true,
          );
          // Await the production completion boundary before checking absence.
          final rejected = await listener.processIncomingMessage(
            wire(
              malformed
                  ? '{invalid-json'
                  : envelope(
                      'rejected-message',
                      'authentication-failure-fixture',
                    ),
            ),
            suppressNotification: true,
          );
          expect(
            rejected.state,
            malformed
                ? ChatMessageProcessState.notChatMessage
                : ChatMessageProcessState.decryptionFailed,
          );
          expect(await messages.getMessage('rejected-message'), isNull);
          expect(await messages.getMessageCountForContact(sender.peerId), 1);
          expect(
            (await messages.getMessage('preserved-message'))?.text,
            'Existing history',
          );
          expect(
            (await contacts.getContact(sender.peerId))?.toMap(),
            contact.toMap(),
          );
          final validWire = wire(
            envelope(
              'valid-message',
              jsonEncode({
                'id': 'valid-message',
                'text': 'Valid delivery after rejection',
                'senderPeerId': sender.peerId,
                'senderUsername': 'Sender',
                'timestamp': '2026-01-02T00:00:00.000Z',
              }),
            ),
          );
          // Same listener, same repositories, no restart or reset after rejection.
          final delivered = await listener.processIncomingMessage(
            validWire,
            suppressNotification: true,
          );
          expect(delivered.state, ChatMessageProcessState.stored);
          expect(
            (await messages.getMessage('valid-message'))?.text,
            'Valid delivery after rejection',
          );
          expect(await messages.getMessageCountForContact(sender.peerId), 2);
          expect(
            (await messages.getMessage('preserved-message'))?.text,
            'Existing history',
          );
          final replay = await listener.processIncomingMessage(
            validWire,
            suppressNotification: true,
          );
          expect(replay.state, ChatMessageProcessState.duplicate);
          expect(await messages.getMessageCountForContact(sender.peerId), 2);
          expect(await contacts.getContactCount(), 1);

          // Exercise the real subscription/queue as well as direct processing:
          // rejected input must not wedge the valid callback queued after it.
          listener.start();
          final queuedDelivery = listener.incomingMessageStream.firstWhere(
            (message) => message.id == 'queued-valid-message',
          );
          incoming.add(
            wire(
              malformed
                  ? '{invalid-json'
                  : envelope(
                      'queued-rejected-message',
                      'authentication-failure-fixture',
                    ),
            ),
          );
          incoming.add(
            wire(
              envelope(
                'queued-valid-message',
                jsonEncode({
                  'id': 'queued-valid-message',
                  'text': 'Queued delivery after rejection',
                  'senderPeerId': sender.peerId,
                  'senderUsername': 'Sender',
                  'timestamp': '2026-01-02T00:00:01.000Z',
                }),
              ),
            ),
          );
          expect(
            (await queuedDelivery.timeout(const Duration(seconds: 3))).text,
            'Queued delivery after rejection',
          );
          expect(await messages.getMessage('queued-rejected-message'), isNull);
          expect(await messages.getMessageCountForContact(sender.peerId), 3);
          expect(
            (await messages.getMessage('preserved-message'))?.text,
            'Existing history',
          );
        },
      );
    }
  });
}
