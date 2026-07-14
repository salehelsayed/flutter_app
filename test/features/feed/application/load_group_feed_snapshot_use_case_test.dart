import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/application/load_group_feed_snapshot_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

class _RecordingMediaAttachmentRepository
    extends InMemoryMediaAttachmentRepository {
  final List<List<String>> batchRequests = <List<String>>[];
  final List<String> singleRequests = <String>[];

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) {
    batchRequests.add(List<String>.of(messageIds));
    return super.getAttachmentsForMessages(messageIds, owner: owner);
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) {
    singleRequests.add(messageId);
    return super.getAttachmentsForMessage(messageId, owner: owner);
  }
}

GroupModel _group(String id) => GroupModel(
  id: id,
  name: 'Group $id',
  type: GroupType.chat,
  topicName: '/mknoon/group/$id',
  createdAt: DateTime(2026, 2, 1),
  createdBy: 'admin',
  myRole: GroupRole.member,
);

GroupMessage _msg({
  required String id,
  required String groupId,
  required String text,
  required DateTime timestamp,
  required bool isIncoming,
  DateTime? readAt,
  String? quotedMessageId,
  GroupPrivateMediaPolicy privateMediaPolicy =
      const GroupPrivateMediaPolicy.ordinary(),
}) => GroupMessage(
  id: id,
  groupId: groupId,
  senderPeerId: isIncoming ? 'p1' : 'me',
  text: text,
  timestamp: timestamp,
  createdAt: timestamp,
  isIncoming: isIncoming,
  status: isIncoming ? 'delivered' : 'sent',
  readAt: readAt,
  quotedMessageId: quotedMessageId,
  privateMediaPolicy: privateMediaPolicy,
);

MediaAttachment _attachment({
  required String id,
  required String messageId,
  String? localPath,
}) => MediaAttachment(
  id: id,
  messageId: messageId,
  mime: 'image/jpeg',
  size: 37,
  mediaType: 'image',
  localPath: localPath,
  downloadStatus: localPath == null ? 'pending' : 'done',
  createdAt: DateTime.utc(2026, 3, 1).toIso8601String(),
);

void main() {
  test(
    'GPL-15F cold group feed snapshot redacts private and unsupported parents '
    'before attachment/path work while preserving ordinary media',
    () async {
      final groupRepo = InMemoryGroupRepository()..saveGroup(_group('g1'));
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final mediaRepo = _RecordingMediaAttachmentRepository();
      final mediaFileManager = FakeMediaFileManager();
      final base = DateTime.utc(2026, 3, 1, 12);

      await groupMsgRepo.saveMessage(
        _msg(
          id: 'private-parent',
          groupId: 'g1',
          text: 'private caption and image name',
          timestamp: base,
          isIncoming: true,
          quotedMessageId: 'private-quoted-parent',
          privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
        ),
      );
      await groupMsgRepo.saveMessage(
        _msg(
          id: 'unsupported-parent',
          groupId: 'g1',
          text: 'future private caption',
          timestamp: base.add(const Duration(minutes: 1)),
          isIncoming: true,
          quotedMessageId: 'unsupported-quoted-parent',
          privateMediaPolicy: const GroupPrivateMediaPolicy.unsupported(
            sourceVersion: 9,
          ),
        ),
      );
      await groupMsgRepo.saveMessage(
        _msg(
          id: 'ordinary-parent',
          groupId: 'g1',
          text: 'ordinary caption',
          timestamp: base.add(const Duration(minutes: 2)),
          isIncoming: true,
          quotedMessageId: 'ordinary-quoted-parent',
        ),
      );

      await mediaRepo.saveAttachment(
        _attachment(
          id: 'private-attachment',
          messageId: 'private-parent',
          localPath: 'media/g1/private-secret.jpg',
        ),
        owner: MediaOwnerLane.group,
      );
      await mediaRepo.saveAttachment(
        _attachment(
          id: 'unsupported-attachment',
          messageId: 'unsupported-parent',
          localPath: 'media/g1/unsupported-secret.jpg',
        ),
        owner: MediaOwnerLane.group,
      );
      await mediaRepo.saveAttachment(
        _attachment(id: 'ordinary-attachment', messageId: 'ordinary-parent'),
        owner: MediaOwnerLane.group,
      );

      final item = await loadGroupFeedSnapshot(
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        groupId: 'g1',
        pageSize: 30,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: mediaFileManager,
      );

      expect(item, isNotNull);
      expect(mediaRepo.batchRequests, <List<String>>[
        <String>['ordinary-parent'],
      ]);
      expect(mediaRepo.singleRequests, <String>['ordinary-parent']);
      expect(mediaFileManager.resolveStoredPathCount, 0);

      final byId = {for (final message in item!.messages) message.id: message};
      for (final id in const <String>['private-parent', 'unsupported-parent']) {
        expect(byId[id]!.text, 'Media unavailable');
        expect(byId[id]!.quotedMessageId, isNull);
        expect(byId[id]!.media, isEmpty);
      }
      expect(byId['ordinary-parent']!.text, 'ordinary caption');
      expect(
        byId['ordinary-parent']!.quotedMessageId,
        'ordinary-quoted-parent',
      );
      expect(byId['ordinary-parent']!.media.single.id, 'ordinary-attachment');
    },
  );

  test(
    'TC-161-09a: paged group snapshot yields a correct GroupThreadFeedItem '
    '(hasReply true, multi-message preview, NOT a single summary row)',
    () async {
      final groupRepo = InMemoryGroupRepository()..saveGroup(_group('g1'));
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final base = DateTime.utc(2026, 3, 1, 12);
      await groupMsgRepo.saveMessage(
        _msg(
          id: 'm1',
          groupId: 'g1',
          text: 'hi',
          timestamp: base,
          isIncoming: true,
          readAt: base.add(const Duration(minutes: 1)),
        ),
      );
      await groupMsgRepo.saveMessage(
        _msg(
          id: 'm2',
          groupId: 'g1',
          text: 'my reply',
          timestamp: base.add(const Duration(minutes: 2)),
          isIncoming: false,
        ),
      );
      await groupMsgRepo.saveMessage(
        _msg(
          id: 'm3',
          groupId: 'g1',
          text: 'and again',
          timestamp: base.add(const Duration(minutes: 3)),
          isIncoming: true,
        ),
      );

      final item = await loadGroupFeedSnapshot(
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        groupId: 'g1',
        pageSize: 30,
      );

      expect(item, isNotNull);
      expect(item!.messages.length, 3);
      expect(item.hasSentMessage, isTrue);
      expect(item.latestMessage.id, 'm3');
    },
  );

  test(
    'TC-161-09b: paged group snapshot caps NEWEST-first; total comes from the '
    'summary, not the page size',
    () async {
      final groupRepo = InMemoryGroupRepository()..saveGroup(_group('g1'));
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final base = DateTime.utc(2026, 3, 1, 12);
      for (var i = 0; i < 10; i++) {
        await groupMsgRepo.saveMessage(
          _msg(
            id: 'm$i',
            groupId: 'g1',
            text: 'msg $i',
            timestamp: base.add(Duration(minutes: i)),
            isIncoming: true,
          ),
        );
      }

      final item = await loadGroupFeedSnapshot(
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        groupId: 'g1',
        pageSize: 4,
      );

      expect(item, isNotNull);
      expect(item!.messages.length, 4);
      expect(item.latestMessage.id, 'm9');
      // totalMessageCount from the summary (10), not the page size (4).
      expect(item.totalMessageCount, 10);
      expect(item.hasEarlierHistory, isTrue);
    },
  );

  test(
    'TC-161-14: a focused group reply survives the windowed/summary-backed '
    'snapshot (append-stay: the just-sent reply is NOT blanked/dropped)',
    () async {
      final groupRepo = InMemoryGroupRepository()..saveGroup(_group('g1'));
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final base = DateTime.utc(2026, 3, 1, 12);
      // A pending group: several unread incoming...
      for (var i = 0; i < 3; i++) {
        await groupMsgRepo.saveMessage(
          _msg(
            id: 'u$i',
            groupId: 'g1',
            text: 'unread $i',
            timestamp: base.add(Duration(minutes: i)),
            isIncoming: true,
          ),
        );
      }
      // ...then the user replies in-feed (newest). Read-mark is deferred to
      // leave, so the unread incoming stay unread → the group is "answered".
      await groupMsgRepo.saveMessage(
        _msg(
          id: 'reply-1',
          groupId: 'g1',
          text: 'in-feed reply',
          timestamp: base.add(const Duration(minutes: 10)),
          isIncoming: false,
        ),
      );

      final item = await loadGroupFeedSnapshot(
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        groupId: 'g1',
        pageSize: 50,
      );

      // The focused card's item must survive (non-null) and still render the
      // just-sent reply — under the window + pending-filter the snapshot must
      // NOT blank the focused body.
      expect(item, isNotNull);
      expect(
        item!.messages.any((m) => m.id == 'reply-1'),
        isTrue,
        reason: 'the focused reply must stay in the snapshot',
      );
      expect(item.hasSentMessage, isTrue);
      expect(item.latestMessage.id, 'reply-1');
    },
  );
}
