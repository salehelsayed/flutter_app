import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/feed/application/load_feed_use_case.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

// -- Fake Contact Repository --
class FakeContactRepository implements ContactRepository {
  final List<ContactModel> contacts;

  FakeContactRepository({this.contacts = const []});

  @override
  Future<List<ContactModel>> getAllContacts() async => contacts;

  @override
  Future<ContactModel?> getContact(String peerId) async =>
      contacts.where((c) => c.peerId == peerId).firstOrNull;

  @override
  Future<void> addContact(ContactModel contact) async {}

  @override
  Future<void> deleteContact(String peerId) async {}

  @override
  Future<bool> contactExists(String peerId) async => false;

  @override
  Future<int> getContactCount() async => contacts.length;

  @override
  Future<void> archiveContact(String peerId) async {}

  @override
  Future<void> unarchiveContact(String peerId) async {}

  @override
  Future<void> blockContact(String peerId) async {}

  @override
  Future<void> unblockContact(String peerId) async {}

  @override
  Future<List<ContactModel>> getActiveContacts() async =>
      contacts.where((c) => !c.isArchived).toList();

  @override
  Future<List<ContactModel>> getArchivedContacts() async =>
      contacts.where((c) => c.isArchived).toList();

  @override
  Future<void> dismissIntroBanner(String peerId) async {}

  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

// -- Fake Message Repository --
class FakeMessageRepository implements MessageRepository {
  final Map<String, List<ConversationMessage>> messagesByContact;

  FakeMessageRepository({this.messagesByContact = const {}});

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    return messagesByContact[contactPeerId] ?? [];
  }

  @override
  Future<void> saveMessage(ConversationMessage message) async {}

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    return null;
  }

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
  Future<int> deleteMessagesForContact(String contactPeerId) async => 0;

  @override
  Future<int> deleteMessage(String id) async => 0;

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async => [];

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async => [];

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async => [];

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
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async => [];

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async => 0;
}

ContactModel _makeContact(String peerId, String username, String scannedAt) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: scannedAt,
  );
}

ConversationMessage _makeMessage({
  required String id,
  required String contactPeerId,
  required String senderPeerId,
  required String text,
  required String timestamp,
  required bool isIncoming,
  String? readAt,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: senderPeerId,
    text: text,
    timestamp: timestamp,
    status: 'delivered',
    isIncoming: isIncoming,
    createdAt: timestamp,
    readAt: readAt,
  );
}

void main() {
  group('loadFeed', () {
    test('returns empty list when no contacts', () async {
      final result = await loadFeed(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
      );

      expect(result, isEmpty);
    });

    test('returns ConnectionFeedItems for contacts with no messages', () async {
      final contacts = [
        _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
        _makeContact('peer-B', 'Bob', '2026-02-09T11:00:00.000Z'),
      ];

      final result = await loadFeed(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: FakeMessageRepository(),
      );

      expect(result.length, 2);
      expect(result.every((item) => item is ConnectionFeedItem), isTrue);
      // Newest-first: Bob (11:00) before Alice (10:00)
      expect((result[0] as ConnectionFeedItem).contactUsername, 'Bob');
      expect((result[1] as ConnectionFeedItem).contactUsername, 'Alice');
    });

    test(
      'groups sent and received messages into ThreadFeedItems by contact',
      () async {
        final contacts = [
          _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
        ];

        final messages = {
          'peer-A': [
            _makeMessage(
              id: 'msg-1',
              contactPeerId: 'peer-A',
              senderPeerId: 'peer-A',
              text: 'Hello from Alice',
              timestamp: '2026-02-09T12:00:00.000Z',
              isIncoming: true,
            ),
            _makeMessage(
              id: 'msg-2',
              contactPeerId: 'peer-A',
              senderPeerId: 'peer-A',
              text: 'Second message',
              timestamp: '2026-02-09T12:05:00.000Z',
              isIncoming: true,
            ),
            _makeMessage(
              id: 'msg-3',
              contactPeerId: 'peer-A',
              senderPeerId: 'my-peer',
              text: 'My reply',
              timestamp: '2026-02-09T12:01:00.000Z',
              isIncoming: false,
            ),
          ],
        };

        final result = await loadFeed(
          contactRepo: FakeContactRepository(contacts: contacts),
          messageRepo: FakeMessageRepository(messagesByContact: messages),
        );

        final threadItems = result.whereType<ThreadFeedItem>().toList();
        expect(threadItems.length, 1);
        // All 3 messages (sent + received) grouped into one thread
        expect(threadItems[0].messages.length, 3);
        expect(threadItems[0].messages[0].text, 'Hello from Alice');
        expect(threadItems[0].messages[1].text, 'My reply');
        expect(threadItems[0].messages[2].text, 'Second message');
        expect(threadItems[0].contactUsername, 'Alice');
      },
    );

    test('same contact with 24hr gap keeps single card', () async {
      final contacts = [
        _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
      ];

      final messages = {
        'peer-A': [
          _makeMessage(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            senderPeerId: 'peer-A',
            text: 'Read message',
            timestamp: '2026-02-08T08:00:00.000Z',
            isIncoming: true,
            readAt: '2026-02-08T08:30:00.000Z',
          ),
          // 26 hour gap — still one card per contact
          _makeMessage(
            id: 'msg-2',
            contactPeerId: 'peer-A',
            senderPeerId: 'peer-A',
            text: 'Unread message',
            timestamp: '2026-02-09T10:00:00.000Z',
            isIncoming: true,
          ),
        ],
      };

      final result = await loadFeed(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: FakeMessageRepository(messagesByContact: messages),
      );

      final threadItems = result.whereType<ThreadFeedItem>().toList();
      // One card per contact, unread takes precedence
      expect(threadItems.length, 1);
      expect(threadItems[0].isUnreadCard, isTrue);
      expect(threadItems[0].messages.length, 2);
      expect(threadItems[0].messages[0].text, 'Read message');
      expect(threadItems[0].messages[1].text, 'Unread message');
    });

    test('sorts all items newest-first across types', () async {
      final contacts = [
        _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
        _makeContact('peer-B', 'Bob', '2026-02-09T14:00:00.000Z'),
      ];

      final messages = {
        'peer-A': [
          _makeMessage(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            senderPeerId: 'peer-A',
            text: 'Hello',
            timestamp: '2026-02-09T12:00:00.000Z',
            isIncoming: true,
          ),
        ],
      };

      final result = await loadFeed(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: FakeMessageRepository(messagesByContact: messages),
      );

      expect(result.length, 3);
      // Bob connection at 14:00, thread at 12:00, Alice connection at 10:00
      expect(result[0], isA<ConnectionFeedItem>());
      expect((result[0] as ConnectionFeedItem).contactUsername, 'Bob');
      expect(result[1], isA<ThreadFeedItem>());
      expect(result[2], isA<ConnectionFeedItem>());
      expect((result[2] as ConnectionFeedItem).contactUsername, 'Alice');
    });

    test('includes blocked contacts with isBlocked flag', () async {
      final contacts = [
        _makeContact('peer-A', 'Alice', '2026-02-01T10:00:00.000Z'),
        ContactModel(
          peerId: 'peer-B',
          publicKey: 'pk-peer-B',
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'BlockedBob',
          signature: 'sig-peer-B',
          scannedAt: '2026-02-01T14:00:00.000Z',
          isBlocked: true,
          blockedAt: '2026-02-15T00:00:00.000Z',
        ),
      ];

      final result = await loadFeed(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: FakeMessageRepository(),
      );

      expect(result.length, 2);
      // Both present, newest first: BlockedBob (14:00) then Alice (10:00)
      final bob = result[0] as ConnectionFeedItem;
      final alice = result[1] as ConnectionFeedItem;
      expect(bob.contactUsername, 'BlockedBob');
      expect(bob.isBlocked, isTrue);
      expect(alice.contactUsername, 'Alice');
      expect(alice.isBlocked, isFalse);
    });
  });

  group('loadFeed with group messages', () {
    test('returns group thread items when group repos provided', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Alpha Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g1',
          senderPeerId: 'p1',
          senderUsername: 'User1',
          text: 'Hello group!',
          timestamp: DateTime.utc(2026, 2, 9, 12, 0),
          createdAt: DateTime.utc(2026, 2, 9, 12, 0),
        ),
      );

      final result = await loadFeed(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
      );

      final groupItems = result.whereType<GroupThreadFeedItem>().toList();
      expect(groupItems.length, 1);
      expect(groupItems[0].groupName, 'Alpha Group');
      expect(groupItems[0].messages.length, 1);
    });

    test('group items merge with contact items sorted by timestamp', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();

      final contacts = [
        _makeContact('peer-A', 'Alice', '2026-02-09T10:00:00.000Z'),
      ];

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Group Alpha',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g1',
          senderPeerId: 'p1',
          text: 'Group msg',
          timestamp: DateTime.utc(2026, 2, 9, 14, 0),
          createdAt: DateTime.utc(2026, 2, 9, 14, 0),
        ),
      );

      final result = await loadFeed(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: FakeMessageRepository(),
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
      );

      expect(result.length, 2);
      // Group at 14:00, Alice connection at 10:00
      expect(result[0], isA<GroupThreadFeedItem>());
      expect(result[1], isA<ConnectionFeedItem>());
    });

    test(
      'dissolved groups stay visible but project frozen feed affordances',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final groupMsgRepo = InMemoryGroupMessageRepository();

        await groupRepo.saveGroup(
          GroupModel(
            id: 'g1',
            name: 'Frozen Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/g1',
            createdAt: DateTime(2026, 2, 1),
            createdBy: 'admin',
            myRole: GroupRole.member,
            isDissolved: true,
            dissolvedAt: DateTime.utc(2026, 2, 9, 11, 59),
            dissolvedBy: 'admin',
          ),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'gm-1',
            groupId: 'g1',
            senderPeerId: 'p1',
            text: 'Frozen history',
            timestamp: DateTime.utc(2026, 2, 9, 12, 0),
            createdAt: DateTime.utc(2026, 2, 9, 12, 0),
          ),
        );

        final result = await loadFeed(
          contactRepo: FakeContactRepository(),
          messageRepo: FakeMessageRepository(),
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        final groupItems = result.whereType<GroupThreadFeedItem>().toList();
        expect(groupItems, hasLength(1));
        expect(groupItems.first.isDissolved, isTrue);
        expect(groupItems.first.canWrite, isFalse);
        expect(groupItems.first.canReact, isFalse);
      },
    );

    test('no group items when group repos not provided', () async {
      final result = await loadFeed(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
      );

      final groupItems = result.whereType<GroupThreadFeedItem>().toList();
      expect(groupItems, isEmpty);
    });

    test('archived groups excluded from feed', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Active Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveGroup(
        GroupModel(
          id: 'g2',
          name: 'Archived Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g2',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
          isArchived: true,
          archivedAt: DateTime(2026, 2, 5),
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g1',
          senderPeerId: 'p1',
          text: 'Active msg',
          timestamp: DateTime.utc(2026, 2, 9, 12, 0),
          createdAt: DateTime.utc(2026, 2, 9, 12, 0),
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-2',
          groupId: 'g2',
          senderPeerId: 'p1',
          text: 'Archived msg',
          timestamp: DateTime.utc(2026, 2, 9, 13, 0),
          createdAt: DateTime.utc(2026, 2, 9, 13, 0),
        ),
      );

      final result = await loadFeed(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
      );

      final groupItems = result.whereType<GroupThreadFeedItem>().toList();
      expect(groupItems.length, 1);
      expect(groupItems[0].groupName, 'Active Group');
    });

    test('groups with no messages produce no thread items', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Empty Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );

      final result = await loadFeed(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
      );

      final groupItems = result.whereType<GroupThreadFeedItem>().toList();
      expect(groupItems, isEmpty);
    });

    test('loadGroupFeedItems batch-loads media attachments', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
      final mediaFileManager = FakeMediaFileManager();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Media Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g1',
          senderPeerId: 'p1',
          senderUsername: 'User1',
          text: 'Photo',
          timestamp: DateTime.utc(2026, 2, 9, 12, 0),
          createdAt: DateTime.utc(2026, 2, 9, 12, 0),
        ),
      );
      await mediaAttachmentRepo.saveAttachment(
        MediaAttachment(
          id: 'att-g1',
          messageId: 'gm-1',
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          localPath: 'media/groups/img.jpg',
          downloadStatus: 'done',
          createdAt: '2026-02-09T12:00:00.000Z',
        ),
      );

      final items = await loadGroupFeedItems(
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );

      expect(items, hasLength(1));
      expect(items.first.messages.first.media, hasLength(1));
      expect(items.first.messages.first.media.first.id, 'att-g1');
      // Path should be resolved
      expect(
        items.first.messages.first.media.first.localPath,
        endsWith('test_docs/media/groups/img.jpg'),
      );
    });

    test('loadGroupFeedItems blocks tampered done group media', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
      final mediaFileManager = FakeMediaFileManager();
      const relativePath = 'media/groups/tampered.jpg';
      final absolutePath = await mediaFileManager.resolveStoredPath(
        relativePath,
      );
      final file = File(absolutePath)..createSync(recursive: true);
      file.writeAsBytesSync(utf8.encode('tampered bytes'));
      final expectedHash = sha256
          .convert(utf8.encode('original bytes'))
          .toString();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Media Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g1',
          senderPeerId: 'p1',
          senderUsername: 'User1',
          text: 'Tampered',
          timestamp: DateTime.utc(2026, 2, 9, 12, 0),
          createdAt: DateTime.utc(2026, 2, 9, 12, 0),
        ),
      );
      await mediaAttachmentRepo.saveAttachment(
        MediaAttachment(
          id: 'att-tampered',
          messageId: 'gm-1',
          mime: 'image/jpeg',
          size: file.lengthSync(),
          mediaType: 'image',
          localPath: relativePath,
          downloadStatus: 'done',
          contentHash: expectedHash,
          createdAt: '2026-02-09T12:00:00.000Z',
        ),
      );

      final items = await loadGroupFeedItems(
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );

      final attachment = items.single.messages.single.media.single;
      expect(attachment.id, 'att-tampered');
      expect(attachment.downloadStatus, kMediaDownloadStatusIntegrityFailed);
      expect(attachment.localPath, absolutePath);
      expect(File(absolutePath).existsSync(), isFalse);
    });

    test('loadFeed includes group media attachments', () async {
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
      final mediaFileManager = FakeMediaFileManager();

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g1',
          name: 'Media Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g1',
          createdAt: DateTime(2026, 2, 1),
          createdBy: 'admin',
          myRole: GroupRole.member,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g1',
          senderPeerId: 'p1',
          senderUsername: 'User1',
          text: 'Image message',
          timestamp: DateTime.utc(2026, 2, 9, 12, 0),
          createdAt: DateTime.utc(2026, 2, 9, 12, 0),
        ),
      );
      await mediaAttachmentRepo.saveAttachment(
        MediaAttachment(
          id: 'att-g1',
          messageId: 'gm-1',
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          localPath: 'media/groups/img.jpg',
          downloadStatus: 'done',
          createdAt: '2026-02-09T12:00:00.000Z',
        ),
      );

      final result = await loadFeed(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );

      final groupItems = result.whereType<GroupThreadFeedItem>().toList();
      expect(groupItems, hasLength(1));
      expect(groupItems.first.messages.first.media, hasLength(1));
      expect(groupItems.first.messages.first.media.first.id, 'att-g1');
    });
  });
}
