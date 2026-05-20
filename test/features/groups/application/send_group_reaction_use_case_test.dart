import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_group_reaction_replay_outbox_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../test/features/conversation/domain/repositories/fake_reaction_repository.dart';

Map<String, dynamic> _replayEnvelopeFromRetryPayload(String retryPayload) {
  final payload = jsonDecode(retryPayload) as Map<String, dynamic>;
  return jsonDecode(payload['message'] as String) as Map<String, dynamic>;
}

void _expectSignedReactionReplayEnvelope(Map<String, dynamic> envelope) {
  expect(envelope['kind'], 'group_offline_replay');
  expect(envelope['payloadType'], 'group_reaction');
  expect(envelope['senderPeerId'], 'peer-1');
  expect(envelope['senderPublicKey'], 'pk-1');
  expect(envelope['signatureAlgorithm'], 'ed25519');
  expect(envelope['signedPayload'], isA<String>());
  expect(envelope['signature'], isA<String>());
  final signedPayload =
      jsonDecode(envelope['signedPayload'] as String) as Map<String, dynamic>;
  expect(signedPayload['kind'], 'group_offline_replay');
  expect(signedPayload['payloadType'], 'group_reaction');
  expect(signedPayload['senderPeerId'], 'peer-1');
  expect(signedPayload['senderSigningPublicKey'], 'pk-1');
  expect(signedPayload['messageId'], envelope['messageId']);
  expect(signedPayload['plaintextHash'], isA<String>());
}

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late FakeReactionRepository reactionRepo;
  late FakeGroupReactionReplayOutboxRepository reactionReplayOutboxRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-1',
    myRole: GroupRole.admin,
  );

  final testMember = GroupMember(
    groupId: 'group-1',
    peerId: 'peer-1',
    username: 'Alice',
    role: MemberRole.admin,
    joinedAt: DateTime.now().toUtc(),
  );

  final testMessage = GroupMessage(
    id: 'msg-1',
    groupId: 'group-1',
    senderPeerId: 'peer-2',
    senderUsername: 'Bob',
    text: 'Hello!',
    timestamp: DateTime.now().toUtc(),
    keyGeneration: 0,
    status: 'delivered',
    isIncoming: true,
    createdAt: DateTime.now().toUtc(),
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    reactionRepo = FakeReactionRepository();
    reactionReplayOutboxRepo = FakeGroupReactionReplayOutboxRepository();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(testMember);
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 0,
        encryptedKey: 'group-key-0',
        createdAt: DateTime.now().toUtc(),
      ),
    );
    await msgRepo.saveMessage(testMessage);

    bridge.responses['group:publishReaction'] = {'ok': true};
  });

  test('chat member can react', () async {
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-1',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
    );

    expect(result, SendGroupReactionResult.success);
    expect(reaction, isNotNull);
    expect(reaction!.emoji, '👍');
    expect(reaction.messageId, 'msg-1');
    expect(reaction.senderPeerId, 'peer-1');

    // Verify persisted
    final stored = await reactionRepo.getReactionsForMessage('msg-1');
    expect(stored, hasLength(1));
    expect(stored.first.emoji, '👍');
  });

  test(
    'PL-009 active member publishes reaction command and stores local reaction once',
    () async {
      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, SendGroupReactionResult.success);
      expect(reaction, isNotNull);
      expect(reaction!.messageId, 'msg-1');
      expect(reaction.senderPeerId, 'peer-1');
      expect(reaction.emoji, '🔥');

      final publishCommands = bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:publishReaction')
          .toList(growable: false);
      expect(publishCommands, hasLength(1));
      final payload = publishCommands.single['payload'] as Map<String, dynamic>;
      expect(payload['groupId'], 'group-1');
      expect(payload['senderPeerId'], 'peer-1');
      final reactionPayload =
          jsonDecode(payload['reactionPayload'] as String)
              as Map<String, dynamic>;
      expect(reactionPayload['messageId'], 'msg-1');
      expect(reactionPayload['senderPeerId'], 'peer-1');
      expect(reactionPayload['emoji'], '🔥');
      expect(reactionPayload['action'], 'add');

      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));
      expect(stored.single.senderPeerId, 'peer-1');
      expect(stored.single.emoji, '🔥');
      expect(reactionRepo.saveReactionCallCount, 1);
    },
  );

  test(
    'PL-010 removed member reaction send is rejected without publish or local mutation',
    () async {
      await groupRepo.removeMember('group-1', 'peer-1');

      final sentBefore = bridge.sentMessages.length;
      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, SendGroupReactionResult.notMember);
      expect(reaction, isNull);
      expect(bridge.sentMessages.length, sentBefore);
      expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
      expect(reactionRepo.saveReactionCallCount, 0);
      expect(reactionReplayOutboxRepo.entries, isEmpty);
    },
  );

  test(
    'PL-011 re-added member with current key publishes reaction and stores once',
    () async {
      final now = DateTime.now().toUtc();
      const charliePeerId = 'peer-charlie';
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie-old',
          mlKemPublicKey: 'mlkem-charlie-old',
          joinedAt: now.subtract(const Duration(minutes: 5)),
        ),
      );
      await groupRepo.removeMember('group-1', charliePeerId);
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'group-key-1',
          createdAt: now,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie-current',
          mlKemPublicKey: 'mlkem-charlie-current',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'device-charlie-current',
              transportPeerId: 'transport-charlie-current',
              deviceSigningPublicKey: 'pk-charlie-current',
              mlKemPublicKey: 'mlkem-charlie-current',
              keyPackageId: 'kp-charlie-current',
            ),
          ],
          joinedAt: now.add(const Duration(minutes: 1)),
        ),
      );
      await msgRepo.saveMessage(
        GroupMessage(
          id: 'pl011-target',
          groupId: 'group-1',
          senderPeerId: 'peer-1',
          senderUsername: 'Alice',
          text: 'PL-011 post-readd visible target',
          timestamp: now.add(const Duration(minutes: 2)),
          keyGeneration: 1,
          status: 'delivered',
          isIncoming: true,
          createdAt: now.add(const Duration(minutes: 2)),
        ),
      );

      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'pl011-target',
        emoji: '✅',
        senderPeerId: charliePeerId,
        senderPublicKey: 'pk-charlie-current',
        senderPrivateKey: 'sk-charlie-current',
      );

      expect(result, SendGroupReactionResult.success);
      expect(reaction, isNotNull);
      expect(reaction!.messageId, 'pl011-target');
      expect(reaction.senderPeerId, charliePeerId);
      expect(reaction.emoji, '✅');

      final publishCommands = bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:publishReaction')
          .toList(growable: false);
      expect(publishCommands, hasLength(1));
      final payload = publishCommands.single['payload'] as Map<String, dynamic>;
      expect(payload['groupId'], 'group-1');
      expect(payload['senderPeerId'], charliePeerId);
      expect(payload['senderDeviceId'], 'device-charlie-current');
      expect(payload['senderTransportPeerId'], 'transport-charlie-current');
      expect(payload['senderDevicePublicKey'], 'pk-charlie-current');
      expect(payload['senderKeyPackageId'], 'kp-charlie-current');
      final reactionPayload =
          jsonDecode(payload['reactionPayload'] as String)
              as Map<String, dynamic>;
      expect(reactionPayload['messageId'], 'pl011-target');
      expect(reactionPayload['senderPeerId'], charliePeerId);
      expect(reactionPayload['emoji'], '✅');
      expect(reactionPayload['action'], 'add');

      final stored = await reactionRepo.getReactionsForMessage('pl011-target');
      expect(stored, hasLength(1));
      expect(stored.single.id, reaction.id);
      expect(stored.single.senderPeerId, charliePeerId);
      expect(stored.single.emoji, '✅');
      expect(reactionRepo.saveReactionCallCount, 1);

      await pumpEventQueue();
      final entry = await reactionReplayOutboxRepo.getEntry(reaction.id);
      expect(entry, isNotNull);
      expect(entry!.deliveryStatus, GroupReactionReplayOutboxStatus.stored);
      final envelope = _replayEnvelopeFromRetryPayload(entry.inboxRetryPayload);
      expect(envelope['payloadType'], 'group_reaction');
      expect(envelope['keyEpoch'], 1);
      expect(envelope['senderPeerId'], charliePeerId);
      expect(envelope['senderDeviceId'], 'device-charlie-current');
      expect(envelope['senderTransportPeerId'], 'transport-charlie-current');
      expect(envelope['senderKeyPackageId'], 'kp-charlie-current');
    },
  );

  test('announcement member can react', () async {
    final announcementGroup = GroupModel(
      id: 'group-ann',
      name: 'Announcements',
      type: GroupType.announcement,
      topicName: 'group-topic-ann',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );
    await groupRepo.saveGroup(announcementGroup);
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-ann',
        keyGeneration: 0,
        encryptedKey: 'group-ann-key-0',
        createdAt: DateTime.now().toUtc(),
      ),
    );

    final readerMember = GroupMember(
      groupId: 'group-ann',
      peerId: 'peer-reader',
      username: 'Reader',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );
    await groupRepo.saveMember(readerMember);

    final adminMsg = GroupMessage(
      id: 'msg-ann-1',
      groupId: 'group-ann',
      senderPeerId: 'peer-admin',
      senderUsername: 'Admin',
      text: 'Announcement!',
      timestamp: DateTime.now().toUtc(),
      keyGeneration: 0,
      status: 'delivered',
      isIncoming: true,
      createdAt: DateTime.now().toUtc(),
    );
    await msgRepo.saveMessage(adminMsg);

    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-ann',
      messageId: 'msg-ann-1',
      emoji: '👍',
      senderPeerId: 'peer-reader',
      senderPublicKey: 'pk-reader',
      senderPrivateKey: 'sk-reader',
    );

    expect(result, SendGroupReactionResult.success);
    expect(reaction, isNotNull);
  });

  test(
    'dissolved chat group rejects reactions without publishing or storing',
    () async {
      await groupRepo.updateGroup(
        testGroup.copyWith(
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 22, 9),
          dissolvedBy: 'peer-1',
        ),
      );

      final sentBefore = bridge.sentMessages.length;
      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, SendGroupReactionResult.groupDissolved);
      expect(reaction, isNull);
      expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
      expect(reactionReplayOutboxRepo.entries, isEmpty);
      expect(bridge.sentMessages.length, sentBefore);
    },
  );

  test('dissolved announcement member cannot add a reaction', () async {
    final announcementGroup = GroupModel(
      id: 'group-ann-dissolved',
      name: 'Announcements',
      type: GroupType.announcement,
      topicName: 'group-topic-ann-dissolved',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
      isDissolved: true,
      dissolvedAt: DateTime.utc(2026, 4, 22, 10),
      dissolvedBy: 'peer-admin',
    );
    await groupRepo.saveGroup(announcementGroup);
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-ann-dissolved',
        keyGeneration: 0,
        encryptedKey: 'group-ann-dissolved-key-0',
        createdAt: DateTime.now().toUtc(),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-ann-dissolved',
        peerId: 'peer-reader',
        username: 'Reader',
        role: MemberRole.writer,
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await msgRepo.saveMessage(
      GroupMessage(
        id: 'msg-ann-dissolved-1',
        groupId: 'group-ann-dissolved',
        senderPeerId: 'peer-admin',
        senderUsername: 'Admin',
        text: 'Ended announcement',
        timestamp: DateTime.now().toUtc(),
        keyGeneration: 0,
        status: 'delivered',
        isIncoming: true,
        createdAt: DateTime.now().toUtc(),
      ),
    );

    final sentBefore = bridge.sentMessages.length;
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-ann-dissolved',
      messageId: 'msg-ann-dissolved-1',
      emoji: '🔥',
      senderPeerId: 'peer-reader',
      senderPublicKey: 'pk-reader',
      senderPrivateKey: 'sk-reader',
    );

    expect(result, SendGroupReactionResult.groupDissolved);
    expect(reaction, isNull);
    expect(
      await reactionRepo.getReactionsForMessage('msg-ann-dissolved-1'),
      isEmpty,
    );
    expect(bridge.sentMessages.length, sentBefore);
  });

  test('non-member is rejected', () async {
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-1',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'outsider',
      senderPublicKey: 'pk-out',
      senderPrivateKey: 'sk-out',
    );

    expect(result, SendGroupReactionResult.notMember);
    expect(reaction, isNull);
  });

  test('unknown messageId is rejected', () async {
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-1',
      messageId: 'nonexistent-msg',
      emoji: '👍',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
    );

    expect(result, SendGroupReactionResult.messageNotFound);
    expect(reaction, isNull);
  });

  test('unknown group is rejected', () async {
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'nonexistent',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
    );

    expect(result, SendGroupReactionResult.groupNotFound);
    expect(reaction, isNull);
  });

  test('publish failure returns publishFailed', () async {
    bridge.responses['group:publishReaction'] = {
      'ok': false,
      'errorCode': 'GROUP_ERROR',
    };

    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-1',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
    );

    expect(result, SendGroupReactionResult.publishFailed);
    expect(reaction, isNull);

    // Verify NOT persisted on failure
    final stored = await reactionRepo.getReactionsForMessage('msg-1');
    expect(stored, isEmpty);
  });

  test(
    'EK004 stores signed offline replay envelope for group_reaction add',
    () async {
      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, SendGroupReactionResult.success);
      expect(reaction, isNotNull);

      await pumpEventQueue();

      final entry = await reactionReplayOutboxRepo.getEntry(reaction!.id);
      expect(entry, isNotNull);
      expect(entry!.groupId, 'group-1');
      expect(entry.messageId, 'msg-1');
      expect(entry.senderPeerId, 'peer-1');
      expect(entry.emoji, '🔥');
      expect(entry.action, 'add');
      expect(entry.deliveryStatus, GroupReactionReplayOutboxStatus.stored);
      expect(bridge.commandLog, contains('group:inboxStore'));
      _expectSignedReactionReplayEnvelope(
        _replayEnvelopeFromRetryPayload(entry.inboxRetryPayload),
      );
    },
  );

  test(
    'replay store failure still returns success and leaves a failed durable row',
    () async {
      bridge.responses['group:inboxStore'] = {
        'ok': false,
        'errorCode': 'GROUP_INBOX_STORE_FAILED',
      };

      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '🔥',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, SendGroupReactionResult.success);
      expect(reaction, isNotNull);

      await pumpEventQueue();

      final entry = await reactionReplayOutboxRepo.getEntry(reaction!.id);
      expect(entry, isNotNull);
      expect(entry!.deliveryStatus, GroupReactionReplayOutboxStatus.failed);
      expect(entry.lastError, contains('GROUP_INBOX_STORE_FAILED'));

      final stored = await reactionRepo.getReactionsForMessage('msg-1');
      expect(stored, hasLength(1));
      expect(stored.single.id, reaction.id);
    },
  );
}
