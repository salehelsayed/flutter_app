import 'dart:convert';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
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

const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

MediaAttachment _privateImage(String messageId) => MediaAttachment(
  id: 'private-image-$messageId',
  messageId: messageId,
  mime: 'image/jpeg',
  size: 4096,
  mediaType: 'image',
  localPath: 'media/group-1/private-image-$messageId.jpg',
  downloadStatus: 'done',
  contentHash: _hash,
  encryptionKeyBase64: 'private-key',
  encryptionNonce: 'private-nonce',
  encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  createdAt: '2026-07-12T10:00:00.000Z',
);

Future<void> _seedGroup(InMemoryGroupRepository repo) async {
  await repo.saveGroup(
    GroupModel(
      id: 'group-1',
      name: 'Private group',
      type: GroupType.chat,
      topicName: 'topic-1',
      createdAt: DateTime.utc(2026, 7, 12),
      createdBy: 'peer-self',
      myRole: GroupRole.admin,
    ),
  );
  await repo.saveKey(
    GroupKeyInfo(
      groupId: 'group-1',
      keyGeneration: 1,
      encryptedKey: 'group-key',
      createdAt: DateTime.utc(2026, 7, 12),
    ),
  );
  for (final member in [
    const ('peer-self', 'Self', MemberRole.writer),
    const ('peer-other', 'Other', MemberRole.writer),
  ]) {
    await repo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: member.$1,
        username: member.$2,
        role: member.$3,
        publicKey: 'pk-${member.$1}',
        joinedAt: DateTime.utc(2026, 7, 12),
      ),
    );
  }
}

Map<String, dynamic> _commandPayload(FakeBridge bridge, String command) {
  final commandMap = bridge.sentMessages
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .firstWhere((entry) => entry['cmd'] == command);
  return (commandMap['payload'] as Map).cast<String, dynamic>();
}

void _expectOnlySenderPolicy(Map<String, dynamic> payload) {
  expect(payload['mediaPolicyVersion'], 1);
  expect(payload['mediaLifecycle'], 'viewOnce');
  expect(payload.containsKey('mediaDurationSeconds'), isTrue);
  expect(payload['mediaDurationSeconds'], isNull);
  expect(payload['mediaProtected'], isTrue);
  for (final localOnly in const [
    'media_received_at',
    'media_expires_at',
    'media_last_checked_at',
    'media_consumed_at',
    'media_expired_at',
    'media_cleanup_pending',
    'mediaReceivedAt',
    'mediaExpiresAt',
    'mediaConsumedAt',
    'mediaExpiredAt',
  ]) {
    expect(payload.containsKey(localOnly), isFalse, reason: localOnly);
  }
}

void main() {
  test(
    'GPL-04 private policy roundtrips send retry live and offline without local lifecycle leakage',
    () async {
      final groupRepo = InMemoryGroupRepository();
      final sendRepo = InMemoryGroupMessageRepository();
      final mediaRepo = InMemoryMediaAttachmentRepository();
      final bridge = FakeBridge();
      await _seedGroup(groupRepo);

      final disabledBridge = FakeBridge();
      final disabledRepo = InMemoryGroupMessageRepository();
      final (disabledResult, disabledMessage) = await sendGroupMessage(
        bridge: disabledBridge,
        groupRepo: groupRepo,
        msgRepo: disabledRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-self',
        senderPublicKey: 'pk-peer-self',
        senderPrivateKey: 'sk-peer-self',
        senderUsername: 'Self',
        messageId: 'private-disabled',
        timestamp: DateTime.utc(2026, 7, 12, 10),
        mediaAttachments: [_privateImage('private-disabled')],
        mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
        privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.disabled(),
      );
      expect(disabledResult, SendGroupMessageResult.unauthorized);
      expect(disabledMessage, isNull);
      expect(await disabledRepo.getMessage('private-disabled'), isNull);
      expect(disabledBridge.commandLog, isEmpty);

      final (result, sent) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: sendRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-self',
        senderPublicKey: 'pk-peer-self',
        senderPrivateKey: 'sk-peer-self',
        senderUsername: 'Self',
        messageId: 'private-message',
        timestamp: DateTime.utc(2026, 7, 12, 10),
        mediaAttachments: [_privateImage('private-message')],
        mediaAttachmentRepo: mediaRepo,
        privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
      );

      expect(result, SendGroupMessageResult.success);
      expect(sent!.mediaPolicy, const GroupPrivateMediaPolicy.viewOnce());
      expect(
        (await sendRepo.getMessage('private-message'))!.mediaPolicy,
        const GroupPrivateMediaPolicy.viewOnce(),
      );

      _expectOnlySenderPolicy(_commandPayload(bridge, 'group:sendReliable'));
      _expectOnlySenderPolicy(_commandPayload(bridge, 'group:publish'));
      final replayPlaintext =
          jsonDecode(
                _commandPayload(bridge, 'group.encrypt')['plaintext'] as String,
              )
              as Map<String, dynamic>;
      _expectOnlySenderPolicy(replayPlaintext);

      for (final source in const ['live', 'replay']) {
        final receiveRepo = InMemoryGroupMessageRepository();
        final received = await handleIncomingGroupMessage(
          groupRepo: groupRepo,
          msgRepo: receiveRepo,
          groupId: 'group-1',
          senderId: 'peer-other',
          senderUsername: 'Other',
          keyEpoch: 1,
          text: '',
          timestamp: '2026-07-12T10:00:00.000Z',
          selfPeerId: 'peer-self',
          messageId: 'private-$source',
          media: [_privateImage('private-$source').toJson()],
          mediaAttachmentRepo: mediaRepo,
          privateMediaPolicyFields: const GroupPrivateMediaPolicy.viewOnce()
              .toWireExtras()!,
          deliverySource: source,
        );

        expect(received, isNotNull, reason: source);
        expect(
          received!.mediaPolicy,
          const GroupPrivateMediaPolicy.viewOnce(),
          reason: source,
        );
        expect(received.mediaReceivedAt, isNotNull, reason: source);
        expect(received.mediaExpiresAt, isNull, reason: source);
        expect(received.mediaConsumedAt, isNull, reason: source);
        expect(received.mediaExpiredAt, isNull, reason: source);
        final durable = await receiveRepo.getMessage('private-$source');
        expect(durable!.mediaPolicy, received.mediaPolicy, reason: source);
      }

      final storedMedia = await mediaRepo.getAttachmentsForMessage(
        'private-message',
        owner: MediaOwnerLane.group,
      );
      expect(storedMedia, hasLength(1));
    },
  );

  test(
    'GPL-07O publish failure still anchors disappearing media at independent inbox custody',
    () async {
      for (final reliable in <bool>[true, false]) {
        final groupRepo = InMemoryGroupRepository();
        final messageRepo = InMemoryGroupMessageRepository();
        final mediaRepo = InMemoryMediaAttachmentRepository();
        final bridge = FakeBridge();
        await _seedGroup(groupRepo);

        final messageId = reliable
            ? 'private-custody-reliable-failure'
            : 'private-custody-fallback-failure';
        final anchoredAt = reliable ? 5000 : 7000;
        if (reliable) {
          bridge.responses['group:sendReliable'] = <String, dynamic>{
            'ok': false,
            'errorCode': 'PUBLISH_FAILED',
            'publishSucceeded': false,
            'inboxStored': true,
            'expectedRecipientCount': 1,
            'topicPeerCount': 0,
          };
        } else {
          // FakeBridge's incomplete reliable response selects the legacy
          // publish + inbox fallback path. The inbox command succeeds by
          // default while this live publish fails definitively.
          bridge.responses['group:publish'] = <String, dynamic>{
            'ok': false,
            'errorCode': 'PUBLISH_FAILED',
          };
        }

        final (result, returned) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: messageRepo,
          groupId: 'group-1',
          text: '',
          senderPeerId: 'peer-self',
          senderPublicKey: 'pk-peer-self',
          senderPrivateKey: 'sk-peer-self',
          senderUsername: 'Self',
          messageId: messageId,
          timestamp: DateTime.utc(2026, 7, 12, 10),
          mediaAttachments: <MediaAttachment>[_privateImage(messageId)],
          mediaAttachmentRepo: mediaRepo,
          privateMediaPolicy: GroupPrivateMediaPolicy.disappearing(3600),
          privateMediaAvailability:
              const GroupPrivateMediaAvailability.enabledForTesting(),
          privateMediaNowMs: () => anchoredAt,
        );

        expect(result, SendGroupMessageResult.error, reason: '$reliable');
        expect(returned, isNotNull, reason: '$reliable');
        expect(returned!.status, 'failed', reason: '$reliable');
        expect(returned.inboxStored, isTrue, reason: '$reliable');
        expect(returned.mediaReceivedAt, anchoredAt, reason: '$reliable');
        expect(
          returned.mediaExpiresAt,
          anchoredAt + 3600 * 1000,
          reason: '$reliable',
        );
        expect(returned.mediaLastCheckedAt, anchoredAt, reason: '$reliable');

        final durable = await messageRepo.getMessage(messageId);
        expect(durable!.mediaReceivedAt, anchoredAt, reason: '$reliable');
        expect(
          durable.mediaExpiresAt,
          anchoredAt + 3600 * 1000,
          reason: '$reliable',
        );
      }
    },
  );
}
