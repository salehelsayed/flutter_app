import 'dart:convert';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

MediaAttachment _image(String messageId) => MediaAttachment(
  id: 'announcement-image-$messageId',
  messageId: messageId,
  mime: 'image/jpeg',
  size: 4096,
  mediaType: 'image',
  localPath: 'media/announcement-1/announcement-image-$messageId.jpg',
  downloadStatus: 'done',
  contentHash: _hash,
  encryptionKeyBase64: 'announcement-key',
  encryptionNonce: 'announcement-nonce',
  encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  createdAt: '2026-07-12T10:00:00.000Z',
);

Future<InMemoryGroupRepository> _announcementRepository({
  GroupRole localRole = GroupRole.admin,
  MemberRole senderRole = MemberRole.admin,
}) async {
  final repository = InMemoryGroupRepository();
  await repository.saveGroup(
    GroupModel(
      id: 'announcement-1',
      name: 'Announcement',
      type: GroupType.announcement,
      topicName: 'announcement-topic',
      createdAt: DateTime.utc(2026, 7, 12),
      createdBy: 'admin-peer',
      myRole: localRole,
    ),
  );
  await repository.saveKey(
    GroupKeyInfo(
      groupId: 'announcement-1',
      keyGeneration: 1,
      encryptedKey: 'announcement-group-key',
      createdAt: DateTime.utc(2026, 7, 12),
    ),
  );
  await repository.saveMember(
    GroupMember(
      groupId: 'announcement-1',
      peerId: 'admin-peer',
      username: 'Admin',
      role: senderRole,
      publicKey: 'pk-admin-peer',
      joinedAt: DateTime.utc(2026, 7, 12),
    ),
  );
  await repository.saveMember(
    GroupMember(
      groupId: 'announcement-1',
      peerId: 'reader-peer',
      username: 'Reader',
      role: MemberRole.reader,
      publicKey: 'pk-reader-peer',
      joinedAt: DateTime.utc(2026, 7, 12),
    ),
  );
  return repository;
}

Map<String, dynamic> _commandPayload(FakeBridge bridge, String command) {
  final commandMap = bridge.sentMessages
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .firstWhere((entry) => entry['cmd'] == command);
  return (commandMap['payload'] as Map).cast<String, dynamic>();
}

void _expectPrivateWireOnly(Map<String, dynamic> payload) {
  expect(payload['mediaPolicyVersion'], 1);
  expect(payload['mediaLifecycle'], 'viewOnce');
  expect(payload.containsKey('mediaDurationSeconds'), isTrue);
  expect(payload['mediaDurationSeconds'], isNull);
  expect(payload['mediaProtected'], isTrue);
  for (final localOnly in const <String>[
    'mediaReceivedAt',
    'mediaExpiresAt',
    'mediaLastCheckedAt',
    'mediaConsumedAt',
    'mediaExpiredAt',
    'mediaCleanupPending',
    'media_received_at',
    'media_expires_at',
    'media_consumed_at',
    'media_expired_at',
  ]) {
    expect(payload.containsKey(localOnly), isFalse, reason: localOnly);
  }
}

void main() {
  test(
    'APL-03 current admin policy matches send live offline retry qualification and legacy paths',
    () async {
      final groupRepository = await _announcementRepository();
      final messageRepository = InMemoryGroupMessageRepository();
      final mediaRepository = InMemoryMediaAttachmentRepository();
      final bridge = FakeBridge();

      final (result, sent) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepository,
        msgRepo: messageRepository,
        groupId: 'announcement-1',
        text: '',
        senderPeerId: 'admin-peer',
        senderPublicKey: 'pk-admin-peer',
        senderPrivateKey: 'sk-admin-peer',
        senderUsername: 'Admin',
        messageId: 'announcement-private-send',
        timestamp: DateTime.utc(2026, 7, 12, 10),
        privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
        mediaAttachments: <MediaAttachment>[
          _image('announcement-private-send'),
        ],
        mediaAttachmentRepo: mediaRepository,
      );

      expect(result, SendGroupMessageResult.success);
      expect(sent, isNotNull);
      expect(
        sent!.privateMediaPolicy,
        const GroupPrivateMediaPolicy.viewOnce(),
      );
      _expectPrivateWireOnly(_commandPayload(bridge, 'group:sendReliable'));
      _expectPrivateWireOnly(_commandPayload(bridge, 'group:publish'));
      final replayPlaintext =
          jsonDecode(
                _commandPayload(bridge, 'group.encrypt')['plaintext'] as String,
              )
              as Map<String, dynamic>;
      _expectPrivateWireOnly(replayPlaintext);

      expect(
        await requalifyCurrentPrivateGroupMediaSend(
          groupRepo: groupRepository,
          msgRepo: messageRepository,
          expectedParent: sent,
          senderPeerId: 'admin-peer',
        ),
        isTrue,
      );
      await groupRepository.updateMemberRole(
        'announcement-1',
        'admin-peer',
        MemberRole.writer,
      );
      expect(
        await requalifyCurrentPrivateGroupMediaSend(
          groupRepo: groupRepository,
          msgRepo: messageRepository,
          expectedParent: sent,
          senderPeerId: 'admin-peer',
        ),
        isFalse,
        reason: 'an announcement demotion closes every retry/re-drive boundary',
      );

      final receiveGroupRepository = await _announcementRepository();
      for (final source in const <String>['live', 'offline']) {
        final receiveMessageRepository = InMemoryGroupMessageRepository();
        final received = await handleIncomingGroupMessage(
          groupRepo: receiveGroupRepository,
          msgRepo: receiveMessageRepository,
          groupId: 'announcement-1',
          senderId: 'admin-peer',
          senderUsername: 'Admin',
          keyEpoch: 1,
          text: '',
          timestamp: '2026-07-12T10:00:00.000Z',
          selfPeerId: 'reader-peer',
          messageId: 'announcement-private-$source',
          privateMediaPolicyFields: const GroupPrivateMediaPolicy.viewOnce()
              .toWireExtras()!,
          media: <Map<String, dynamic>>[
            _image('announcement-private-$source').toJson(),
          ],
          mediaAttachmentRepo: mediaRepository,
          deliverySource: source,
        );
        expect(received, isNotNull, reason: source);
        expect(
          received!.privateMediaPolicy,
          const GroupPrivateMediaPolicy.viewOnce(),
          reason: source,
        );
        expect(received.mediaReceivedAt, isNotNull, reason: source);
        expect(received.mediaConsumedAt, isNull, reason: source);
      }

      final legacy = await handleIncomingGroupMessage(
        groupRepo: receiveGroupRepository,
        msgRepo: InMemoryGroupMessageRepository(),
        groupId: 'announcement-1',
        senderId: 'admin-peer',
        senderUsername: 'Admin',
        keyEpoch: 1,
        text: '',
        timestamp: '2026-07-12T10:01:00.000Z',
        selfPeerId: 'reader-peer',
        messageId: 'announcement-legacy',
        media: <Map<String, dynamic>>[_image('announcement-legacy').toJson()],
        mediaAttachmentRepo: mediaRepository,
      );
      expect(
        legacy!.privateMediaPolicy,
        const GroupPrivateMediaPolicy.ordinary(),
      );
    },
  );

  test(
    'APL-02 reader local role or non-admin roster role cannot publish private announcement media',
    () async {
      for (final roles in <(GroupRole, MemberRole)>[
        (GroupRole.member, MemberRole.reader),
        (GroupRole.admin, MemberRole.writer),
        (GroupRole.admin, MemberRole.reader),
      ]) {
        final repository = await _announcementRepository(
          localRole: roles.$1,
          senderRole: roles.$2,
        );
        final bridge = FakeBridge();
        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: repository,
          msgRepo: InMemoryGroupMessageRepository(),
          groupId: 'announcement-1',
          text: '',
          senderPeerId: 'admin-peer',
          senderPublicKey: 'pk-admin-peer',
          senderPrivateKey: 'sk-admin-peer',
          senderUsername: 'Admin',
          messageId: 'announcement-denied-${roles.$1.name}-${roles.$2.name}',
          timestamp: DateTime.utc(2026, 7, 12, 10),
          privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
          privateMediaAvailability:
              const GroupPrivateMediaAvailability.enabledForTesting(),
          mediaAttachments: <MediaAttachment>[_image('announcement-denied')],
          mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
        );
        expect(result, SendGroupMessageResult.unauthorized, reason: '$roles');
        expect(message, isNull, reason: '$roles');
        expect(bridge.commandLog, isEmpty, reason: '$roles');
      }
    },
  );

  test(
    'APL-02R announcement private inbox retry requalifies the current admin role',
    () async {
      final groups = await _announcementRepository();
      final messages = InMemoryGroupMessageRepository();
      final identity = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'admin-peer',
            publicKey: 'pk-admin-peer',
            privateKey: 'sk-admin-peer',
          ),
        );
      final timestamp = DateTime.utc(2026, 7, 12, 10);
      final parent = GroupMessage(
        id: 'announcement-private-retry',
        groupId: 'announcement-1',
        senderPeerId: 'admin-peer',
        senderUsername: 'Admin',
        text: '',
        timestamp: timestamp,
        keyGeneration: 1,
        status: 'sent',
        isIncoming: false,
        privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
        createdAt: timestamp,
        inboxStored: false,
        inboxRetryPayload: jsonEncode(<String, Object?>{
          'groupId': 'announcement-1',
          'message': 'encrypted-announcement-replay',
          'recipientPeerIds': <String>['reader-peer'],
        }),
      );
      await messages.saveMessage(parent);
      final allowedBridge = FakeBridge();
      expect(
        await retryFailedGroupInboxStores(
          bridge: allowedBridge,
          msgRepo: messages,
          groupRepo: groups,
          identityRepo: identity,
          privateMediaAvailability:
              const GroupPrivateMediaAvailability.enabledForTesting(),
        ),
        1,
      );
      expect(allowedBridge.commandLog, contains('group:inboxStore'));

      await messages.saveMessage(parent);
      await groups.updateMemberRole(
        'announcement-1',
        'admin-peer',
        MemberRole.writer,
      );
      final deniedBridge = FakeBridge();
      expect(
        await retryFailedGroupInboxStores(
          bridge: deniedBridge,
          msgRepo: messages,
          groupRepo: groups,
          identityRepo: identity,
          privateMediaAvailability:
              const GroupPrivateMediaAvailability.enabledForTesting(),
        ),
        0,
      );
      expect(deniedBridge.commandLog, isEmpty);
    },
  );
}
