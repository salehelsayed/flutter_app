import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../test/features/conversation/domain/repositories/fake_reaction_repository.dart';

void main() {
  late InMemoryGroupRepository groupRepo;
  late FakeReactionRepository reactionRepo;

  setUp(() async {
    groupRepo = InMemoryGroupRepository();
    reactionRepo = FakeReactionRepository();

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

    final member = GroupMember(
      groupId: 'group-1',
      peerId: 'peer-sender',
      username: 'Bob',
      role: MemberRole.writer,
      joinedAt: DateTime.now().toUtc(),
    );
    await groupRepo.saveMember(member);
  });

  String makeReactionJson({
    String id = 'r-1',
    String messageId = 'msg-1',
    String emoji = '👍',
    String action = 'add',
    String senderPeerId = 'peer-sender',
    String timestamp = '2026-03-08T00:00:00.000Z',
  }) {
    return jsonEncode({
      'id': id,
      'messageId': messageId,
      'emoji': emoji,
      'action': action,
      'senderPeerId': senderPeerId,
      'timestamp': timestamp,
    });
  }

  test('upserts reaction', () async {
    final (result, change) = await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: makeReactionJson(),
    );

    expect(result, HandleGroupReactionResult.success);
    expect(change, isNotNull);
    expect(change!.type, ReactionChangeType.upserted);
    expect(change.reaction!.emoji, '👍');

    final stored = await reactionRepo.getReactionsForMessage('msg-1');
    expect(stored, hasLength(1));
  });

  test('replaces prior emoji from same sender', () async {
    // First reaction: 👍
    await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: makeReactionJson(emoji: '👍'),
    );

    // Second reaction: ❤️ (same sender, should replace)
    final (result, change) = await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: makeReactionJson(id: 'r-2', emoji: '❤️'),
    );

    expect(result, HandleGroupReactionResult.success);
    expect(change!.reaction!.emoji, '❤️');

    final stored = await reactionRepo.getReactionsForMessage('msg-1');
    expect(stored, hasLength(1));
    expect(stored.first.emoji, '❤️');
  });

  test('removes reaction on remove action', () async {
    // Add first
    await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: makeReactionJson(),
    );

    // Remove
    final (result, change) = await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: makeReactionJson(id: 'r-remove', action: 'remove'),
    );

    expect(result, HandleGroupReactionResult.success);
    expect(change!.type, ReactionChangeType.removed);

    final stored = await reactionRepo.getReactionsForMessage('msg-1');
    expect(stored, isEmpty);
  });

  test('duplicate add reaction replay leaves one stored reaction', () async {
    final reactionJson = makeReactionJson(id: 'r-duplicate-add');

    final first = await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: reactionJson,
    );
    final second = await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: reactionJson,
    );

    expect(first.$1, HandleGroupReactionResult.success);
    expect(second.$1, HandleGroupReactionResult.success);
    expect(first.$2?.type, ReactionChangeType.upserted);
    expect(second.$2?.type, ReactionChangeType.upserted);

    final stored = await reactionRepo.getReactionsForMessage('msg-1');
    expect(stored, hasLength(1));
    expect(stored.single.id, 'r-duplicate-add');
    expect(stored.single.senderPeerId, 'peer-sender');
    expect(stored.single.emoji, '👍');
  });

  test('duplicate remove reaction replay leaves reaction absent', () async {
    await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: makeReactionJson(),
    );

    final removeJson = makeReactionJson(
      id: 'r-duplicate-remove',
      action: 'remove',
    );

    final first = await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: removeJson,
    );
    final second = await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: removeJson,
    );

    expect(first.$1, HandleGroupReactionResult.success);
    expect(second.$1, HandleGroupReactionResult.success);
    expect(first.$2?.type, ReactionChangeType.removed);
    expect(second.$2?.type, ReactionChangeType.removed);

    final stored = await reactionRepo.getReactionsForMessage('msg-1');
    expect(stored, isEmpty);
  });

  test('returns unknownGroup for nonexistent group', () async {
    final (result, change) = await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'nonexistent',
      senderId: 'peer-sender',
      reactionJson: makeReactionJson(),
    );

    expect(result, HandleGroupReactionResult.unknownGroup);
    expect(change, isNull);
  });

  test('returns parseError for invalid JSON', () async {
    final (result, change) = await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: 'not valid json',
    );

    expect(result, HandleGroupReactionResult.parseError);
    expect(change, isNull);
  });

  test(
    'rejects reaction from unknown sender without storing ghost reaction',
    () async {
      final (result, change) = await handleIncomingGroupReaction(
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        groupId: 'group-1',
        senderId: 'unknown-peer',
        reactionJson: makeReactionJson(senderPeerId: 'unknown-peer'),
      );

      expect(result, HandleGroupReactionResult.unknownSender);
      expect(change, isNull);
      expect(reactionRepo.reactions, isEmpty);
      expect(reactionRepo.saveReactionCallCount, 0);
    },
  );

  test('rejects add when payload sender mismatches outer sender', () async {
    final (result, change) = await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: makeReactionJson(senderPeerId: 'peer-other'),
    );

    expect(result, HandleGroupReactionResult.senderMismatch);
    expect(change, isNull);

    final stored = await reactionRepo.getReactionsForMessage('msg-1');
    expect(stored, isEmpty);
  });

  test('rejects remove when payload sender mismatches outer sender', () async {
    await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: makeReactionJson(),
    );

    final (result, change) = await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: makeReactionJson(
        id: 'r-remove-mismatch',
        action: 'remove',
        senderPeerId: 'peer-other',
      ),
    );

    expect(result, HandleGroupReactionResult.senderMismatch);
    expect(change, isNull);

    final stored = await reactionRepo.getReactionsForMessage('msg-1');
    expect(stored, hasLength(1));
    expect(stored.single.senderPeerId, 'peer-sender');
  });

  test('ignores add reactions at or after the dissolve cutoff', () async {
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
        dissolvedAt: DateTime.utc(2026, 4, 22, 12),
        dissolvedBy: 'peer-admin',
      ),
    );

    final (result, change) = await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: makeReactionJson(timestamp: '2026-04-22T12:00:00.000Z'),
    );

    expect(result, HandleGroupReactionResult.ignoredAfterDissolve);
    expect(change, isNull);
    expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
  });

  test('ignores remove reactions at or after the dissolve cutoff', () async {
    await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: makeReactionJson(timestamp: '2026-04-22T11:59:59.000Z'),
    );
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
        dissolvedAt: DateTime.utc(2026, 4, 22, 12),
        dissolvedBy: 'peer-admin',
      ),
    );

    final (result, change) = await handleIncomingGroupReaction(
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      reactionJson: makeReactionJson(
        id: 'r-remove-after-dissolve',
        action: 'remove',
        timestamp: '2026-04-22T12:00:00.000Z',
      ),
    );

    expect(result, HandleGroupReactionResult.ignoredAfterDissolve);
    expect(change, isNull);
    expect(await reactionRepo.getReactionsForMessage('msg-1'), hasLength(1));
  });

  test(
    'accepts late replayed reactions when the payload predates dissolve',
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
          dissolvedAt: DateTime.utc(2026, 4, 22, 12),
          dissolvedBy: 'peer-admin',
        ),
      );

      final (result, change) = await handleIncomingGroupReaction(
        groupRepo: groupRepo,
        reactionRepo: reactionRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        reactionJson: makeReactionJson(
          id: 'r-before-dissolve',
          timestamp: '2026-04-22T11:59:59.000Z',
        ),
      );

      expect(result, HandleGroupReactionResult.success);
      expect(change, isNotNull);
      expect(await reactionRepo.getReactionsForMessage('msg-1'), hasLength(1));
    },
  );
}
