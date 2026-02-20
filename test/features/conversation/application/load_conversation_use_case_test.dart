import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

// -- Fake Message Repository --
class FakeMessageRepository implements MessageRepository {
  final Map<String, List<ConversationMessage>> messagesByContact;

  FakeMessageRepository({this.messagesByContact = const {}});

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
      String contactPeerId) async {
    return messagesByContact[contactPeerId] ?? [];
  }

  @override
  Future<void> saveMessage(ConversationMessage message) async {}

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
      String contactPeerId) async {
    return null;
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {}

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
  Future<int> deleteMessagesForContact(String contactPeerId) async => 0;

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    final all = messagesByContact[contactPeerId] ?? [];
    var filtered = all;
    if (beforeTimestamp != null) {
      filtered = all.where((m) => m.timestamp.compareTo(beforeTimestamp) < 0).toList();
    }
    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final page = filtered.take(limit).toList();
    return page.reversed.toList();
  }

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async => [];
}

// -- Fake Media Attachment Repository --
class FakeMediaAttachmentRepository implements MediaAttachmentRepository {
  final Map<String, List<MediaAttachment>> mediaByMessage;

  FakeMediaAttachmentRepository({this.mediaByMessage = const {}});

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {}

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
      String messageId) async {
    return mediaByMessage[messageId] ?? [];
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
      List<String> messageIds) async {
    final result = <String, List<MediaAttachment>>{};
    for (final id in messageIds) {
      final media = mediaByMessage[id];
      if (media != null && media.isNotEmpty) {
        result[id] = media;
      }
    }
    return result;
  }

  @override
  Future<void> updateLocalPath(String id, String localPath) async {}

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}

  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async => 0;

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => [];
}

void main() {
  group('loadConversation', () {
    test('returns empty list when no messages for contact', () async {
      final repo = FakeMessageRepository();

      final result = await loadConversation(
        messageRepo: repo,
        contactPeerId: 'nonexistent-peer',
      );

      expect(result, isEmpty);
    });

    test('returns messages for existing contact', () async {
      final messages = [
        ConversationMessage(
          id: 'msg-1',
          contactPeerId: 'contact-A',
          senderPeerId: 'contact-A',
          text: 'First message',
          timestamp: '2026-02-09T10:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T10:00:01.000Z',
        ),
        ConversationMessage(
          id: 'msg-2',
          contactPeerId: 'contact-A',
          senderPeerId: 'my-peer',
          text: 'Reply',
          timestamp: '2026-02-09T10:01:00.000Z',
          status: 'sent',
          isIncoming: false,
          createdAt: '2026-02-09T10:01:01.000Z',
        ),
      ];

      final repo = FakeMessageRepository(
        messagesByContact: {'contact-A': messages},
      );

      final result = await loadConversation(
        messageRepo: repo,
        contactPeerId: 'contact-A',
      );

      expect(result.length, 2);
      expect(result[0].id, 'msg-1');
      expect(result[1].id, 'msg-2');
    });
  });

  group('loadConversationPage', () {
    test('returns most recent page when no cursor', () async {
      final messages = [
        for (var i = 1; i <= 5; i++)
          ConversationMessage(
            id: 'msg-$i',
            contactPeerId: 'contact-A',
            senderPeerId: 'contact-A',
            text: 'Message $i',
            timestamp: '2026-02-09T${10 + i}:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-02-09T${10 + i}:00:01.000Z',
          ),
      ];

      final repo = FakeMessageRepository(
        messagesByContact: {'contact-A': messages},
      );

      final result = await loadConversationPage(
        messageRepo: repo,
        contactPeerId: 'contact-A',
        pageSize: 3,
      );

      expect(result.length, 3);
      // Most recent 3 in ASC order: msg-3, msg-4, msg-5
      expect(result[0].id, 'msg-3');
      expect(result[1].id, 'msg-4');
      expect(result[2].id, 'msg-5');
    });

    test('returns older page with cursor', () async {
      final messages = [
        for (var i = 1; i <= 5; i++)
          ConversationMessage(
            id: 'msg-$i',
            contactPeerId: 'contact-A',
            senderPeerId: 'contact-A',
            text: 'Message $i',
            timestamp: '2026-02-09T${10 + i}:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-02-09T${10 + i}:00:01.000Z',
          ),
      ];

      final repo = FakeMessageRepository(
        messagesByContact: {'contact-A': messages},
      );

      // Before msg-3's timestamp (13:00) → should get msg-1, msg-2
      final result = await loadConversationPage(
        messageRepo: repo,
        contactPeerId: 'contact-A',
        pageSize: 3,
        beforeTimestamp: '2026-02-09T13:00:00.000Z',
      );

      expect(result.length, 2);
      expect(result[0].id, 'msg-1');
      expect(result[1].id, 'msg-2');
    });

    test('returns empty list when no more messages', () async {
      final messages = [
        ConversationMessage(
          id: 'msg-1',
          contactPeerId: 'contact-A',
          senderPeerId: 'contact-A',
          text: 'Only message',
          timestamp: '2026-02-09T11:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T11:00:01.000Z',
        ),
      ];

      final repo = FakeMessageRepository(
        messagesByContact: {'contact-A': messages},
      );

      // Cursor older than all messages
      final result = await loadConversationPage(
        messageRepo: repo,
        contactPeerId: 'contact-A',
        pageSize: 3,
        beforeTimestamp: '2026-02-09T10:00:00.000Z',
      );

      expect(result, isEmpty);
    });
  });

  group('loadConversation with media', () {
    final messagesWithMedia = [
      ConversationMessage(
        id: 'msg-1',
        contactPeerId: 'contact-A',
        senderPeerId: 'contact-A',
        text: 'Photo message',
        timestamp: '2026-02-09T10:00:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-02-09T10:00:01.000Z',
      ),
      ConversationMessage(
        id: 'msg-2',
        contactPeerId: 'contact-A',
        senderPeerId: 'my-peer',
        text: 'Text only reply',
        timestamp: '2026-02-09T10:01:00.000Z',
        status: 'sent',
        isIncoming: false,
        createdAt: '2026-02-09T10:01:01.000Z',
      ),
    ];

    const attachmentForMsg1 = MediaAttachment(
      id: 'blob-001',
      messageId: 'msg-1',
      mime: 'image/jpeg',
      size: 245000,
      mediaType: 'image',
      width: 1920,
      height: 1080,
      downloadStatus: 'pending',
      createdAt: '2026-02-09T10:00:00.000Z',
    );

    test('attaches media to messages via batch-load', () async {
      final messageRepo = FakeMessageRepository(
        messagesByContact: {'contact-A': messagesWithMedia},
      );
      final mediaRepo = FakeMediaAttachmentRepository(
        mediaByMessage: {
          'msg-1': [attachmentForMsg1],
        },
      );

      final result = await loadConversation(
        messageRepo: messageRepo,
        contactPeerId: 'contact-A',
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result.length, 2);
      // msg-1 should have media attached
      expect(result[0].media.length, 1);
      expect(result[0].media[0].id, 'blob-001');
      expect(result[0].media[0].mime, 'image/jpeg');
      // msg-2 should have empty media
      expect(result[1].media, isEmpty);
    });

    test('returns messages without media when repo is null', () async {
      final messageRepo = FakeMessageRepository(
        messagesByContact: {'contact-A': messagesWithMedia},
      );

      final result = await loadConversation(
        messageRepo: messageRepo,
        contactPeerId: 'contact-A',
        mediaAttachmentRepo: null,
      );

      expect(result.length, 2);
      expect(result[0].media, isEmpty);
      expect(result[1].media, isEmpty);
    });

    test('returns messages as-is when no media exists', () async {
      final messageRepo = FakeMessageRepository(
        messagesByContact: {'contact-A': messagesWithMedia},
      );
      final mediaRepo = FakeMediaAttachmentRepository();

      final result = await loadConversation(
        messageRepo: messageRepo,
        contactPeerId: 'contact-A',
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result.length, 2);
      expect(result[0].media, isEmpty);
      expect(result[1].media, isEmpty);
    });

    test('handles empty message list gracefully', () async {
      final messageRepo = FakeMessageRepository();
      final mediaRepo = FakeMediaAttachmentRepository();

      final result = await loadConversation(
        messageRepo: messageRepo,
        contactPeerId: 'nonexistent',
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isEmpty);
    });
  });

  group('loadConversationPage with media', () {
    test('attaches media to paged messages', () async {
      final messages = [
        for (var i = 1; i <= 3; i++)
          ConversationMessage(
            id: 'msg-$i',
            contactPeerId: 'contact-A',
            senderPeerId: 'contact-A',
            text: 'Message $i',
            timestamp: '2026-02-09T${10 + i}:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-02-09T${10 + i}:00:01.000Z',
          ),
      ];

      final messageRepo = FakeMessageRepository(
        messagesByContact: {'contact-A': messages},
      );
      final mediaRepo = FakeMediaAttachmentRepository(
        mediaByMessage: {
          'msg-2': [
            const MediaAttachment(
              id: 'blob-page',
              messageId: 'msg-2',
              mime: 'video/mp4',
              size: 5000000,
              mediaType: 'video',
              downloadStatus: 'pending',
              createdAt: '2026-02-09T12:00:00.000Z',
            ),
          ],
        },
      );

      final result = await loadConversationPage(
        messageRepo: messageRepo,
        contactPeerId: 'contact-A',
        pageSize: 10,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result.length, 3);
      // msg-1 has no media
      expect(result[0].media, isEmpty);
      // msg-2 has media
      expect(result[1].media.length, 1);
      expect(result[1].media[0].id, 'blob-page');
      // msg-3 has no media
      expect(result[2].media, isEmpty);
    });
  });

  group('path resolution with mediaFileManager', () {
    late _FakeMediaFileManager fakeFileManager;

    setUp(() {
      fakeFileManager = _FakeMediaFileManager('/app/Documents');
    });

    test('resolves relative paths to absolute in loadConversation', () async {
      final messageRepo = FakeMessageRepository(
        messagesByContact: {
          'contact-A': [
            ConversationMessage(
              id: 'msg-1',
              contactPeerId: 'contact-A',
              senderPeerId: 'contact-A',
              text: 'Photo',
              timestamp: '2026-02-09T10:00:00.000Z',
              status: 'delivered',
              isIncoming: true,
              createdAt: '2026-02-09T10:00:01.000Z',
            ),
          ],
        },
      );
      final mediaRepo = FakeMediaAttachmentRepository(
        mediaByMessage: {
          'msg-1': [
            const MediaAttachment(
              id: 'blob-001',
              messageId: 'msg-1',
              mime: 'image/jpeg',
              size: 245000,
              mediaType: 'image',
              localPath: 'media/contact-A/blob-001.jpg', // relative path in DB
              downloadStatus: 'done',
              createdAt: '2026-02-09T10:00:00.000Z',
            ),
          ],
        },
      );

      final result = await loadConversation(
        messageRepo: messageRepo,
        contactPeerId: 'contact-A',
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fakeFileManager,
      );

      expect(result.length, 1);
      expect(result[0].media.length, 1);
      // Path should be resolved to absolute
      expect(result[0].media[0].localPath, '/app/Documents/media/contact-A/blob-001.jpg');
    });

    test('resolves relative paths in loadConversationPage', () async {
      final messageRepo = FakeMessageRepository(
        messagesByContact: {
          'contact-A': [
            ConversationMessage(
              id: 'msg-1',
              contactPeerId: 'contact-A',
              senderPeerId: 'contact-A',
              text: 'Photo',
              timestamp: '2026-02-09T10:00:00.000Z',
              status: 'delivered',
              isIncoming: true,
              createdAt: '2026-02-09T10:00:01.000Z',
            ),
          ],
        },
      );
      final mediaRepo = FakeMediaAttachmentRepository(
        mediaByMessage: {
          'msg-1': [
            const MediaAttachment(
              id: 'blob-001',
              messageId: 'msg-1',
              mime: 'image/jpeg',
              size: 245000,
              mediaType: 'image',
              localPath: 'media/contact-A/blob-001.jpg',
              downloadStatus: 'done',
              createdAt: '2026-02-09T10:00:00.000Z',
            ),
          ],
        },
      );

      final result = await loadConversationPage(
        messageRepo: messageRepo,
        contactPeerId: 'contact-A',
        pageSize: 50,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fakeFileManager,
      );

      expect(result.length, 1);
      expect(result[0].media[0].localPath, '/app/Documents/media/contact-A/blob-001.jpg');
    });

    test('resolves legacy absolute paths with /media/ segment', () async {
      final messageRepo = FakeMessageRepository(
        messagesByContact: {
          'contact-A': [
            ConversationMessage(
              id: 'msg-1',
              contactPeerId: 'contact-A',
              senderPeerId: 'contact-A',
              text: 'Photo',
              timestamp: '2026-02-09T10:00:00.000Z',
              status: 'delivered',
              isIncoming: true,
              createdAt: '2026-02-09T10:00:01.000Z',
            ),
          ],
        },
      );
      final mediaRepo = FakeMediaAttachmentRepository(
        mediaByMessage: {
          'msg-1': [
            const MediaAttachment(
              id: 'blob-001',
              messageId: 'msg-1',
              mime: 'image/jpeg',
              size: 245000,
              mediaType: 'image',
              // Legacy absolute path from old iOS container UUID
              localPath: '/old-uuid/Documents/media/contact-A/blob-001.jpg',
              downloadStatus: 'done',
              createdAt: '2026-02-09T10:00:00.000Z',
            ),
          ],
        },
      );

      final result = await loadConversation(
        messageRepo: messageRepo,
        contactPeerId: 'contact-A',
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fakeFileManager,
      );

      expect(result[0].media[0].localPath,
          '/app/Documents/media/contact-A/blob-001.jpg');
    });

    test('does not resolve when mediaFileManager is null', () async {
      final messageRepo = FakeMessageRepository(
        messagesByContact: {
          'contact-A': [
            ConversationMessage(
              id: 'msg-1',
              contactPeerId: 'contact-A',
              senderPeerId: 'contact-A',
              text: 'Photo',
              timestamp: '2026-02-09T10:00:00.000Z',
              status: 'delivered',
              isIncoming: true,
              createdAt: '2026-02-09T10:00:01.000Z',
            ),
          ],
        },
      );
      final mediaRepo = FakeMediaAttachmentRepository(
        mediaByMessage: {
          'msg-1': [
            const MediaAttachment(
              id: 'blob-001',
              messageId: 'msg-1',
              mime: 'image/jpeg',
              size: 245000,
              mediaType: 'image',
              localPath: 'media/contact-A/blob-001.jpg',
              downloadStatus: 'done',
              createdAt: '2026-02-09T10:00:00.000Z',
            ),
          ],
        },
      );

      final result = await loadConversation(
        messageRepo: messageRepo,
        contactPeerId: 'contact-A',
        mediaAttachmentRepo: mediaRepo,
        // no mediaFileManager
      );

      // Path should remain as-is (relative)
      expect(result[0].media[0].localPath, 'media/contact-A/blob-001.jpg');
    });

    test('handles null localPath gracefully', () async {
      final messageRepo = FakeMessageRepository(
        messagesByContact: {
          'contact-A': [
            ConversationMessage(
              id: 'msg-1',
              contactPeerId: 'contact-A',
              senderPeerId: 'contact-A',
              text: 'Photo pending',
              timestamp: '2026-02-09T10:00:00.000Z',
              status: 'delivered',
              isIncoming: true,
              createdAt: '2026-02-09T10:00:01.000Z',
            ),
          ],
        },
      );
      final mediaRepo = FakeMediaAttachmentRepository(
        mediaByMessage: {
          'msg-1': [
            const MediaAttachment(
              id: 'blob-001',
              messageId: 'msg-1',
              mime: 'image/jpeg',
              size: 245000,
              mediaType: 'image',
              localPath: null, // not yet downloaded
              downloadStatus: 'pending',
              createdAt: '2026-02-09T10:00:00.000Z',
            ),
          ],
        },
      );

      final result = await loadConversation(
        messageRepo: messageRepo,
        contactPeerId: 'contact-A',
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fakeFileManager,
      );

      expect(result[0].media[0].localPath, isNull);
    });
  });
}

/// Fake media file manager that resolves paths deterministically without
/// needing path_provider.
class _FakeMediaFileManager extends MediaFileManager {
  final String basePath;

  _FakeMediaFileManager(this.basePath);

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    // Relative path: prepend basePath
    if (storedPath.startsWith('media/')) {
      return '$basePath/$storedPath';
    }
    // Legacy absolute path with /media/
    final mediaIndex = storedPath.indexOf('/media/');
    if (mediaIndex != -1) {
      final relativePortion = storedPath.substring(mediaIndex + 1);
      return '$basePath/$relativePortion';
    }
    return storedPath;
  }
}
