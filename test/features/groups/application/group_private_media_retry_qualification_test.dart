import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
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

class _ThrowingRosterRepository extends InMemoryGroupRepository {
  @override
  Future<List<GroupMember>> getMembers(String groupId) {
    throw StateError('roster unavailable');
  }
}

class _RevokingReliableBridge extends FakeBridge {
  _RevokingReliableBridge(this.onReliableSend);

  final Future<void> Function() onReliableSend;
  var _revoked = false;

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    if (!_revoked && decoded['cmd'] == 'group:sendReliable') {
      _revoked = true;
      await onReliableSend();
    }
    return super.send(message);
  }
}

class _GatedPrivateAttachmentReadRepository
    extends InMemoryMediaAttachmentRepository {
  final Completer<void> readStarted = Completer<void>();
  final Completer<void> releaseRead = Completer<void>();
  bool armed = false;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    if (armed) {
      if (!readStarted.isCompleted) readStarted.complete();
      await releaseRead.future;
    }
    return super.getAttachmentsForMessage(messageId, owner: owner);
  }
}

GroupMessage _privateParent({
  String id = 'private-parent',
  List<String> recipientPeerIds = const ['peer-other'],
}) {
  final timestamp = DateTime.utc(2026, 7, 12, 10);
  return GroupMessage(
    id: id,
    groupId: 'group-1',
    senderPeerId: 'peer-self',
    senderUsername: 'Self',
    text: '',
    timestamp: timestamp,
    keyGeneration: 1,
    status: 'sent',
    isIncoming: false,
    createdAt: timestamp,
    privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
    wireEnvelope: jsonEncode({
      'groupId': 'group-1',
      'messageId': id,
      'mediaPolicyVersion': 1,
      'mediaLifecycle': 'viewOnce',
      'mediaDurationSeconds': null,
      'mediaProtected': true,
    }),
    inboxRetryPayload: jsonEncode({
      'groupId': 'group-1',
      'message': jsonEncode({
        'kind': 'group_offline_replay',
        'version': 1,
        'payloadType': 'group_message',
        'keyEpoch': 1,
        'messageId': id,
        'ciphertext': 'ciphertext',
        'nonce': 'nonce',
      }),
      'recipientPeerIds': recipientPeerIds,
    }),
  );
}

GroupModel _group({GroupType type = GroupType.chat, bool dissolved = false}) =>
    GroupModel(
      id: 'group-1',
      name: 'Group',
      type: type,
      topicName: 'topic-1',
      createdAt: DateTime.utc(2026, 7, 12),
      createdBy: 'peer-self',
      myRole: GroupRole.admin,
      isDissolved: dissolved,
      dissolvedAt: dissolved ? DateTime.utc(2026, 7, 12, 9) : null,
      dissolvedBy: dissolved ? 'peer-self' : null,
    );

Future<InMemoryGroupRepository> _qualifiedRepo({
  MemberRole role = MemberRole.writer,
  GroupType type = GroupType.chat,
  bool includeSelf = true,
  bool includeKey = true,
  bool includeOther = false,
  bool includeIncumbent = false,
  bool dissolved = false,
}) async {
  final repo = InMemoryGroupRepository();
  await repo.saveGroup(_group(type: type, dissolved: dissolved));
  if (includeSelf) {
    await repo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-self',
        role: role,
        publicKey: 'pk-peer-self',
        joinedAt: DateTime.utc(2026, 7, 12),
      ),
    );
  }
  if (includeOther) {
    await repo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-other',
        role: MemberRole.reader,
        publicKey: 'pk-peer-other',
        joinedAt: DateTime.utc(2026, 7, 12),
      ),
    );
  }
  if (includeIncumbent) {
    // Plan 318 widened the qualification to include unevidenced incumbents, so
    // this member lands in `current` but never in a pre-318 persisted set.
    await repo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-incumbent',
        role: MemberRole.reader,
        publicKey: 'pk-peer-incumbent',
        joinedAt: DateTime.utc(2026, 7, 12),
      ),
    );
  }
  if (includeKey) {
    await repo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 1,
        encryptedKey: 'group-key',
        createdAt: DateTime.utc(2026, 7, 12),
      ),
    );
  }
  return repo;
}

MediaAttachment _privateAttachment(String messageId) => MediaAttachment(
  id: 'private-attachment-$messageId',
  messageId: messageId,
  mime: 'image/jpeg',
  size: 128,
  mediaType: 'image',
  localPath: '/tmp/private-$messageId.jpg',
  downloadStatus: 'done',
  createdAt: '2026-07-12T10:00:00.000Z',
  contentHash:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  encryptionKeyBase64: 'private-key',
  encryptionNonce: 'private-nonce',
  encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
);

void main() {
  test(
    'private media qualification recipient set includes unevidenced incumbents',
    () async {
      // Plan 318 TC-318-09: qualification shares the F7 seam. On HEAD the
      // admin-tracker arm plus this device's own join-timeline entry dropped
      // the unevidenced incumbent eve from the private-media recipient set.
      final parent = _privateParent(id: 'f7-qualification-parent');
      final groupRepo = await _qualifiedRepo();
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-incumbent-eve',
          role: MemberRole.reader,
          publicKey: 'pk-eve-incumbent',
          joinedAt: DateTime.utc(2026, 7, 11),
        ),
      );
      final msgRepo = InMemoryGroupMessageRepository();
      await msgRepo.saveMessage(parent);
      await msgRepo.saveMessage(
        buildMemberJoinedTimelineMessage(
          groupId: 'group-1',
          joinedPeerId: 'peer-self',
          joinedUsername: 'Self',
          eventAt: DateTime.utc(2026, 7, 12, 9),
        ),
      );

      final qualification = await qualifyCurrentPrivateGroupMediaSend(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        expectedParent: parent,
        senderPeerId: 'peer-self',
      );

      expect(qualification, isNotNull);
      expect(
        qualification!.recipientPeerIds,
        unorderedEquals(<String>['peer-incumbent-eve']),
      );
    },
  );

  test(
    'GPL-03E private requalification rejects every changed dispatch-bearing durable field',
    () async {
      final parent = _privateParent(id: 'exact-private-parent');
      final groupRepo = await _qualifiedRepo(includeOther: true);
      final msgRepo = InMemoryGroupMessageRepository();
      await msgRepo.saveMessage(parent);
      expect(
        await requalifyCurrentPrivateGroupMediaSend(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          expectedParent: parent,
          senderPeerId: 'peer-self',
        ),
        isTrue,
      );

      final changed = <String, GroupMessage>{
        'transportPeerId': parent.copyWith(transportPeerId: 'device-other'),
        'senderUsername': parent.copyWith(senderUsername: 'Changed sender'),
        'text': parent.copyWith(text: 'forbidden private caption'),
        'timestamp': parent.copyWith(
          timestamp: parent.timestamp.add(const Duration(seconds: 1)),
        ),
        'lastSendAttemptAt': parent.copyWith(
          lastSendAttemptAt: DateTime.utc(2026, 7, 12, 10, 1),
        ),
        'quotedMessageId': parent.copyWith(quotedMessageId: 'other-parent'),
        'logicalDeliveryId': parent.copyWith(
          logicalDeliveryId: 'other-logical',
        ),
        'keyGeneration': parent.copyWith(keyGeneration: 2),
        'status': parent.copyWith(status: 'pending'),
        'isForwarded': parent.copyWith(isForwarded: true),
        'createdAt': parent.copyWith(
          createdAt: parent.createdAt.add(const Duration(seconds: 1)),
        ),
        'wireEnvelope': parent.copyWith(wireEnvelope: '{"changed":true}'),
        'inboxStored': parent.copyWith(inboxStored: true),
        'inboxRetryPayload': parent.copyWith(
          inboxRetryPayload: '{"changed":true}',
        ),
      };

      for (final entry in changed.entries) {
        await msgRepo.saveMessage(entry.value);
        expect(
          await requalifyCurrentPrivateGroupMediaSend(
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            expectedParent: parent,
            senderPeerId: 'peer-self',
          ),
          isFalse,
          reason: entry.key,
        );
      }
    },
  );

  test(
    'GPL-03 private retries requalify current discussion membership before upload or fanout',
    () async {
      final parent = _privateParent();

      Future<bool> qualified(InMemoryGroupRepository groupRepo) async {
        final msgRepo = InMemoryGroupMessageRepository();
        await msgRepo.saveMessage(parent);
        return requalifyCurrentPrivateGroupMediaSend(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          expectedParent: parent,
          senderPeerId: 'peer-self',
        );
      }

      expect(await qualified(await _qualifiedRepo()), isTrue);
      expect(
        await qualified(await _qualifiedRepo(role: MemberRole.admin)),
        isTrue,
      );
      expect(
        await qualified(await _qualifiedRepo(role: MemberRole.reader)),
        isFalse,
      );
      expect(
        await qualified(await _qualifiedRepo(type: GroupType.announcement)),
        isFalse,
      );
      expect(await qualified(await _qualifiedRepo(dissolved: true)), isFalse);
      expect(
        await qualified(await _qualifiedRepo(includeSelf: false)),
        isFalse,
      );
      expect(await qualified(await _qualifiedRepo(includeKey: false)), isFalse);
      expect(await qualified(InMemoryGroupRepository()), isFalse);

      final throwingRepo = _ThrowingRosterRepository();
      await throwingRepo.saveGroup(_group());
      await throwingRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'group-key',
          createdAt: DateTime.utc(2026, 7, 12),
        ),
      );
      expect(await qualified(throwingRepo), isFalse);

      final msgRepo = InMemoryGroupMessageRepository();
      await msgRepo.saveMessage(parent);
      final bridge = FakeBridge();
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'peer-self',
            publicKey: 'pk-peer-self',
            privateKey: 'sk-peer-self',
          ),
        );
      final count = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: msgRepo,
        groupRepo: await _qualifiedRepo(role: MemberRole.reader),
        identityRepo: identityRepo,
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
      );
      expect(count, 0);
      expect(bridge.commandLog, isNot(contains('group:inboxStore')));
    },
  );

  test(
    'GPL-03C private failed-inbox replay requires persisted recipients equal current roster',
    () async {
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'peer-self',
            publicKey: 'pk-peer-self',
            privateKey: 'sk-peer-self',
          ),
        );

      final staleMessages = InMemoryGroupMessageRepository();
      await staleMessages.saveMessage(_privateParent(id: 'stale-recipient'));
      final staleBridge = FakeBridge();
      final staleCount = await retryFailedGroupInboxStores(
        bridge: staleBridge,
        msgRepo: staleMessages,
        groupRepo: await _qualifiedRepo(),
        identityRepo: identityRepo,
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
      );
      expect(staleCount, 0);
      expect(staleBridge.commandLog, isNot(contains('group:inboxStore')));

      final currentMessages = InMemoryGroupMessageRepository();
      await currentMessages.saveMessage(
        _privateParent(id: 'current-recipient'),
      );
      final currentBridge = FakeBridge();
      final currentCount = await retryFailedGroupInboxStores(
        bridge: currentBridge,
        msgRepo: currentMessages,
        groupRepo: await _qualifiedRepo(includeOther: true),
        identityRepo: identityRepo,
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
      );
      expect(currentCount, 1);
      expect(currentBridge.commandLog, contains('group:inboxStore'));
    },
  );

  test(
    'TC-323-02 subset persisted recipients are retry-eligible and replay frozen',
    () async {
      // Plan 323 (318 deferral B): plan 318 WIDENED the send qualification, so a
      // row staged before that upgrade holds a strict subset of today's set and
      // exact equality denied it forever. Subset containment restores it — and
      // the replay must still carry the FROZEN set, never the wider current one.
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'peer-self',
            publicKey: 'pk-peer-self',
            privateKey: 'sk-peer-self',
          ),
        );
      final messages = InMemoryGroupMessageRepository();
      await messages.saveMessage(_privateParent(id: 'subset-recipient'));
      final bridge = FakeBridge();

      final count = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: messages,
        groupRepo: await _qualifiedRepo(
          includeOther: true,
          includeIncumbent: true,
        ),
        identityRepo: identityRepo,
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
      );

      expect(count, 1);
      expect(bridge.commandLog, contains('group:inboxStore'));
      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      // Frozen, NOT widened: `peer-incumbent` is in the current qualification
      // but must never enter the stored ACL.
      expect(payload['recipientPeerIds'], equals(['peer-other']));
      expect(payload['preserveRecipientPeerIds'], isTrue);
    },
  );

  test(
    'TC-323-03 a persisted peer absent from the current set still denies retry',
    () async {
      // Direction pin. Subset must be checked persisted-in-current; the inverted
      // predicate (current subset-of persisted) would allow this and hand relay
      // custody of private media to a peer who is no longer qualified.
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'peer-self',
            publicKey: 'pk-peer-self',
            privateKey: 'sk-peer-self',
          ),
        );
      final messages = InMemoryGroupMessageRepository();
      await messages.saveMessage(
        _privateParent(
          id: 'departed-recipient',
          recipientPeerIds: const ['peer-other', 'peer-gone'],
        ),
      );
      final bridge = FakeBridge();

      final count = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: messages,
        groupRepo: await _qualifiedRepo(includeOther: true),
        identityRepo: identityRepo,
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
      );

      expect(count, 0);
      expect(bridge.commandLog, isNot(contains('group:inboxStore')));
    },
  );

  test(
    'TC-323-04 an empty persisted recipient set never becomes retry-eligible',
    () async {
      // `{} subset-of anything` would make the predicate a tautology. Both arms:
      // a non-empty current set (the tautology case) and an empty one (which
      // exact equality MATCHED today, buying a bridge call the relay rejects).
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'peer-self',
            publicKey: 'pk-peer-self',
            privateKey: 'sk-peer-self',
          ),
        );

      final wideMessages = InMemoryGroupMessageRepository();
      await wideMessages.saveMessage(
        _privateParent(id: 'empty-vs-wide', recipientPeerIds: const []),
      );
      final wideBridge = FakeBridge();
      final wideCount = await retryFailedGroupInboxStores(
        bridge: wideBridge,
        msgRepo: wideMessages,
        groupRepo: await _qualifiedRepo(includeOther: true),
        identityRepo: identityRepo,
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
      );
      expect(wideCount, 0);
      expect(wideBridge.commandLog, isNot(contains('group:inboxStore')));

      final emptyMessages = InMemoryGroupMessageRepository();
      await emptyMessages.saveMessage(
        _privateParent(id: 'empty-vs-empty', recipientPeerIds: const []),
      );
      final emptyBridge = FakeBridge();
      final emptyCount = await retryFailedGroupInboxStores(
        bridge: emptyBridge,
        msgRepo: emptyMessages,
        groupRepo: await _qualifiedRepo(),
        identityRepo: identityRepo,
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
      );
      expect(emptyCount, 0);
      expect(emptyBridge.commandLog, isNot(contains('group:inboxStore')));
    },
  );

  test(
    'TC-323-B5 a sender-inclusive persisted set stays retry-eligible',
    () async {
      // Sentinel for the second matcher arm. The send lane omits the sender from
      // the durable set by default, so a sender-inclusive persisted set is
      // legitimate; a rewrite keeping only `persisted subset-of current` would
      // silently deny every such legacy row with no other test going red.
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'peer-self',
            publicKey: 'pk-peer-self',
            privateKey: 'sk-peer-self',
          ),
        );
      final messages = InMemoryGroupMessageRepository();
      await messages.saveMessage(
        _privateParent(
          id: 'sender-inclusive',
          recipientPeerIds: const ['peer-other', 'peer-self'],
        ),
      );
      final bridge = FakeBridge();

      final count = await retryFailedGroupInboxStores(
        bridge: bridge,
        msgRepo: messages,
        groupRepo: await _qualifiedRepo(includeOther: true),
        identityRepo: identityRepo,
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
      );

      expect(count, 1);
      expect(bridge.commandLog, contains('group:inboxStore'));
    },
  );

  test(
    'GPL-03D private reliable fallback requalifies after the unavailable bridge call',
    () async {
      const messageId = 'private-fallback-revocation';
      final groupRepo = await _qualifiedRepo(includeOther: true);
      final msgRepo = InMemoryGroupMessageRepository();
      final mediaRepo = InMemoryMediaAttachmentRepository();
      final bridge =
          _RevokingReliableBridge(
              () => groupRepo.updateMemberRole(
                'group-1',
                'peer-self',
                MemberRole.reader,
              ),
            )
            ..responses['group:sendReliable'] = {
              'ok': false,
              'errorCode': 'UNKNOWN_COMMAND',
            };

      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-self',
        senderPublicKey: 'pk-peer-self',
        senderPrivateKey: 'sk-peer-self',
        senderUsername: 'Self',
        messageId: messageId,
        timestamp: DateTime.utc(2026, 7, 12, 10),
        privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
        mediaAttachments: [_privateAttachment(messageId)],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.unauthorized);
      expect(bridge.commandLog, contains('group:sendReliable'));
      expect(bridge.commandLog, isNot(contains('group:publish')));
      expect(bridge.commandLog, isNot(contains('group:inboxStore')));
    },
  );

  test(
    'GPL-03G private failed retry cannot replace a parent drifted during attachment await',
    () async {
      const messageId = 'private-retry-parent-drift';
      final attachment = _privateAttachment(messageId);
      final parent = _privateParent(id: messageId).copyWith(
        status: 'failed',
        wireEnvelope: jsonEncode({
          'groupId': 'group-1',
          'messageId': messageId,
          'media': [attachment.toJson()],
        }),
        inboxRetryPayload: jsonEncode({
          'groupId': 'group-1',
          'message': jsonEncode({
            'groupId': 'group-1',
            'messageId': messageId,
            'media': [attachment.toJson()],
          }),
          'recipientPeerIds': ['peer-other'],
        }),
      );
      final groupRepo = await _qualifiedRepo(includeOther: true);
      final msgRepo = InMemoryGroupMessageRepository();
      final mediaRepo = _GatedPrivateAttachmentReadRepository();
      final bridge = FakeBridge();
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'peer-self',
            publicKey: 'pk-peer-self',
            privateKey: 'sk-peer-self',
          ),
        );
      await msgRepo.saveMessage(parent);
      await mediaRepo.saveAttachment(attachment, owner: MediaOwnerLane.group);
      mediaRepo.armed = true;
      addTearDown(() {
        if (!mediaRepo.releaseRead.isCompleted) {
          mediaRepo.releaseRead.complete();
        }
      });

      final retry = retryFailedGroupMessage(
        messageId: messageId,
        groupMsgRepo: msgRepo,
        groupRepo: groupRepo,
        identityRepo: identityRepo,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        privateMediaAvailability:
            const GroupPrivateMediaAvailability.enabledForTesting(),
      );
      await mediaRepo.readStarted.future.timeout(const Duration(seconds: 10));

      await msgRepo.saveMessage(
        parent.copyWith(senderUsername: 'Drifted sender'),
      );
      mediaRepo.releaseRead.complete();

      expect(await retry, 0);
      expect(bridge.commandLog, isNot(contains('group:sendReliable')));
      expect(bridge.commandLog, isNot(contains('group:publish')));
      expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      final durable = await msgRepo.getMessage(messageId);
      expect(durable, isNotNull);
      expect(durable!.senderUsername, 'Drifted sender');
      final rows = await msgRepo.getMessagesPage('group-1');
      expect(rows, hasLength(1));
      expect(rows.single.id, messageId);
    },
  );
}
