import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
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
  Future<void> saveAttachment(MediaAttachment attachment) async {}

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId,
  ) async => const [];

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  ) async => const {};

  @override
  Future<void> updateLocalPath(String id, String localPath) async {}

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}

  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async => 0;

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async {
    deletedForContact.add(contactPeerId);
    operations?.add('attachments:$contactPeerId');
    return 3;
  }

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId,
  ) async => 0;

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => const [];

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments() async => const [];
}

class FakeReactionRepository implements ReactionRepository {
  final List<String> deletedForContact = [];
  final List<String>? operations;

  FakeReactionRepository({this.operations});

  @override
  Future<void> saveReaction(MessageReaction reaction) async {}

  @override
  Future<List<MessageReaction>> getReactionsForMessage(
    String messageId,
  ) async => const [];

  @override
  Future<Map<String, List<MessageReaction>>> getReactionsForMessages(
    List<String> messageIds,
  ) async => const {};

  @override
  Future<int> removeReaction(String messageId, String senderPeerId) async => 0;

  @override
  Future<int> deleteReactionsForMessage(String messageId) async => 0;

  @override
  Future<int> deleteReactionsForContact(String contactPeerId) async {
    deletedForContact.add(contactPeerId);
    operations?.add('reactions:$contactPeerId');
    return 4;
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
