import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../test/features/conversation/domain/repositories/fake_reaction_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late FakeReactionRepository reactionRepo;

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

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(testMember);
    await msgRepo.saveMessage(testMessage);

    bridge.responses['group:publishReaction'] = {'ok': true};
  });

  test('chat member can react', () async {
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
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

  test('non-member is rejected', () async {
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
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
}
