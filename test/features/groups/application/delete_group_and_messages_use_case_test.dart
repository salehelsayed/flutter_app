import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import '../../../../test/shared/fakes/in_memory_group_repository.dart';
import '../../../../test/shared/fakes/in_memory_group_message_repository.dart';
import '../../../../test/core/bridge/fake_bridge.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository groupMessageRepo;
  const groupId = 'test-group-id-12345';

  setUp(() {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    groupMessageRepo = InMemoryGroupMessageRepository();

    // Pre-configure bridge to respond to group:leave
    bridge.responses['group:leave'] = {'ok': true};
  });

  group('deleteGroupAndMessages', () {
    test('deletes group messages first, then calls leaveGroup', () async {
      // Save a group and some messages
      final now = DateTime.now().toUtc();
      await groupRepo.saveGroup(GroupModel(
        id: groupId,
        name: 'Test Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdBy: 'creator-peer',
        myRole: GroupRole.admin,
        createdAt: now,
      ));

      await groupMessageRepo.saveMessage(GroupMessage(
        id: 'msg-1',
        groupId: groupId,
        senderPeerId: 'sender-1',
        senderUsername: 'Alice',
        text: 'Hello',
        timestamp: now,
        createdAt: now,
        isIncoming: true,
        status: 'delivered',
      ));

      await groupMessageRepo.saveMessage(GroupMessage(
        id: 'msg-2',
        groupId: groupId,
        senderPeerId: 'sender-2',
        senderUsername: 'Bob',
        text: 'World',
        timestamp: now,
        createdAt: now,
        isIncoming: true,
        status: 'delivered',
      ));

      await deleteGroupAndMessages(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: groupMessageRepo,
        groupId: groupId,
      );

      // Messages should be deleted
      expect(groupMessageRepo.count, 0);

      // Group should be deleted (leaveGroup removes it)
      final group = await groupRepo.getGroup(groupId);
      expect(group, isNull);

      // Bridge should have been called for group:leave
      expect(bridge.commandLog, contains('group:leave'));
    });

    test('propagates errors from message deletion', () async {
      final failingMsgRepo = _FailingGroupMessageRepository();

      expect(
        () => deleteGroupAndMessages(
          bridge: bridge,
          groupRepo: groupRepo,
          groupMessageRepo: failingMsgRepo,
          groupId: groupId,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}

class _FailingGroupMessageRepository extends InMemoryGroupMessageRepository {
  @override
  Future<int> deleteMessagesForGroup(String groupId) async {
    throw Exception('DB error');
  }
}
