import 'dart:convert';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _groupId = 'announcement-private-group';
const _senderPeerId = 'peer-admin';
const _readerPeerId = 'peer-reader';
const _contentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _RevokingSecondKeyReadRepository extends InMemoryGroupRepository {
  var keyReads = 0;

  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) async {
    final key = await super.getLatestKey(groupId);
    keyReads++;
    if (keyReads == 2) {
      final group = await super.getGroup(groupId);
      if (group != null) {
        await saveGroup(group.copyWith(myRole: GroupRole.member));
      }
      await updateMemberRole(groupId, _senderPeerId, MemberRole.writer);
    }
    return key;
  }
}

GroupModel _announcement({GroupRole localRole = GroupRole.admin}) => GroupModel(
  id: _groupId,
  name: 'Private announcements',
  type: GroupType.announcement,
  topicName: 'announcement-private-topic',
  createdAt: DateTime.utc(2026, 7, 12),
  createdBy: _senderPeerId,
  myRole: localRole,
);

Future<InMemoryGroupRepository> _seedAnnouncement({
  GroupRole localRole = GroupRole.admin,
  MemberRole senderRole = MemberRole.admin,
  InMemoryGroupRepository? target,
}) async {
  final repository = target ?? InMemoryGroupRepository();
  await repository.saveGroup(_announcement(localRole: localRole));
  await repository.saveKey(
    GroupKeyInfo(
      groupId: _groupId,
      keyGeneration: 1,
      encryptedKey: 'announcement-private-key',
      createdAt: DateTime.utc(2026, 7, 12),
    ),
  );
  await repository.saveMember(
    GroupMember(
      groupId: _groupId,
      peerId: _senderPeerId,
      username: 'Admin',
      role: senderRole,
      publicKey: 'pk-admin',
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
      joinedAt: DateTime.utc(2026, 7, 12, 0, 1),
    ),
  );
  return repository;
}

MediaAttachment _privateImage(String messageId) => MediaAttachment(
  id: 'private-image-$messageId',
  messageId: messageId,
  mime: 'image/jpeg',
  size: 4096,
  mediaType: 'image',
  localPath: 'media/$_groupId/private-image-$messageId.jpg',
  downloadStatus: 'done',
  contentHash: _contentHash,
  encryptionKeyBase64: 'private-key',
  encryptionNonce: 'private-nonce',
  encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  createdAt: '2026-07-12T10:00:00.000Z',
);

Map<String, dynamic> _commandPayload(FakeBridge bridge, String command) {
  final commandMap = bridge.sentMessages
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .firstWhere((entry) => entry['cmd'] == command);
  return (commandMap['payload'] as Map).cast<String, dynamic>();
}

void main() {
  test(
    'APL-02 current announcement admin publishes private media with encrypted-inner policy only',
    () async {
      const messageId = 'announcement-private-send';
      final groupRepo = await _seedAnnouncement();
      final messageRepo = InMemoryGroupMessageRepository();
      final mediaRepo = InMemoryMediaAttachmentRepository();
      final bridge = FakeBridge();

      final (result, sent) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: messageRepo,
        groupId: _groupId,
        text: '',
        senderPeerId: _senderPeerId,
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        senderUsername: 'Admin',
        messageId: messageId,
        timestamp: DateTime.utc(2026, 7, 12, 10),
        privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
        mediaAttachments: <MediaAttachment>[_privateImage(messageId)],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.success);
      expect(sent, isNotNull);
      expect(
        sent!.privateMediaPolicy,
        const GroupPrivateMediaPolicy.viewOnce(),
      );
      for (final command in const <String>[
        'group:sendReliable',
        'group:publish',
      ]) {
        final payload = _commandPayload(bridge, command);
        expect(payload['mediaPolicyVersion'], 1, reason: command);
        expect(payload['mediaLifecycle'], 'viewOnce', reason: command);
        expect(payload.containsKey('mediaDurationSeconds'), isTrue);
        expect(payload['mediaDurationSeconds'], isNull, reason: command);
        expect(payload['mediaProtected'], isTrue, reason: command);
        expect(payload.containsKey('mediaConsumedAt'), isFalse);
        expect(payload.containsKey('media_consumed_at'), isFalse);
      }
    },
  );

  test(
    'APL-02 announcement private authoring denies every mismatched current role before bridge work',
    () async {
      for (final scenario
          in <({String name, GroupRole localRole, MemberRole senderRole})>[
            (
              name: 'reader local row cannot borrow admin roster role',
              localRole: GroupRole.member,
              senderRole: MemberRole.admin,
            ),
            (
              name: 'stale admin local row cannot borrow writer roster role',
              localRole: GroupRole.admin,
              senderRole: MemberRole.writer,
            ),
            (
              name: 'reader is never an announcement private publisher',
              localRole: GroupRole.member,
              senderRole: MemberRole.reader,
            ),
          ]) {
        final groupRepo = await _seedAnnouncement(
          localRole: scenario.localRole,
          senderRole: scenario.senderRole,
        );
        final messageRepo = InMemoryGroupMessageRepository();
        final bridge = FakeBridge();
        final messageId = 'denied-${scenario.senderRole.name}';

        final (result, sent) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: messageRepo,
          groupId: _groupId,
          text: '',
          senderPeerId: _senderPeerId,
          senderPublicKey: 'pk-admin',
          senderPrivateKey: 'sk-admin',
          senderUsername: 'Admin',
          messageId: messageId,
          timestamp: DateTime.utc(2026, 7, 12, 10),
          privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
          privateMediaAvailability:
              const GroupPrivateMediaAvailability.enabledForTesting(),
          mediaAttachments: <MediaAttachment>[_privateImage(messageId)],
          mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
        );

        expect(
          result,
          SendGroupMessageResult.unauthorized,
          reason: scenario.name,
        );
        expect(sent, isNull, reason: scenario.name);
        expect(await messageRepo.getMessage(messageId), isNull);
        expect(bridge.commandLog, isEmpty, reason: scenario.name);
      }
    },
  );

  test(
    'APL-02 queued announcement retry requalifies demotion before publish or inbox work',
    () async {
      const messageId = 'announcement-private-retry';
      final groupRepo = await _seedAnnouncement();
      final messageRepo = InMemoryGroupMessageRepository();
      final mediaRepo = InMemoryMediaAttachmentRepository();
      final initialBridge = FakeBridge();
      final (_, sent) = await sendGroupMessage(
        bridge: initialBridge,
        groupRepo: groupRepo,
        msgRepo: messageRepo,
        groupId: _groupId,
        text: '',
        senderPeerId: _senderPeerId,
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        senderUsername: 'Admin',
        messageId: messageId,
        timestamp: DateTime.utc(2026, 7, 12, 10),
        privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
        mediaAttachments: <MediaAttachment>[_privateImage(messageId)],
        mediaAttachmentRepo: mediaRepo,
      );
      expect(sent, isNotNull);
      await messageRepo.saveMessage(sent!.copyWith(status: 'failed'));
      await groupRepo.updateMemberRole(
        _groupId,
        _senderPeerId,
        MemberRole.writer,
      );

      final retryBridge = FakeBridge();
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: _senderPeerId,
            publicKey: 'pk-admin',
            privateKey: 'sk-admin',
          ),
        );
      final count = await retryFailedGroupMessages(
        groupMsgRepo: messageRepo,
        groupRepo: groupRepo,
        identityRepo: identityRepo,
        bridge: retryBridge,
        mediaAttachmentRepo: mediaRepo,
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
      );

      expect(count, 0);
      expect(retryBridge.commandLog, isEmpty);
      expect((await messageRepo.getMessage(messageId))!.status, 'failed');
    },
  );

  test(
    'APL-02K final dispatch reloads admin authority after the awaited key read',
    () async {
      const messageId = 'announcement-private-key-race';
      final groupRepo = _RevokingSecondKeyReadRepository();
      await _seedAnnouncement(target: groupRepo);
      final messageRepo = InMemoryGroupMessageRepository();
      final bridge = FakeBridge();

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: messageRepo,
        groupId: _groupId,
        text: '',
        senderPeerId: _senderPeerId,
        senderPublicKey: 'pk-admin',
        senderPrivateKey: 'sk-admin',
        senderUsername: 'Admin',
        messageId: messageId,
        timestamp: DateTime.utc(2026, 7, 12, 10),
        privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
        mediaAttachments: <MediaAttachment>[_privateImage(messageId)],
        mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
      );

      expect(groupRepo.keyReads, 2);
      expect(result, SendGroupMessageResult.unauthorized);
      expect(message, isNotNull, reason: 'the optimistic row remains truthful');
      expect(message!.status, 'failed');
      expect(bridge.commandLog, isNot(contains('group:sendReliable')));
      expect(bridge.commandLog, isNot(contains('group:publish')));
      expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      expect((await groupRepo.getGroup(_groupId))!.myRole, GroupRole.member);
      expect(
        (await groupRepo.getMember(_groupId, _senderPeerId))!.role,
        MemberRole.writer,
      );
    },
  );
}
