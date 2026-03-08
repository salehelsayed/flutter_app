import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../test/features/conversation/domain/repositories/fake_reaction_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late FakeReactionRepository reactionRepo;

  setUp(() async {
    bridge = FakeBridge();
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
    await reactionRepo.saveReaction(MessageReaction(
      id: 'r-existing',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'peer-1',
      timestamp: '2026-03-08T00:00:00.000Z',
      createdAt: '2026-03-08T00:00:00.000Z',
    ));
  });

  test('removes own reaction', () async {
    // Verify reaction exists before
    final before = await reactionRepo.getReactionsForMessage('msg-1');
    expect(before, hasLength(1));

    final result = await removeGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
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

  test('is idempotent when reaction absent', () async {
    final result = await removeGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      reactionRepo: reactionRepo,
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
      groupId: 'group-1',
      messageId: 'msg-1',
      emoji: '👍',
      senderPeerId: 'outsider',
      senderPublicKey: 'pk-out',
      senderPrivateKey: 'sk-out',
    );

    expect(result, RemoveGroupReactionResult.notMember);
  });
}
