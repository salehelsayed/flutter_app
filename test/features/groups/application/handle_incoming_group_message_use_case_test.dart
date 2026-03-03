import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';

void main() {
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  final testMember = GroupMember(
    groupId: 'group-1',
    peerId: 'peer-sender',
    username: 'Sender',
    role: MemberRole.writer,
    joinedAt: DateTime.now().toUtc(),
  );

  setUp(() async {
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(testMember);
  });

  test('handles incoming message successfully', () async {
    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Hello from sender!',
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );

    expect(result, isNotNull);
    expect(result!.text, 'Hello from sender!');
    expect(result.isIncoming, true);
    expect(result.senderPeerId, 'peer-sender');
  });

  test('ignores message for unknown group', () async {
    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'nonexistent-group',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Hello',
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );

    expect(result, isNull);
  });

  test('saves message to repo', () async {
    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Test message',
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );

    expect(msgRepo.count, 1);
    final latest = await msgRepo.getLatestMessage('group-1');
    expect(latest, isNotNull);
    expect(latest!.text, 'Test message');
  });

  test('still processes messages from unknown members', () async {
    // Message from non-member (stale member list)
    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'unknown-peer',
      senderUsername: 'Unknown',
      keyEpoch: 0,
      text: 'Hello from unknown',
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );

    expect(result, isNotNull);
    expect(result!.text, 'Hello from unknown');
    expect(msgRepo.count, 1);
  });

  test('deduplicates identical incoming messages', () async {
    final ts = DateTime.now().toUtc().toIso8601String();

    final result1 = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Hello!',
      timestamp: ts,
    );
    expect(result1, isNotNull);

    // Second call with same fields
    final result2 = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Hello!',
      timestamp: ts,
    );
    expect(result2, isNull); // duplicate → skipped
    expect(msgRepo.count, 1); // still only 1 message
  });

  test('allows messages with different text or timestamp', () async {
    final ts1 = DateTime(2026, 1, 1).toUtc().toIso8601String();
    final ts2 = DateTime(2026, 1, 2).toUtc().toIso8601String();

    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'A',
      timestamp: ts1,
    );
    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'B',
      timestamp: ts1,
    ); // different text
    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'A',
      timestamp: ts2,
    ); // different time

    expect(msgRepo.count, 3); // all unique
  });
}
