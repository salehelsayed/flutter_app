import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_group_reaction_replay_outbox_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
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

Future<T> _captureFlowEvents<T>(
  List<Map<String, dynamic>> events,
  Future<T> Function() action,
) async {
  debugSetFlowEventSink(events.add);
  try {
    return await action();
  } finally {
    debugSetFlowEventSink(null);
  }
}

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late FakeReactionRepository reactionRepo;
  late FakeGroupReactionReplayOutboxRepository reactionReplayOutboxRepo;

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    reactionRepo = FakeReactionRepository();
    reactionReplayOutboxRepo = FakeGroupReactionReplayOutboxRepository();

    final testGroup = GroupModel(
      id: 'group-1',
      name: 'Test Group',
      type: GroupType.chat,
      topicName: 'group-topic-1',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-1',
      myRole: GroupRole.admin,
    );
    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 0,
        encryptedKey: 'group-key-0',
        createdAt: DateTime.now().toUtc(),
      ),
    );

    final testMember = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-1',
      username: 'Alice',
      role: MemberRole.admin,
      joinedAt: DateTime.now().toUtc(),
    );
    await groupRepo.saveMember(testMember);

    bridge.responses['group:publishReaction'] = {'ok': true};

    // Seed an existing reaction
    await reactionRepo.saveReaction(
      MessageReaction(
        id: 'r-existing',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        timestamp: '2026-03-08T00:00:00.000Z',
        createdAt: '2026-03-08T00:00:00.000Z',
      ),
    );
  });

  test('removes own reaction', () async {
    // Verify reaction exists before
    final before = await reactionRepo.getReactionsForMessage('msg-1');
    expect(before, hasLength(1));

    final result = await removeGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-1',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
    );

    expect(result, RemoveGroupReactionResult.success);

    // Verify deleted locally
    final after = await reactionRepo.getReactionsForMessage('msg-1');
    expect(after, isEmpty);
  });

  test(
    'successful reaction remove emits queued local delivery contract',
    () async {
      final events = <Map<String, dynamic>>[];

      final result = await _captureFlowEvents(
        events,
        () => removeGroupReaction(
          bridge: bridge,
          groupRepo: groupRepo,
          reactionRepo: reactionRepo,
          reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          groupId: 'group-1',
          messageId: 'msg-1',
          emoji: '👍',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
        ),
      );

      expect(result, RemoveGroupReactionResult.success);
      expect(
        events.where(
          (event) => event['event'] == 'GROUP_REACTION_REMOVE_SUCCESS',
        ),
        isEmpty,
      );

      final queued = events.singleWhere(
        (event) => event['event'] == 'GROUP_REACTION_REMOVE_QUEUED',
      );
      final details = queued['details'] as Map<String, dynamic>;
      expect(details['deliveryMode'], 'live_publish_replay_queued');
      expect(details['deliveryConfirmed'], isFalse);
      expect(details['localState'], 'optimistic');
      expect(details['replayStatus'], 'pending');
    },
  );

  test('is idempotent when reaction absent', () async {
    final result = await removeGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-1',
      messageId: 'msg-1',
      emoji: '❤️', // different emoji, no reaction exists
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
    );

    expect(result, RemoveGroupReactionResult.success);
  });

  test('non-member is rejected', () async {
    final result = await removeGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      reactionReplayOutboxRepo: reactionReplayOutboxRepo,
      groupId: 'group-1',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'outsider',
      senderPublicKey: 'pk-out',
      senderPrivateKey: 'sk-out',
    );

    expect(result, RemoveGroupReactionResult.notMember);
  });

  test(
    'dissolved group rejects remove and preserves the stored reaction',
    () async {
      await groupRepo.updateGroup(
        GroupModel(
          id: 'group-1',
          name: 'Test Group',
          type: GroupType.chat,
          topicName: 'group-topic-1',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-1',
          myRole: GroupRole.admin,
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 22, 11),
          dissolvedBy: 'peer-1',
        ),
      );

      final sentBefore = bridge.sentMessages.length;
      final result = await removeGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, RemoveGroupReactionResult.groupDissolved);
      expect(await reactionRepo.getReactionsForMessage('msg-1'), hasLength(1));
      expect(reactionReplayOutboxRepo.entries, isEmpty);
      expect(bridge.sentMessages.length, sentBefore);
    },
  );

  test(
    'EK004 stores signed offline replay envelope for group_reaction remove',
    () async {
      final result = await removeGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, RemoveGroupReactionResult.success);

      await pumpEventQueue();

      final entry = reactionReplayOutboxRepo.entries.single;
      expect(entry.groupId, 'group-1');
      expect(entry.messageId, 'msg-1');
      expect(entry.senderPeerId, 'peer-1');
      expect(entry.emoji, '👍');
      expect(entry.action, 'remove');
      expect(entry.deliveryStatus, GroupReactionReplayOutboxStatus.stored);
      _expectSignedReactionReplayEnvelope(
        _replayEnvelopeFromRetryPayload(entry.inboxRetryPayload),
      );
    },
  );

  test(
    'remove replay store failure still returns success and leaves a failed durable row',
    () async {
      bridge.responses['group:inboxStore'] = {
        'ok': false,
        'errorCode': 'GROUP_INBOX_STORE_FAILED',
      };

      final result = await removeGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        groupId: 'group-1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
      );

      expect(result, RemoveGroupReactionResult.success);

      await pumpEventQueue();

      final entry = reactionReplayOutboxRepo.entries.single;
      expect(entry.deliveryStatus, GroupReactionReplayOutboxStatus.failed);
      expect(entry.lastError, contains('GROUP_INBOX_STORE_FAILED'));

      final after = await reactionRepo.getReactionsForMessage('msg-1');
      expect(after, isEmpty);
    },
  );
}
