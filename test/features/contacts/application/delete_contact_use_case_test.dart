import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart'
    show dbPurgeDirectContactConversationAndContact;
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart'
    show kDirectMediaBlobCustodyTable;
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/contacts/domain/repositories/direct_contact_conversation_purge.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/contacts/application/delete_contact_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_outbox_delivery.dart';
import 'package:flutter_app/features/introduction/domain/models/pending_introduction_response.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:path/path.dart' as p;

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../../shared/fakes/fake_media_file_manager.dart' as shared;

class FakeContactRepository implements ContactRepository {
  final List<String> deletedPeerIds = [];
  final List<String>? operations;
  bool shouldThrow = false;

  FakeContactRepository({this.operations});

  @override
  Future<void> deleteContact(String peerId) async {
    if (shouldThrow) throw Exception('DB error');
    deletedPeerIds.add(peerId);
    operations?.add('contact:$peerId');
  }

  @override
  Future<void> addContact(ContactModel contact) async {}
  @override
  Future<bool> contactExists(String peerId) async => false;
  @override
  Future<List<ContactModel>> getAllContacts() async => [];
  @override
  Future<ContactModel?> getContact(String peerId) async => null;
  @override
  Future<int> getContactCount() async => 0;
  @override
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
  @override
  Future<List<ContactModel>> getActiveContacts() async => [];
  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
  @override
  Future<void> dismissIntroBanner(String peerId) async {}
  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

class FakeMessageRepository implements MessageRepository {
  final List<String> deletedForContact = [];
  final List<String>? operations;
  List<ConversationMessage> visibleMessages = [];
  List<ConversationMessage> failedMessages = [];
  List<ConversationMessage> unackedMessages = [];
  List<ConversationMessage> sendingMessages = [];
  bool shouldThrow = false;

  FakeMessageRepository({this.operations});

  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async {
    if (shouldThrow) throw Exception('DB error');
    deletedForContact.add(contactPeerId);
    operations?.add('messages:$contactPeerId');
    return 5; // arbitrary count
  }

  @override
  Future<int> deleteMessage(String id) async => 0;

  @override
  Future<void> saveMessage(ConversationMessage message) async {}
  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async => visibleMessages
      .where((message) => message.contactPeerId == contactPeerId)
      .toList(growable: false);
  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async => null;
  @override
  Future<void> updateMessageStatus(String id, String status) async {}
  @override
  Future<ConversationMessage?> getMessage(String id) async => null;
  @override
  Future<bool> existsByContent(
    String contactPeerId,
    String senderPeerId,
    String text,
    String timestamp,
  ) async => false;

  @override
  Future<bool> existsByDedupKey(
    String contactPeerId,
    String senderPeerId,
    String dedupKey,
  ) async => false;
  @override
  Future<bool> messageExists(String id) async => false;
  @override
  Future<int> getMessageCountForContact(String contactPeerId) async => 0;
  @override
  Future<int> markConversationAsRead(String contactPeerId) async => 0;
  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async => 0;
  @override
  Future<int> getTotalUnreadCount() async => 0;
  @override
  Future<int> getTotalUnreadCountExcludingArchived() async => 0;
  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async => [];

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async =>
      failedMessages;

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async => unackedMessages;

  @override
  Future<int> recoverStuckSendingMessages({
    required Duration olderThan,
  }) async => 0;

  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {}

  @override
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  }) async => [];

  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async =>
      sendingMessages;

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async => 0;
}

class FakeMediaAttachmentRepository implements MediaAttachmentRepository {
  final List<String> deletedForContact = [];
  final List<String>? operations;

  FakeMediaAttachmentRepository({this.operations});

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {}

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => const [];

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async => const {};

  @override
  Future<void> updateLocalPath(String id, String localPath) async {}

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async {
    deletedForContact.add(contactPeerId);
    operations?.add('attachments:$contactPeerId');
    return 3;
  }

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => const [];

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async => const [];
}

class FakeReactionRepository implements ReactionRepository {
  final List<String> deletedForContact = [];
  final List<String>? operations;

  FakeReactionRepository({this.operations});

  @override
  Future<void> saveReaction(MessageReaction reaction) async {}

  @override
  Future<ReactionAddApplyResult> applyIncomingAdd(
    MessageReaction reaction,
  ) async => ReactionAddApplyResult.inserted;

  @override
  Future<List<MessageReaction>> getReactionsForMessage(
    String messageId,
  ) async => const [];

  @override
  Future<Map<String, List<MessageReaction>>> getReactionsForMessages(
    List<String> messageIds,
  ) async => const {};

  @override
  Future<MessageReaction?> getReactionForSenderIncludingRemoved({
    required String messageId,
    required String senderPeerId,
  }) async => null;

  @override
  Future<int> removeReaction(
    String messageId,
    String senderPeerId, {
    String? removedAtTimestamp,
  }) async => 0;

  @override
  Future<int> deleteReactionsForMessage(String messageId) async => 0;

  @override
  Future<int> deleteReactionsForContact(String contactPeerId) async {
    deletedForContact.add(contactPeerId);
    operations?.add('reactions:$contactPeerId');
    return 4;
  }
}

class BarrierReactionRepository extends FakeReactionRepository {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<int> deleteReactionsForContact(String contactPeerId) async {
    if (!entered.isCompleted) {
      entered.complete();
    }
    await release.future;
    return super.deleteReactionsForContact(contactPeerId);
  }
}

/// 361: a contact repository that owns the final serialized purge.
class FakePurgeContactRepository extends FakeContactRepository
    implements DirectContactConversationPurgeCapability {
  FakePurgeContactRepository({super.operations});

  final List<String> purgedPeerIds = [];
  final Map<String, int> pendingRowsAtPurge = {};
  Map<String, int> rowsSeenAtPurge = const {};

  @override
  bool get supportsDirectContactConversationPurge => true;

  @override
  Future<DirectContactConversationPurgeSummary>
  purgeDirectContactConversationAndContact(String peerId) async {
    purgedPeerIds.add(peerId);
    operations?.add('purge:$peerId');
    // The final transaction sweeps whatever exists at commit time.
    rowsSeenAtPurge = Map<String, int>.from(pendingRowsAtPurge);
    pendingRowsAtPurge.clear();
    return const DirectContactConversationPurgeSummary(
      deletedTextCustodyRows: 1,
      deletedEventCustodyRows: 1,
      deletedReactions: 1,
      deletedMessages: 2,
      deletedContact: true,
    );
  }
}

/// 362: a purge-capable contact repository whose final owner is the REAL
/// serialized DB purge over the fixture database, so v114 blob-custody
/// convergence is proven against production SQL rather than a stub.
class RealDbPurgeContactRepository extends FakeContactRepository
    implements DirectContactConversationPurgeCapability {
  RealDbPurgeContactRepository(this.db);

  final Database db;
  final List<String> purgedPeerIds = [];

  @override
  bool get supportsDirectContactConversationPurge => true;

  @override
  Future<DirectContactConversationPurgeSummary>
  purgeDirectContactConversationAndContact(String peerId) async {
    purgedPeerIds.add(peerId);
    final result = await dbPurgeDirectContactConversationAndContact(db, peerId);
    return DirectContactConversationPurgeSummary(
      deletedTextCustodyRows: result.deletedTextCustodyRows,
      deletedEventCustodyRows: result.deletedEventCustodyRows,
      deletedReactions: result.deletedReactions,
      deletedMessages: result.deletedMessages,
      deletedContact: result.deletedContact,
    );
  }
}

/// 361: a message repository that reconciles from the committed purge.
class ReconcilingFakeMessageRepository extends FakeMessageRepository
    implements DirectContactPurgeReconciliation {
  ReconcilingFakeMessageRepository({super.operations});

  @override
  Future<void> reconcileDirectContactConversationPurge(String peerId) async {
    operations?.add('reconcile-messages:$peerId');
  }
}

/// 361: a reaction repository that reconciles from the committed purge.
class ReconcilingFakeReactionRepository extends FakeReactionRepository
    implements DirectContactPurgeReconciliation {
  ReconcilingFakeReactionRepository({super.operations});

  void Function()? onDeleteReactionsForContact;

  @override
  Future<int> deleteReactionsForContact(String contactPeerId) async {
    final deleted = await super.deleteReactionsForContact(contactPeerId);
    onDeleteReactionsForContact?.call();
    return deleted;
  }

  @override
  Future<void> reconcileDirectContactConversationPurge(String peerId) async {
    operations?.add('reconcile-reactions:$peerId');
  }
}

class FakeContactRequestRepository implements ContactRequestRepository {
  final List<String> deletedPeerIds = [];
  final List<String>? operations;

  FakeContactRequestRepository({this.operations});

  @override
  Future<void> addRequest(ContactRequestModel request) async {}

  @override
  Future<ContactRequestModel?> getRequest(String peerId) async => null;

  @override
  Future<List<ContactRequestModel>> getPendingRequests() async => const [];

  @override
  Future<void> updateStatus(String peerId, ContactRequestStatus status) async {}

  @override
  Future<void> deleteRequest(String peerId) async {
    deletedPeerIds.add(peerId);
    operations?.add('request:$peerId');
  }

  @override
  Future<bool> requestExists(String peerId) async => false;
}

class FakeIntroductionRepository implements IntroductionRepository {
  final List<IntroductionModel> introductions;
  final List<String> deletedIntroductionIds = [];
  final List<String>? operations;

  FakeIntroductionRepository({required this.introductions, this.operations});

  @override
  Future<void> saveIntroduction(IntroductionModel intro) async {}

  @override
  Future<void> saveIntroductionWithOutboxDeliveries(
    IntroductionModel intro,
    List<IntroductionOutboxDelivery> deliveries,
  ) async {}

  @override
  Future<void> replaceIntroductionWithPendingResponseMigration({
    required IntroductionModel intro,
    required List<IntroductionOutboxDelivery> deliveries,
    required List<String> replacedIntroductionIds,
  }) async {}

  @override
  Future<bool> saveIntroductionResponseWithOutboxDeliveries({
    required String introductionId,
    required bool isRecipient,
    required IntroductionStatus responseStatus,
    required IntroductionOverallStatus overallStatus,
    required String respondedAt,
    required List<IntroductionOutboxDelivery> deliveries,
  }) async => true;

  @override
  Future<IntroductionModel?> getIntroduction(String id) async {
    for (final intro in introductions) {
      if (intro.id == id) {
        return intro;
      }
    }
    return null;
  }

  @override
  Future<void> deleteIntroduction(String id) async {
    deletedIntroductionIds.add(id);
    operations?.add('intro:$id');
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByRecipient(
    String recipientId,
  ) async {
    return introductions
        .where((intro) => intro.recipientId == recipientId)
        .toList(growable: false);
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByIntroduced(
    String introducedId,
  ) async {
    return introductions
        .where((intro) => intro.introducedId == introducedId)
        .toList(growable: false);
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsByIntroducer(
    String introducerId,
  ) async {
    return introductions
        .where((intro) => intro.introducerId == introducerId)
        .toList(growable: false);
  }

  @override
  Future<List<IntroductionModel>> getIntroductionsForRecipientAndIntroducer(
    String recipientId,
    String introducerId,
  ) async => const [];

  @override
  Future<bool> updateRecipientStatus(
    String id,
    IntroductionStatus status,
  ) async => true;

  @override
  Future<bool> updateIntroducedStatus(
    String id,
    IntroductionStatus status,
  ) async => true;

  @override
  Future<void> updateOverallStatus(
    String id,
    IntroductionOverallStatus status,
  ) async {}

  @override
  Future<List<IntroductionModel>> getPendingIntroductionsForUser(
    String peerId,
  ) async => const [];

  @override
  Future<int> countPendingIntroductions(String peerId) async => 0;

  @override
  Future<void> savePendingResponse(
    PendingIntroductionResponse response,
  ) async {}

  @override
  Future<List<PendingIntroductionResponse>> loadPendingResponses(
    String introductionId,
  ) async => const [];

  @override
  Future<void> deletePendingResponse(String responseKey) async {}

  @override
  Future<void> saveOutboxDelivery(IntroductionOutboxDelivery delivery) async {}

  @override
  Future<List<IntroductionOutboxDelivery>> loadOutboxDeliveriesForIntroduction(
    String introductionId,
  ) async => const [];

  @override
  Future<List<IntroductionOutboxDelivery>> loadRetryableOutboxDeliveries({
    Duration olderThan = const Duration(seconds: 60),
    int limit = 100,
  }) async => const [];

  @override
  Future<void> deleteOutboxDelivery(String deliveryId) async {}

  @override
  Future<void> deleteOutboxDeliveriesForIntroduction(
    String introductionId,
  ) async {}
}

class FakeMediaFileManager extends MediaFileManager {
  final List<String> deletedPendingUploadMessageIds = [];
  final List<String> deletedMediaPeerIds = [];
  final List<String>? operations;

  FakeMediaFileManager({this.operations});

  @override
  Future<void> deletePendingUploadDir(String messageId) async {
    deletedPendingUploadMessageIds.add(messageId);
    operations?.add('pending-upload:$messageId');
  }

  @override
  Future<void> deleteMediaForContact(String contactPeerId) async {
    deletedMediaPeerIds.add(contactPeerId);
    operations?.add('media-files:$contactPeerId');
  }
}

void main() {
  group('deleteContactAndMessages use case', () {
    test('deletes messages then contact', () async {
      final contactRepo = FakeContactRepository();
      final messageRepo = FakeMessageRepository();

      await deleteContactAndMessages(
        contactRepo: contactRepo,
        messageRepo: messageRepo,
        peerId: 'peer-1234567890',
      );

      expect(messageRepo.deletedForContact, ['peer-1234567890']);
      expect(contactRepo.deletedPeerIds, ['peer-1234567890']);
    });

    test(
      'TC-361-01b the final purge owner replaces the split message/contact '
      'deletion and the repositories reconcile from the committed purge',
      () async {
        final operations = <String>[];
        final contactRepo = FakePurgeContactRepository(operations: operations);
        final messageRepo = ReconcilingFakeMessageRepository(
          operations: operations,
        );
        final reactionRepo = ReconcilingFakeReactionRepository(
          operations: operations,
        );

        await deleteContactAndMessages(
          contactRepo: contactRepo,
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          peerId: 'peer-purge-12345',
        );

        expect(
          messageRepo.deletedForContact,
          isEmpty,
          reason:
              'messages are never physically purged before the final '
              'serialized transaction',
        );
        expect(
          contactRepo.deletedPeerIds,
          isEmpty,
          reason: 'the split contact delete is replaced by the final owner',
        );
        expect(contactRepo.purgedPeerIds, ['peer-purge-12345']);
        expect(
          operations,
          [
            'reactions:peer-purge-12345',
            'purge:peer-purge-12345',
            'reconcile-messages:peer-purge-12345',
            'reconcile-reactions:peer-purge-12345',
          ],
          reason:
              'early best-effort reaction cleanup precedes the final '
              'purge; cache reconciliation follows the committed purge',
        );
      },
    );

    test('TC-361-01c a reaction applied after the early cleanup is still owned '
        'by the final purge transaction', () async {
      final operations = <String>[];
      final contactRepo = FakePurgeContactRepository(operations: operations);
      final messageRepo = ReconcilingFakeMessageRepository(
        operations: operations,
      );
      final reactionRepo = ReconcilingFakeReactionRepository(
        operations: operations,
      );
      // Interleave: the moment the early sweep runs, a racing apply lands a
      // fresh reaction. Only the final serialized owner may sweep it.
      reactionRepo.onDeleteReactionsForContact = () {
        contactRepo.pendingRowsAtPurge['late-reaction'] = 1;
      };

      await deleteContactAndMessages(
        contactRepo: contactRepo,
        messageRepo: messageRepo,
        reactionRepo: reactionRepo,
        peerId: 'peer-race-12345',
      );

      expect(contactRepo.purgedPeerIds, ['peer-race-12345']);
      expect(
        contactRepo.rowsSeenAtPurge,
        containsPair('late-reaction', 1),
        reason:
            'the final transaction still sees and sweeps the '
            'post-cleanup reaction; nothing survives it',
      );
    });

    test('TC-362-03a deletion converges plural custody without orphaning '
        'shared artifacts', () async {
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);
      const peerId = 'peer-plural-custody';
      const messageId = 'plural-custody-m1';
      const attachmentId = '$messageId-att';
      const t0 = '2026-08-12T09:00:00.000Z';
      final contentHash = 'f9' * 32;
      await fixture.db.insert('contacts', <String, Object?>{
        'peer_id': peerId,
        'public_key': 'pk-$peerId',
        'rendezvous': '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
        'username': 'Plural Custody',
        'signature': 'sig-$peerId',
        'scanned_at': t0,
      });
      await fixture.seedDirectParent(messageId, contactPeerId: peerId);
      DirectMediaBlobCustodyRow blobRow({
        required String attachmentId,
        required DirectMediaBlobCustodyState state,
        String? recipientPeerId,
        String? contactAccountPeerId,
        String? recipientMlKemPublicKey,
        int? expiresAtMs,
        String? custodyRelayPeerId,
      }) => DirectMediaBlobCustodyRow(
        attachmentId: attachmentId,
        messageId: messageId,
        direction: state.direction,
        state: state,
        inboxCustodyIncarnationId: null,
        recipientPeerId: recipientPeerId,
        contactAccountPeerId: contactAccountPeerId,
        recipientMlKemPublicKey: recipientMlKemPublicKey,
        ciphertextRelativePath: recipientPeerId == null
            ? null
            : 'direct_media_blob_custody_v1/${'a' * 64}/$attachmentId.blob',
        contentHash: contentHash,
        ciphertextSize: 4096,
        expiresAtMs: expiresAtMs,
        custodyRelayPeerId: custodyRelayPeerId,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: t0,
        updatedAt: t0,
      );
      // Plural outgoing custody: two exact linked target rows sharing ONE
      // encrypted artifact, plus one incoming ACK obligation.
      await fixture.db.insert(
        kDirectMediaBlobCustodyTable,
        blobRow(
          attachmentId: attachmentId,
          state: DirectMediaBlobCustodyState.outgoingPrepared,
          recipientPeerId: 'plural-custody-transport-a',
          contactAccountPeerId: peerId,
          recipientMlKemPublicKey: 'mlkem-plural-a',
        ).toMap(),
      );
      await fixture.db.insert(
        kDirectMediaBlobCustodyTable,
        blobRow(
          attachmentId: attachmentId,
          state: DirectMediaBlobCustodyState.outgoingStored,
          recipientPeerId: 'plural-custody-transport-b',
          contactAccountPeerId: peerId,
          recipientMlKemPublicKey: 'mlkem-plural-b',
          expiresAtMs: 1900000600000,
          custodyRelayPeerId: 'relay-plural',
        ).toMap(),
      );
      await fixture.db.insert(
        kDirectMediaBlobCustodyTable,
        blobRow(
          attachmentId: 'plural-custody-incoming',
          state: DirectMediaBlobCustodyState.incomingAckPending,
          expiresAtMs: 1900000700000,
          custodyRelayPeerId: 'relay-plural-source',
        ).toMap(),
      );
      final incomingBefore = (await fixture.db.query(
        kDirectMediaBlobCustodyTable,
        where: "direction = 'incoming'",
      )).single;
      final contactRepo = RealDbPurgeContactRepository(fixture.db);

      await deleteContactAndMessages(
        contactRepo: contactRepo,
        messageRepo: fixture.messageRepo,
        peerId: peerId,
        mediaAttachmentRepo: fixture.repo,
      );

      // The purge capability path ran (never the split delete fallback) …
      expect(contactRepo.purgedPeerIds, <String>[peerId]);
      expect(contactRepo.deletedPeerIds, isEmpty);
      // … and the real DB owner transitioned every outgoing linked v114 row
      // before the conversation purge, retaining the shared artifact for the
      // incumbent last-reference cleanup instead of orphaning it.
      final outgoingAfter = await fixture.db.query(
        kDirectMediaBlobCustodyTable,
        where: "direction = 'outgoing'",
        orderBy: 'recipient_peer_id ASC',
      );
      expect(outgoingAfter, hasLength(2));
      for (final row in outgoingAfter) {
        expect(row['state'], 'outgoing_cleanup_pending');
      }
      expect(
        (await fixture.db.query(
          kDirectMediaBlobCustodyTable,
          where: "direction = 'incoming'",
        )).single,
        incomingBefore,
        reason: 'the incoming ACK obligation survives contact deletion',
      );
      expect(
        await fixture.db.query(
          'messages',
          where: 'contact_peer_id = ?',
          whereArgs: const <Object?>[peerId],
        ),
        isEmpty,
      );
      expect(
        await fixture.db.query(
          'contacts',
          where: 'peer_id = ?',
          whereArgs: const <Object?>[peerId],
        ),
        isEmpty,
      );
    });

    test('rethrows errors from message repository', () async {
      final contactRepo = FakeContactRepository();
      final messageRepo = FakeMessageRepository()..shouldThrow = true;

      expect(
        () => deleteContactAndMessages(
          contactRepo: contactRepo,
          messageRepo: messageRepo,
          peerId: 'peer-1234567890',
        ),
        throwsException,
      );
    });

    test('rethrows errors from contact repository', () async {
      final contactRepo = FakeContactRepository()..shouldThrow = true;
      final messageRepo = FakeMessageRepository();

      expect(
        () => deleteContactAndMessages(
          contactRepo: contactRepo,
          messageRepo: messageRepo,
          peerId: 'peer-1234567890',
        ),
        throwsException,
      );
    });

    test(
      'purges related local state before deleting messages and contact',
      () async {
        final operations = <String>[];
        final contactRepo = FakeContactRepository(operations: operations);
        final messageRepo = FakeMessageRepository(operations: operations)
          ..visibleMessages = [
            _message(id: 'visible-1'),
            _message(id: 'visible-2'),
          ]
          ..failedMessages = [_message(id: 'failed-1', status: 'failed')]
          ..unackedMessages = [_message(id: 'unacked-1', status: 'sent')]
          ..sendingMessages = [_message(id: 'sending-1', status: 'sending')];
        final mediaRepo = FakeMediaAttachmentRepository(operations: operations);
        final reactionRepo = FakeReactionRepository(operations: operations);
        final contactRequestRepo = FakeContactRequestRepository(
          operations: operations,
        );
        final introRepo = FakeIntroductionRepository(
          operations: operations,
          introductions: [
            _intro(
              id: 'intro-recipient',
              introducerId: 'peer-introducer',
              recipientId: 'peer-1234567890',
              introducedId: 'peer-other',
            ),
            _intro(
              id: 'intro-introduced',
              introducerId: 'peer-introducer',
              recipientId: 'peer-other',
              introducedId: 'peer-1234567890',
            ),
            _intro(
              id: 'intro-introducer',
              introducerId: 'peer-1234567890',
              recipientId: 'peer-other',
              introducedId: 'peer-third',
            ),
          ],
        );
        final mediaFileManager = FakeMediaFileManager(operations: operations);

        await deleteContactAndMessages(
          contactRepo: contactRepo,
          messageRepo: messageRepo,
          peerId: 'peer-1234567890',
          mediaAttachmentRepo: mediaRepo,
          reactionRepo: reactionRepo,
          mediaFileManager: mediaFileManager,
          contactRequestRepo: contactRequestRepo,
          introductionRepo: introRepo,
        );

        expect(
          mediaFileManager.deletedPendingUploadMessageIds,
          containsAll(<String>[
            'visible-1',
            'visible-2',
            'failed-1',
            'unacked-1',
            'sending-1',
          ]),
        );
        expect(mediaFileManager.deletedMediaPeerIds, ['peer-1234567890']);
        expect(reactionRepo.deletedForContact, ['peer-1234567890']);
        expect(mediaRepo.deletedForContact, ['peer-1234567890']);
        expect(contactRequestRepo.deletedPeerIds, ['peer-1234567890']);
        expect(
          introRepo.deletedIntroductionIds,
          containsAll(<String>[
            'intro-recipient',
            'intro-introduced',
            'intro-introducer',
          ]),
        );
        expect(messageRepo.deletedForContact, ['peer-1234567890']);
        expect(contactRepo.deletedPeerIds, ['peer-1234567890']);
        expect(
          operations,
          containsAllInOrder([
            'media-files:peer-1234567890',
            'reactions:peer-1234567890',
            'attachments:peer-1234567890',
            'intro:intro-recipient',
            'intro:intro-introduced',
            'intro:intro-introducer',
            'request:peer-1234567890',
            'messages:peer-1234567890',
            'contact:peer-1234567890',
          ]),
        );
      },
    );

    test(
      'contact deletion preserves same id group and unresolved media',
      () async {
        // 228 TC-228-05B: `messages.id` and `group_messages.id` are
        // independent table-local keys, so the SAME message id can legally
        // exist in both lanes. Contact cleanup runs against the REAL
        // repository (production-registry schema) and must delete ONLY the
        // contact's direct-owned rows — the same-ID group sibling and the
        // legacy 'unresolved' row survive byte-identical.
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);

        const peerId = 'peer-1234567890';
        const collidingMessageId = 'msg-collide';
        await fixture.seedDirectParent(
          collidingMessageId,
          contactPeerId: peerId,
        );
        await fixture.seedGroupParent(collidingMessageId);

        MediaAttachment makeCollidingAttachment(String id) => MediaAttachment(
          id: id,
          messageId: collidingMessageId,
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-04-01T00:00:00.000Z',
        );

        await fixture.repo.saveAttachment(
          makeCollidingAttachment('att-direct'),
          owner: MediaOwnerLane.direct,
        );
        await fixture.repo.saveAttachment(
          makeCollidingAttachment('att-group'),
          owner: MediaOwnerLane.group,
        );
        // Legacy row: addressable through NO lane, must survive cleanup.
        await fixture.db.insert('media_attachments', {
          'id': 'att-unresolved',
          'message_id': collidingMessageId,
          'owner_lane': kMediaOwnerLaneUnresolved,
          'mime': 'image/jpeg',
          'size': 2048,
          'media_type': 'image',
          'download_status': 'done',
          'created_at': '2026-04-01T00:00:00.000Z',
        });

        final groupRowBefore = await fixture.rawAttachmentRow('att-group');
        final unresolvedRowBefore = await fixture.rawAttachmentRow(
          'att-unresolved',
        );
        expect(groupRowBefore, isNotNull);
        expect(unresolvedRowBefore, isNotNull);

        await deleteContactAndMessages(
          contactRepo: FakeContactRepository(),
          messageRepo: FakeMessageRepository(),
          peerId: peerId,
          mediaAttachmentRepo: fixture.repo,
        );

        expect(await fixture.rawAttachmentRow('att-direct'), isNull);
        expect(await fixture.rawAttachmentRow('att-group'), groupRowBefore);
        expect(
          await fixture.rawAttachmentRow('att-unresolved'),
          unresolvedRowBefore,
        );
      },
    );

    test(
      'private contact deletion terminalizes and cleans before parent removal',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const peerId = 'peer-private-contact';
        const messageId = 'private-contact-message';
        const attachmentId = 'private-contact-attachment';
        await fixture.seedDirectParent(messageId, contactPeerId: peerId);
        await fixture.db.update(
          'messages',
          <String, Object?>{
            'status': 'sending',
            'is_incoming': 0,
            'private_media_policy_version': 1,
            'private_media_mode': 'view_once',
            'private_media_state': 'available',
            'private_media_received_at_ms': 1000,
            'private_media_revealed_at_ms': null,
            'private_media_clock_high_water_ms': 1000,
          },
          where: 'id = ?',
          whereArgs: const <Object?>[messageId],
        );
        await fixture.repo.saveAttachment(
          MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 4,
            mediaType: 'image',
            localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-07-20T00:00:00.000Z',
            ownerLane: MediaOwnerLane.direct,
          ),
          owner: MediaOwnerLane.direct,
        );
        await fixture.db.update(
          'messages',
          <String, Object?>{
            'private_media_state': 'viewing',
            'private_media_revealed_at_ms': 1100,
            'private_media_clock_high_water_ms': 1100,
          },
          where: 'id = ?',
          whereArgs: const <Object?>[messageId],
        );
        final contactRepo = FakeContactRepository();
        final manager = shared.FakeMediaFileManager();

        await deleteContactAndMessages(
          contactRepo: contactRepo,
          messageRepo: fixture.messageRepo,
          peerId: peerId,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: manager,
        );

        expect(await fixture.rawAttachmentRow(attachmentId), isNull);
        expect(await fixture.messageRepo.getMessage(messageId), isNull);
        expect(contactRepo.deletedPeerIds, <String>[peerId]);
        expect(manager.deletedContactIds, <String>[peerId]);
      },
    );

    test(
      'private contact deletion preflights every transfer before any hide',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const peerId = 'peer-private-contact-transfer';
        const messageIds = <String>[
          'private-contact-transfer-first',
          'private-contact-transfer-second',
        ];
        const attachmentIds = <String>[
          'private-contact-transfer-first-att',
          'private-contact-transfer-second-att',
        ];
        for (var index = 0; index < messageIds.length; index++) {
          final messageId = messageIds[index];
          final attachmentId = attachmentIds[index];
          await fixture.seedDirectParent(
            messageId,
            contactPeerId: peerId,
            timestamp: '2026-07-20T00:00:0$index.000Z',
          );
          await fixture.db.update(
            'messages',
            <String, Object?>{
              'status': 'sending',
              'is_incoming': 0,
              'private_media_policy_version': 1,
              'private_media_mode': 'protected',
              'private_media_state': 'available',
              'private_media_received_at_ms': 1000,
              'private_media_clock_high_water_ms': 1000,
            },
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
          );
          if (index == 0) {
            await fixture.repo.saveAttachment(
              MediaAttachment(
                id: attachmentId,
                messageId: messageId,
                mime: 'image/jpeg',
                size: 4,
                mediaType: 'image',
                localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
                downloadStatus: 'upload_pending',
                createdAt: '2026-07-20T00:00:00.000Z',
                ownerLane: MediaOwnerLane.direct,
              ),
              owner: MediaOwnerLane.direct,
            );
          }
        }
        final transferToken = directPrivateMediaTransferRegistry.tryBegin(
          attachmentIds.last,
          messageId: messageIds.last,
        );
        expect(transferToken, isNotNull);
        addTearDown(
          () => directPrivateMediaTransferRegistry.end(
            attachmentIds.last,
            transferToken!,
          ),
        );
        final contactRepo = FakeContactRepository();
        final pendingDeletes = <String>[];
        final manager = shared.FakeMediaFileManager()
          ..onDeletePendingUploadDir = pendingDeletes.add;

        await expectLater(
          deleteContactAndMessages(
            contactRepo: contactRepo,
            messageRepo: fixture.messageRepo,
            peerId: peerId,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: manager,
          ),
          throwsStateError,
        );

        for (var index = 0; index < messageIds.length; index++) {
          final message = await fixture.messageRepo.getMessage(
            messageIds[index],
          );
          expect(message, isNotNull);
          expect(message!.hiddenAt, isNull);
          expect(
            await fixture.rawAttachmentRow(attachmentIds[index]),
            index == 0 ? isNotNull : isNull,
          );
        }
        expect(contactRepo.deletedPeerIds, isEmpty);
        expect(manager.deletedContactIds, isEmpty);
        expect(pendingDeletes, isEmpty);
      },
    );

    test(
      'empty inventory rechecks a late private parent and transfer under the global lock',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const peerId = 'peer-late-private-contact';
        const messageId = 'late-private-contact-message';
        const attachmentId = 'late-private-contact-attachment';
        final contactRepo = FakeContactRepository();
        final pendingDeletes = <String>[];
        final manager = shared.FakeMediaFileManager()
          ..onDeletePendingUploadDir = pendingDeletes.add;

        expect(
          await fixture.messageRepo.getMessagesForContact(peerId),
          isEmpty,
        );

        final lockEntered = Completer<void>();
        final releaseLock = Completer<void>();
        final lockBlocker = fixture.repo.lifecycleLock.synchronizedAll(
          () async {
            lockEntered.complete();
            await releaseLock.future;
          },
        );
        addTearDown(() async {
          if (!releaseLock.isCompleted) {
            releaseLock.complete();
          }
          await lockBlocker;
        });
        await lockEntered.future;

        var deletionSettled = false;
        final deletion = deleteContactAndMessages(
          contactRepo: contactRepo,
          messageRepo: fixture.messageRepo,
          peerId: peerId,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: manager,
        ).whenComplete(() => deletionSettled = true);
        await Future<void>.delayed(Duration.zero);
        expect(deletionSettled, isFalse);

        // This parent and its transfer appear only after contact deletion has
        // started. Inventory outside the global lock would miss both, then
        // broad purges could erase their only durable custody authority.
        await fixture.seedDirectParent(messageId, contactPeerId: peerId);
        await fixture.db.update(
          'messages',
          <String, Object?>{
            'status': 'sending',
            'is_incoming': 0,
            'private_media_policy_version': 1,
            'private_media_mode': 'protected',
            'private_media_state': 'available',
            'private_media_received_at_ms': 1000,
            'private_media_revealed_at_ms': null,
            'private_media_terminal_at_ms': null,
            'private_media_clock_high_water_ms': 1000,
          },
          where: 'id = ?',
          whereArgs: const <Object?>[messageId],
        );
        final pendingRelative =
            MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: 'image/jpeg',
            );
        final pendingFile = File(
          p.join(shared.FakeMediaFileManager.testRootPath, pendingRelative),
        );
        await pendingFile.parent.create(recursive: true);
        await pendingFile.writeAsBytes(const <int>[1, 2, 3, 4]);
        addTearDown(() async {
          if (await pendingFile.exists()) {
            await pendingFile.delete();
          }
        });
        final secureKeyName = mediaAttachmentEncryptionKeyStoreName(
          attachmentId,
        );
        await fixture.secureKeyStore.write(secureKeyName, 'late-secret-key');
        final lateAttachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 4,
          mediaType: 'image',
          localPath: pendingRelative,
          downloadStatus: 'upload_pending',
          createdAt: '2026-07-20T00:00:00.000Z',
          encryptionKeyBase64: secureStoreReferenceForKey(secureKeyName),
          encryptionNonce: 'bGF0ZS1ub25jZQ==',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.direct,
        );
        await fixture.db.insert('media_attachments', lateAttachment.toMap());
        final transferToken = directPrivateMediaTransferRegistry.tryBegin(
          attachmentId,
          messageId: messageId,
        );
        expect(transferToken, isNotNull);
        addTearDown(
          () => directPrivateMediaTransferRegistry.end(
            attachmentId,
            transferToken!,
          ),
        );

        final deletionExpectation = expectLater(deletion, throwsStateError);
        releaseLock.complete();
        await deletionExpectation;
        await lockBlocker;

        final parent = await fixture.messageRepo.getMessage(messageId);
        expect(parent, isNotNull);
        expect(parent!.hiddenAt, isNull);
        expect(await fixture.rawAttachmentRow(attachmentId), isNotNull);
        expect(await pendingFile.exists(), isTrue);
        expect(
          await fixture.secureKeyStore.read(secureKeyName),
          'late-secret-key',
        );
        expect(contactRepo.deletedPeerIds, isEmpty);
        expect(manager.deletedContactIds, isEmpty);
        expect(pendingDeletes, isEmpty);
      },
    );

    test(
      'first private pending-row insert queues behind contact deletion and compensates after refusal',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const peerId = 'peer-first-row-contact-race';
        const messageId = 'first-row-contact-race-message';
        const attachmentId = 'first-row-contact-race-attachment';
        await fixture.seedDirectParent(messageId, contactPeerId: peerId);
        await fixture.db.update(
          'messages',
          <String, Object?>{
            'status': 'sending',
            'is_incoming': 0,
            'private_media_policy_version': 1,
            'private_media_mode': 'protected',
            'private_media_state': 'available',
            'private_media_received_at_ms': 1000,
            'private_media_revealed_at_ms': null,
            'private_media_terminal_at_ms': null,
            'private_media_clock_high_water_ms': 1000,
          },
          where: 'id = ?',
          whereArgs: const <Object?>[messageId],
        );

        final reactionRepo = BarrierReactionRepository();
        addTearDown(() {
          if (!reactionRepo.release.isCompleted) {
            reactionRepo.release.complete();
          }
        });
        final pendingDeletes = <String>[];
        final manager = shared.FakeMediaFileManager()
          ..onDeletePendingUploadDir = pendingDeletes.add;
        final contactRepo = FakeContactRepository();
        final deletion = deleteContactAndMessages(
          contactRepo: contactRepo,
          messageRepo: fixture.messageRepo,
          peerId: peerId,
          mediaAttachmentRepo: fixture.repo,
          reactionRepo: reactionRepo,
          mediaFileManager: manager,
        );
        await reactionRepo.entered.future;
        expect(pendingDeletes, contains(messageId));

        // Seed the copied file only after contact deletion has completed its
        // own pending-directory sweep, while it still owns the global lock.
        final pendingRelative =
            MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: 'image/jpeg',
            );
        final pendingFile = File(
          p.join(shared.FakeMediaFileManager.testRootPath, pendingRelative),
        );
        await pendingFile.parent.create(recursive: true);
        await pendingFile.writeAsBytes(const <int>[1, 2, 3, 4]);
        addTearDown(() async {
          if (await pendingFile.exists()) {
            await pendingFile.delete();
          }
        });
        final attachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 4,
          mediaType: 'image',
          localPath: pendingRelative,
          downloadStatus: 'upload_pending',
          createdAt: '2026-07-20T00:00:00.000Z',
          ownerLane: MediaOwnerLane.direct,
        );

        var preparationSettled = false;
        final preparation = fixture.repo
            .prepareOutgoingDirectPrivatePendingAttachments(<MediaAttachment>[
              attachment,
            ])
            .whenComplete(() => preparationSettled = true);
        await Future<void>.delayed(Duration.zero);
        expect(preparationSettled, isFalse);
        expect(await fixture.rawAttachmentRow(attachmentId), isNull);

        reactionRepo.release.complete();
        await deletion;
        final outcome = await preparation;
        expect(outcome, OutgoingDirectPrivatePendingPreparationOutcome.refused);

        // The typed refusal is the caller's authority to remove exactly the
        // convention-owned file copied before it attempted publication.
        await manager.deleteOwnedPendingUploadFilesForMessage(
          messageId: messageId,
          storedPaths: <String>[pendingRelative],
        );

        expect(contactRepo.deletedPeerIds, <String>[peerId]);
        expect(await fixture.messageRepo.getMessage(messageId), isNull);
        expect(await fixture.rawAttachmentRow(attachmentId), isNull);
        expect(await pendingFile.exists(), isFalse);
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(attachmentId),
          ),
          isFalse,
        );
      },
    );
  });
}

ConversationMessage _message({
  required String id,
  String status = 'delivered',
}) {
  const peerId = 'peer-1234567890';
  return ConversationMessage(
    id: id,
    contactPeerId: peerId,
    senderPeerId: peerId,
    text: 'hello',
    timestamp: '2026-04-01T00:00:00.000Z',
    status: status,
    isIncoming: status == 'delivered',
    createdAt: '2026-04-01T00:00:00.000Z',
  );
}

IntroductionModel _intro({
  required String id,
  required String introducerId,
  required String recipientId,
  required String introducedId,
}) {
  return IntroductionModel(
    id: id,
    introducerId: introducerId,
    recipientId: recipientId,
    introducedId: introducedId,
    createdAt: '2026-04-01T00:00:00.000Z',
  );
}
