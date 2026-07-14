import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

const _groupId = 'announcement-receive-auth';
const _senderPeerId = 'announcement-sender';
const _readerPeerId = 'announcement-reader';
const _contentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Future<InMemoryGroupRepository> _announcementRepository(
  MemberRole senderRole,
) async {
  final repository = InMemoryGroupRepository();
  await repository.saveGroup(
    GroupModel(
      id: _groupId,
      name: 'Announcement',
      type: GroupType.announcement,
      topicName: 'announcement-receive-auth-topic',
      createdAt: DateTime.utc(2026, 7, 12),
      createdBy: _senderPeerId,
      myRole: GroupRole.member,
    ),
  );
  await repository.saveMember(
    GroupMember(
      groupId: _groupId,
      peerId: _senderPeerId,
      username: 'Sender',
      role: senderRole,
      publicKey: 'pk-sender',
      joinedAt: DateTime.utc(2026, 7, 12),
    ),
  );
  await repository.saveMember(
    GroupMember(
      groupId: _groupId,
      peerId: _readerPeerId,
      username: 'Reader',
      role: MemberRole.reader,
      publicKey: 'pk-reader',
      joinedAt: DateTime.utc(2026, 7, 12),
    ),
  );
  return repository;
}

MediaAttachment _privateImage(String messageId) => MediaAttachment(
  id: 'attachment-$messageId',
  messageId: messageId,
  mime: 'image/jpeg',
  size: 4096,
  mediaType: 'image',
  downloadStatus: 'pending',
  contentHash: _contentHash,
  encryptionKeyBase64: 'private-key',
  encryptionNonce: 'private-nonce',
  encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  createdAt: '2026-07-12T10:00:00.000Z',
);

Future<void> _receivePrivateAnnouncement({
  required InMemoryGroupRepository groups,
  required InMemoryGroupMessageRepository messages,
  required InMemoryMediaAttachmentRepository media,
  required String source,
  required String messageId,
}) async {
  await handleIncomingGroupMessage(
    groupRepo: groups,
    msgRepo: messages,
    groupId: _groupId,
    senderId: _senderPeerId,
    senderUsername: 'Sender',
    keyEpoch: 1,
    text: '',
    timestamp: '2026-07-12T10:00:00.000Z',
    selfPeerId: _readerPeerId,
    messageId: messageId,
    privateMediaPolicyFields: const GroupPrivateMediaPolicy.viewOnce()
        .toWireExtras()!,
    media: <Map<String, dynamic>>[_privateImage(messageId).toJson()],
    mediaAttachmentRepo: media,
    deliverySource: source,
    nowUtc: () => DateTime.utc(2026, 7, 12, 10, 1),
  );
}

void main() {
  test(
    'APL-11 current non-admin announcement sender is rejected on live and offline receive before persistence',
    () async {
      for (final source in const <String>['live', 'offline']) {
        for (final senderRole in const <MemberRole>[
          MemberRole.writer,
          MemberRole.reader,
        ]) {
          final groups = await _announcementRepository(senderRole);
          final messages = InMemoryGroupMessageRepository();
          final media = InMemoryMediaAttachmentRepository();
          final messageId = 'denied-$source-${senderRole.name}';

          await _receivePrivateAnnouncement(
            groups: groups,
            messages: messages,
            media: media,
            source: source,
            messageId: messageId,
          );

          expect(
            await messages.getMessage(messageId),
            isNull,
            reason: '$source ${senderRole.name}',
          );
          expect(
            await media.getAttachmentsForMessage(
              messageId,
              owner: MediaOwnerLane.group,
            ),
            isEmpty,
            reason: '$source ${senderRole.name}',
          );
        }
      }
    },
  );

  test(
    'APL-03 current announcement admin remains accepted on live and offline receive',
    () async {
      for (final source in const <String>['live', 'offline']) {
        final groups = await _announcementRepository(MemberRole.admin);
        final messages = InMemoryGroupMessageRepository();
        final media = InMemoryMediaAttachmentRepository();
        final messageId = 'accepted-$source';

        await _receivePrivateAnnouncement(
          groups: groups,
          messages: messages,
          media: media,
          source: source,
          messageId: messageId,
        );

        final stored = await messages.getMessage(messageId);
        expect(stored, isNotNull, reason: source);
        expect(
          stored!.privateMediaPolicy,
          const GroupPrivateMediaPolicy.viewOnce(),
          reason: source,
        );
        expect(
          await media.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.group,
          ),
          hasLength(1),
          reason: source,
        );
      }
    },
  );

  test(
    'announcement system rows retain their existing receive semantics',
    () async {
      final groups = await _announcementRepository(MemberRole.reader);
      final messages = InMemoryGroupMessageRepository();

      final stored = await handleIncomingGroupMessage(
        groupRepo: groups,
        msgRepo: messages,
        groupId: _groupId,
        senderId: _senderPeerId,
        senderUsername: 'Sender',
        keyEpoch: 1,
        text: '{"__sys":"member_joined","peerId":"peer-new"}',
        timestamp: '2026-07-12T10:00:00.000Z',
        selfPeerId: _readerPeerId,
        messageId: 'announcement-system-row',
        deliverySource: 'offline',
        nowUtc: () => DateTime.utc(2026, 7, 12, 10, 1),
      );

      expect(stored, isNotNull);
      expect(await messages.getMessage('announcement-system-row'), isNotNull);
    },
  );
}
