import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/feed/application/feed_projection.dart';
import 'package:flutter_app/features/feed/application/load_contact_feed_snapshot_use_case.dart';
import 'package:flutter_app/features/feed/application/load_feed_use_case.dart';
import 'package:flutter_app/features/feed/application/load_group_feed_snapshot_use_case.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/group_group_messages_into_threads.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';

ContactModel _contact({
  required String peerId,
  required String username,
  required String scannedAt,
  bool isBlocked = false,
  String? avatarPath,
  String? introducedBy,
  String? introducedByPeerId,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: scannedAt,
    isBlocked: isBlocked,
    avatarPath: avatarPath,
    introducedBy: introducedBy,
    introducedByPeerId: introducedByPeerId,
  );
}

ConversationMessage _message({
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

GroupModel _group({
  required String id,
  required String name,
  required DateTime createdAt,
  bool isArchived = false,
}) {
  return GroupModel(
    id: id,
    name: name,
    type: GroupType.chat,
    topicName: '/mknoon/group/$id',
    createdAt: createdAt,
    createdBy: 'admin',
    myRole: GroupRole.member,
    isArchived: isArchived,
    archivedAt: isArchived ? createdAt.add(const Duration(days: 1)) : null,
  );
}

GroupMessage _groupMessage({
  required String id,
  required String groupId,
  required String senderPeerId,
  required String text,
  required DateTime timestamp,
  bool isIncoming = true,
  DateTime? readAt,
}) {
  return GroupMessage(
    id: id,
    groupId: groupId,
    senderPeerId: senderPeerId,
    senderUsername: senderPeerId,
    text: text,
    timestamp: timestamp,
    isIncoming: isIncoming,
    readAt: readAt,
    createdAt: timestamp,
  );
}

List<Map<String, Object?>> _summaries(List<FeedItem> items) {
  return items.map(_summarizeFeedItem).toList();
}

Map<String, Object?> _summarizeFeedItem(FeedItem item) {
  if (item is ConnectionFeedItem) {
    return {
      'type': 'connection',
      'id': item.id,
      'timestamp': item.timestamp.toUtc().toIso8601String(),
      'contactPeerId': item.contactPeerId,
      'contactUsername': item.contactUsername,
      'contactAvatarPath': item.contactAvatarPath,
      'isBlocked': item.isBlocked,
      'introducedBy': item.introducedBy,
      'introducedByPeerId': item.introducedByPeerId,
    };
  }
  if (item is ThreadFeedItem) {
    return {
      'type': 'thread',
      'id': item.id,
      'timestamp': item.timestamp.toUtc().toIso8601String(),
      'contactPeerId': item.contactPeerId,
      'contactUsername': item.contactUsername,
      'unreadCount': item.unreadCount,
      'isUnreadCard': item.isUnreadCard,
      'conversationState': item.conversationState.name,
      'isBlocked': item.isBlocked,
      'messages': item.messages
          .map(
            (message) => {
              'id': message.id,
              'text': message.text,
              'timestamp': message.timestamp.toUtc().toIso8601String(),
              'isIncoming': message.isIncoming,
              'isUnread': message.isUnread,
              'status': message.status,
              'quotedMessageId': message.quotedMessageId,
              'media': message.media
                  .map(
                    (media) => {
                      'id': media.id,
                      'localPath': media.localPath,
                      'downloadStatus': media.downloadStatus,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    };
  }
  if (item is GroupThreadFeedItem) {
    return {
      'type': 'groupThread',
      'id': item.id,
      'timestamp': item.timestamp.toUtc().toIso8601String(),
      'groupId': item.groupId,
      'groupName': item.groupName,
      'groupType': item.groupType.name,
      'myRole': item.myRole.name,
      'isDissolved': item.isDissolved,
      'canWrite': item.canWrite,
      'canReact': item.canReact,
      'unreadCount': item.unreadCount,
      'conversationState': item.conversationState.name,
      'messages': item.messages
          .map(
            (message) => {
              'id': message.id,
              'text': message.text,
              'timestamp': message.timestamp.toUtc().toIso8601String(),
              'isIncoming': message.isIncoming,
              'isUnread': message.isUnread,
              'senderUsername': message.senderUsername,
              'senderPeerId': message.senderPeerId,
            },
          )
          .toList(),
    };
  }
  throw StateError('Unsupported feed item type: ${item.runtimeType}');
}

void main() {
  late FakeContactRepository contactRepo;
  late InMemoryMessageRepository messageRepo;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepo;
  late FakeMediaFileManager mediaFileManager;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository groupMessageRepo;

  setUp(() {
    contactRepo = FakeContactRepository();
    messageRepo = InMemoryMessageRepository();
    mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
    mediaFileManager = FakeMediaFileManager();
    groupRepo = InMemoryGroupRepository();
    groupMessageRepo = InMemoryGroupMessageRepository();
  });

  Future<List<FeedItem>> loadFullFeed() {
    return loadFeed(
      contactRepo: contactRepo,
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
      groupRepo: groupRepo,
      groupMsgRepo: groupMessageRepo,
    );
  }

  group('feed projection parity', () {
    test(
      'first incoming message converts connection-only contact incrementally',
      () async {
        contactRepo.seed([
          _contact(
            peerId: 'peer-A',
            username: 'Alice',
            scannedAt: '2026-02-01T10:00:00.000Z',
          ),
        ]);

        final initial = await loadFullFeed();

        await messageRepo.saveMessage(
          _message(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            senderPeerId: 'peer-A',
            text: 'Hello',
            timestamp: '2026-02-01T12:00:00.000Z',
            isIncoming: true,
          ),
        );

        final snapshot = await loadContactFeedSnapshot(
          contactRepo: contactRepo,
          messageRepo: messageRepo,
          contactPeerId: 'peer-A',
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        final incrementallyUpdated = applyContactFeedSnapshot(
          currentItems: initial,
          contactPeerId: 'peer-A',
          connectionItem: snapshot.connectionItem,
          threadItem: snapshot.threadItem,
        );
        final fullReload = await loadFullFeed();

        expect(_summaries(incrementallyUpdated), _summaries(fullReload));
        expect(incrementallyUpdated.whereType<ThreadFeedItem>(), hasLength(1));
      },
    );

    test(
      'incoming chat updates only the affected thread and ordering matches cold load',
      () async {
        contactRepo.seed([
          _contact(
            peerId: 'peer-A',
            username: 'Alice',
            scannedAt: '2026-02-01T10:00:00.000Z',
          ),
          _contact(
            peerId: 'peer-B',
            username: 'Bob',
            scannedAt: '2026-02-01T11:00:00.000Z',
          ),
        ]);
        await messageRepo.saveMessage(
          _message(
            id: 'msg-a1',
            contactPeerId: 'peer-A',
            senderPeerId: 'peer-A',
            text: 'Old Alice',
            timestamp: '2026-02-01T12:00:00.000Z',
            isIncoming: true,
          ),
        );
        await messageRepo.saveMessage(
          _message(
            id: 'msg-b1',
            contactPeerId: 'peer-B',
            senderPeerId: 'peer-B',
            text: 'Current Bob',
            timestamp: '2026-02-01T13:00:00.000Z',
            isIncoming: true,
          ),
        );

        final initial = await loadFullFeed();

        await messageRepo.saveMessage(
          _message(
            id: 'msg-a2',
            contactPeerId: 'peer-A',
            senderPeerId: 'peer-A',
            text: 'Newest Alice',
            timestamp: '2026-02-01T14:00:00.000Z',
            isIncoming: true,
          ),
        );

        final snapshot = await loadContactFeedSnapshot(
          contactRepo: contactRepo,
          messageRepo: messageRepo,
          contactPeerId: 'peer-A',
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        final incrementallyUpdated = applyContactFeedSnapshot(
          currentItems: initial,
          contactPeerId: 'peer-A',
          connectionItem: snapshot.connectionItem,
          threadItem: snapshot.threadItem,
        );
        final fullReload = await loadFullFeed();

        expect(_summaries(incrementallyUpdated), _summaries(fullReload));
        expect(
          (incrementallyUpdated.firstWhere((item) => item is ThreadFeedItem)
                  as ThreadFeedItem)
              .contactPeerId,
          'peer-A',
        );
      },
    );

    test(
      'contact metadata refresh matches cold load without touching other items',
      () async {
        contactRepo.seed([
          _contact(
            peerId: 'peer-A',
            username: 'Alice',
            scannedAt: '2026-02-01T10:00:00.000Z',
          ),
        ]);
        await messageRepo.saveMessage(
          _message(
            id: 'msg-1',
            contactPeerId: 'peer-A',
            senderPeerId: 'peer-A',
            text: 'Hello',
            timestamp: '2026-02-01T12:00:00.000Z',
            isIncoming: true,
          ),
        );

        final initial = await loadFullFeed();

        contactRepo.seed([
          _contact(
            peerId: 'peer-A',
            username: 'Bobby',
            scannedAt: '2026-02-01T10:00:00.000Z',
            isBlocked: true,
            avatarPath: 'media/avatars/bobby.jpg',
            introducedBy: 'Charlie',
            introducedByPeerId: 'peer-C',
          ),
        ]);

        final snapshot = await loadContactFeedSnapshot(
          contactRepo: contactRepo,
          messageRepo: messageRepo,
          contactPeerId: 'peer-A',
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        final incrementallyUpdated = applyContactFeedSnapshot(
          currentItems: initial,
          contactPeerId: 'peer-A',
          connectionItem: snapshot.connectionItem,
          threadItem: snapshot.threadItem,
        );
        final fullReload = await loadFullFeed();

        expect(_summaries(incrementallyUpdated), _summaries(fullReload));
      },
    );

    test('archived contact removal matches cold load', () async {
      contactRepo.seed([
        _contact(
          peerId: 'peer-A',
          username: 'Alice',
          scannedAt: '2026-02-01T10:00:00.000Z',
        ),
      ]);
      await messageRepo.saveMessage(
        _message(
          id: 'msg-1',
          contactPeerId: 'peer-A',
          senderPeerId: 'peer-A',
          text: 'Hello',
          timestamp: '2026-02-01T12:00:00.000Z',
          isIncoming: true,
        ),
      );

      final initial = await loadFullFeed();

      await contactRepo.archiveContact('peer-A');

      final snapshot = await loadContactFeedSnapshot(
        contactRepo: contactRepo,
        messageRepo: messageRepo,
        contactPeerId: 'peer-A',
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );

      final incrementallyUpdated = applyContactFeedSnapshot(
        currentItems: initial,
        contactPeerId: 'peer-A',
        connectionItem: snapshot.connectionItem,
        threadItem: snapshot.threadItem,
      );
      final fullReload = await loadFullFeed();

      expect(_summaries(incrementallyUpdated), _summaries(fullReload));
      expect(incrementallyUpdated, isEmpty);
    });

    test('mark-read transition matches cold load', () async {
      contactRepo.seed([
        _contact(
          peerId: 'peer-A',
          username: 'Alice',
          scannedAt: '2026-02-01T10:00:00.000Z',
        ),
      ]);
      await messageRepo.saveMessage(
        _message(
          id: 'msg-1',
          contactPeerId: 'peer-A',
          senderPeerId: 'peer-A',
          text: 'Unread',
          timestamp: '2026-02-01T12:00:00.000Z',
          isIncoming: true,
        ),
      );

      final initial = await loadFullFeed();

      await messageRepo.markConversationAsRead('peer-A');

      final snapshot = await loadContactFeedSnapshot(
        contactRepo: contactRepo,
        messageRepo: messageRepo,
        contactPeerId: 'peer-A',
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );

      final incrementallyUpdated = applyContactFeedSnapshot(
        currentItems: initial,
        contactPeerId: 'peer-A',
        connectionItem: snapshot.connectionItem,
        threadItem: snapshot.threadItem,
      );
      final fullReload = await loadFullFeed();

      expect(_summaries(incrementallyUpdated), _summaries(fullReload));
      expect(
        incrementallyUpdated
            .whereType<ThreadFeedItem>()
            .single
            .conversationState,
        ConversationState.read,
      );
    });

    test('group message upsert and reorder matches cold load', () async {
      contactRepo.seed([
        _contact(
          peerId: 'peer-A',
          username: 'Alice',
          scannedAt: '2026-02-01T10:00:00.000Z',
        ),
      ]);
      await messageRepo.saveMessage(
        _message(
          id: 'msg-a1',
          contactPeerId: 'peer-A',
          senderPeerId: 'peer-A',
          text: 'Contact thread',
          timestamp: '2026-02-01T12:00:00.000Z',
          isIncoming: true,
        ),
      );
      await groupRepo.saveGroup(
        _group(
          id: 'group-1',
          name: 'Alpha Group',
          createdAt: DateTime.utc(2026, 2, 1),
        ),
      );
      await groupMessageRepo.saveMessage(
        _groupMessage(
          id: 'gm-1',
          groupId: 'group-1',
          senderPeerId: 'peer-B',
          text: 'Older group',
          timestamp: DateTime.utc(2026, 2, 1, 11, 0),
        ),
      );

      final initial = await loadFullFeed();

      await groupMessageRepo.saveMessage(
        _groupMessage(
          id: 'gm-2',
          groupId: 'group-1',
          senderPeerId: 'peer-B',
          text: 'Newest group',
          timestamp: DateTime.utc(2026, 2, 1, 13, 30),
        ),
      );

      final snapshot = await loadGroupFeedSnapshot(
        groupRepo: groupRepo,
        groupMsgRepo: groupMessageRepo,
        groupId: 'group-1',
      );

      final incrementallyUpdated = applyGroupFeedSnapshot(
        currentItems: initial,
        groupId: 'group-1',
        threadItem: snapshot,
      );
      final fullReload = await loadFullFeed();

      expect(_summaries(incrementallyUpdated), _summaries(fullReload));
      expect(
        incrementallyUpdated.whereType<GroupThreadFeedItem>().single.groupId,
        'group-1',
      );
    });

    test('group message with media flows through to ThreadMessage', () async {
      final attachment = MediaAttachment(
        id: 'att-g1',
        messageId: 'gm-1',
        mime: 'image/jpeg',
        size: 2048,
        mediaType: 'image',
        downloadStatus: 'done',
        localPath: '/tmp/group-img.jpg',
        createdAt: '2026-02-01T11:00:00.000Z',
      );
      final groupMsg = GroupMessage(
        id: 'gm-1',
        groupId: 'group-1',
        senderPeerId: 'peer-B',
        senderUsername: 'Bob',
        text: 'Check this out',
        timestamp: DateTime.utc(2026, 2, 1, 11, 0),
        createdAt: DateTime.utc(2026, 2, 1, 11, 0),
        media: [attachment],
      );
      final group = GroupModel(
        id: 'group-1',
        name: 'Alpha',
        type: GroupType.chat,
        topicName: '/mknoon/group/group-1',
        createdAt: DateTime.utc(2026, 2, 1),
        createdBy: 'admin',
        myRole: GroupRole.member,
      );

      final items = groupGroupMessagesIntoThreads(
        allGroupMessages: [groupMsg],
        groups: [group],
      );

      expect(items, hasLength(1));
      expect(items.first.messages.first.media, hasLength(1));
      expect(items.first.messages.first.media.first.id, 'att-g1');
    });

    test('archived group removal matches cold load', () async {
      await groupRepo.saveGroup(
        _group(
          id: 'group-1',
          name: 'Alpha Group',
          createdAt: DateTime.utc(2026, 2, 1),
        ),
      );
      await groupMessageRepo.saveMessage(
        _groupMessage(
          id: 'gm-1',
          groupId: 'group-1',
          senderPeerId: 'peer-B',
          text: 'Group message',
          timestamp: DateTime.utc(2026, 2, 1, 13, 0),
        ),
      );

      final initial = await loadFullFeed();

      await groupRepo.archiveGroup('group-1');

      final snapshot = await loadGroupFeedSnapshot(
        groupRepo: groupRepo,
        groupMsgRepo: groupMessageRepo,
        groupId: 'group-1',
      );

      final incrementallyUpdated = applyGroupFeedSnapshot(
        currentItems: initial,
        groupId: 'group-1',
        threadItem: snapshot,
      );
      final fullReload = await loadFullFeed();

      expect(_summaries(incrementallyUpdated), _summaries(fullReload));
      expect(incrementallyUpdated.whereType<GroupThreadFeedItem>(), isEmpty);
    });

    test('loadGroupFeedSnapshot includes media attachments', () async {
      await groupRepo.saveGroup(
        _group(
          id: 'group-1',
          name: 'Alpha',
          createdAt: DateTime.utc(2026, 2, 1),
        ),
      );
      await groupMessageRepo.saveMessage(
        _groupMessage(
          id: 'gm-1',
          groupId: 'group-1',
          senderPeerId: 'peer-B',
          text: 'Photo',
          timestamp: DateTime.utc(2026, 2, 1, 11, 0),
        ),
      );
      await mediaAttachmentRepo.saveAttachment(
        MediaAttachment(
          id: 'att-snap-1',
          messageId: 'gm-1',
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          localPath: 'media/groups/snap.jpg',
          downloadStatus: 'done',
          createdAt: '2026-02-01T11:00:00Z',
        ),
      );

      final snapshot = await loadGroupFeedSnapshot(
        groupRepo: groupRepo,
        groupMsgRepo: groupMessageRepo,
        groupId: 'group-1',
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.messages.first.media, hasLength(1));
      expect(snapshot.messages.first.media.first.id, 'att-snap-1');
      expect(
        snapshot.messages.first.media.first.localPath,
        contains('media/groups/snap.jpg'),
      );
    });

    test(
      'loadGroupFeedSnapshot without media repos returns empty media',
      () async {
        await groupRepo.saveGroup(
          _group(
            id: 'group-1',
            name: 'Alpha',
            createdAt: DateTime.utc(2026, 2, 1),
          ),
        );
        await groupMessageRepo.saveMessage(
          _groupMessage(
            id: 'gm-1',
            groupId: 'group-1',
            senderPeerId: 'peer-B',
            text: 'No media loaded',
            timestamp: DateTime.utc(2026, 2, 1, 11, 0),
          ),
        );

        final snapshot = await loadGroupFeedSnapshot(
          groupRepo: groupRepo,
          groupMsgRepo: groupMessageRepo,
          groupId: 'group-1',
        );

        expect(snapshot, isNotNull);
        expect(snapshot!.messages.first.media, isEmpty);
      },
    );
  });
}
