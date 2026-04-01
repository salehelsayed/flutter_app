import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

// -- Fakes (same pattern as handle_incoming_chat_message_use_case_test.dart) --

class _FakeContactRepository implements ContactRepository {
  final Map<String, ContactModel> _contacts = {};

  void seedContact(ContactModel contact) {
    _contacts[contact.peerId] = contact;
  }

  @override
  Future<ContactModel?> getContact(String peerId) async => _contacts[peerId];
  @override
  Future<bool> contactExists(String peerId) async =>
      _contacts.containsKey(peerId);
  @override
  Future<void> addContact(ContactModel contact) async {
    _contacts[contact.peerId] = contact;
  }

  @override
  Future<List<ContactModel>> getAllContacts() async =>
      _contacts.values.toList();
  @override
  Future<void> deleteContact(String peerId) async {
    _contacts.remove(peerId);
  }

  @override
  Future<int> getContactCount() async => _contacts.length;
  @override
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<List<ContactModel>> getActiveContacts() async =>
      _contacts.values.toList();
  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
  @override
  Future<void> dismissIntroBanner(String peerId) async {}
  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

class _FakeMessageRepository implements MessageRepository {
  final List<ConversationMessage> saved = [];

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    saved.add(message);
  }

  @override
  Future<bool> messageExists(String id) async => false;
  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async =>
      [];
  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async =>
      null;
  @override
  Future<void> updateMessageStatus(String id, String status) async {}
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
  Future<int> deleteMessagesForContact(String contactPeerId) async => 0;
  @override
  Future<int> deleteMessage(String id) async => 0;
  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async =>
      [];
  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async => [];
  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async =>
      [];
  @override
  Future<ConversationMessage?> getMessage(String id) async => null;
  @override
  Future<int> recoverStuckSendingMessages({required Duration olderThan}) async => 0;
  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {}
  @override
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  }) async => [];
  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async => [];
  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async => 0;
}

class _FakeMediaAttachmentRepository implements MediaAttachmentRepository {
  final List<MediaAttachment> saved = [];

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {
    saved.add(attachment);
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId,
  ) async {
    return saved.where((a) => a.messageId == messageId).toList();
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  ) async =>
      {};
  @override
  Future<void> updateLocalPath(String id, String localPath) async {}
  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}
  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async => 0;
  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;
  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId,
  ) async => 0;
  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => [];

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments() async => [];
}

void main() {
  group('handleIncomingChatMessage — media hydration on returned message', () {
    late _FakeMessageRepository messageRepo;
    late _FakeContactRepository contactRepo;
    late _FakeMediaAttachmentRepository mediaAttachmentRepo;

    setUp(() {
      messageRepo = _FakeMessageRepository();
      contactRepo = _FakeContactRepository();
      mediaAttachmentRepo = _FakeMediaAttachmentRepository();

      // Seed the sender as a known contact
      contactRepo.seedContact(ContactModel(
        peerId: 'peer-sender',
        publicKey: 'pk',
        rendezvous: '/relay',
        username: 'Sender',
        signature: 'sig',
        scannedAt: '2026-01-01T00:00:00.000Z',
      ));
    });

    test('returned message carries image attachment from wire payload',
        () async {
      final wireJson = '{"type":"chat_message","version":"1","payload":{'
          '"id":"msg-media-001","text":"","senderPeerId":"peer-sender",'
          '"senderUsername":"Sender","timestamp":"2026-03-23T12:00:00.000Z",'
          '"media":[{"id":"blob-img-001","mime":"image/jpeg","size":204800,'
          '"mediaType":"image","width":1920,"height":1080}]}}';

      final (result, message, _) = await handleIncomingChatMessage(
        message: ChatMessage(
          from: 'peer-sender',
          to: 'peer-self',
          content: wireJson,
          timestamp: '2026-03-23T12:00:00.000Z',
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      expect(result, HandleChatMessageResult.chatMessage);
      expect(message, isNotNull);

      // KEY ASSERTION: media must be populated on the returned message
      expect(message!.media, hasLength(1),
          reason:
              'Returned ConversationMessage must carry media from wire payload');
      expect(message.media.first.mediaType, 'image');
      expect(message.media.first.messageId, 'msg-media-001');
    });

    test('returned message carries audio attachment from wire payload',
        () async {
      final wireJson = '{"type":"chat_message","version":"1","payload":{'
          '"id":"msg-voice-001","text":"","senderPeerId":"peer-sender",'
          '"senderUsername":"Sender","timestamp":"2026-03-23T12:00:00.000Z",'
          '"media":[{"id":"blob-audio-001","mime":"audio/aac","size":48000,'
          '"mediaType":"audio","durationMs":5200}]}}';

      final (result, message, _) = await handleIncomingChatMessage(
        message: ChatMessage(
          from: 'peer-sender',
          to: 'peer-self',
          content: wireJson,
          timestamp: '2026-03-23T12:00:00.000Z',
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      expect(result, HandleChatMessageResult.chatMessage);
      expect(message, isNotNull);
      expect(message!.media, hasLength(1));
      expect(message.media.first.mediaType, 'audio');
      expect(message.media.first.durationMs, 5200);
    });

    test('text-only message returns empty media list (no regression)',
        () async {
      final wireJson = '{"type":"chat_message","version":"1","payload":{'
          '"id":"msg-text-001","text":"Hello","senderPeerId":"peer-sender",'
          '"senderUsername":"Sender","timestamp":"2026-03-23T12:00:00.000Z"}}';

      final (result, message, _) = await handleIncomingChatMessage(
        message: ChatMessage(
          from: 'peer-sender',
          to: 'peer-self',
          content: wireJson,
          timestamp: '2026-03-23T12:00:00.000Z',
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      expect(result, HandleChatMessageResult.chatMessage);
      expect(message, isNotNull);
      expect(message!.media, isEmpty,
          reason: 'Text-only messages must still have empty media list');
    });

    test(
        'media message without mediaAttachmentRepo returns empty media (graceful)',
        () async {
      final wireJson = '{"type":"chat_message","version":"1","payload":{'
          '"id":"msg-no-repo-001","text":"","senderPeerId":"peer-sender",'
          '"senderUsername":"Sender","timestamp":"2026-03-23T12:00:00.000Z",'
          '"media":[{"id":"blob-x","mime":"image/png","size":100}]}}';

      // No mediaAttachmentRepo — attachments not persisted, not hydrated
      final (result, message, _) = await handleIncomingChatMessage(
        message: ChatMessage(
          from: 'peer-sender',
          to: 'peer-self',
          content: wireJson,
          timestamp: '2026-03-23T12:00:00.000Z',
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        mediaAttachmentRepo: null,
      );

      expect(result, HandleChatMessageResult.chatMessage);
      expect(message, isNotNull);
      // When mediaAttachmentRepo is null, attachments are not persisted
      // and media is not hydrated — this is acceptable for legacy paths
      expect(message!.media, isEmpty);
    });
  });
}
