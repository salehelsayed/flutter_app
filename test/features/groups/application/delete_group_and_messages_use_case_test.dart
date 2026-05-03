import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
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
    test('leaves group then deletes its messages', () async {
      // Save a group and some messages
      final now = DateTime.now().toUtc();
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Test Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdBy: 'creator-peer',
          myRole: GroupRole.admin,
          createdAt: now,
        ),
      );

      await groupMessageRepo.saveMessage(
        GroupMessage(
          id: 'msg-1',
          groupId: groupId,
          senderPeerId: 'sender-1',
          senderUsername: 'Alice',
          text: 'Hello',
          timestamp: now,
          createdAt: now,
          isIncoming: true,
          status: 'delivered',
        ),
      );

      await groupMessageRepo.saveMessage(
        GroupMessage(
          id: 'msg-2',
          groupId: groupId,
          senderPeerId: 'sender-2',
          senderUsername: 'Bob',
          text: 'World',
          timestamp: now,
          createdAt: now,
          isIncoming: true,
          status: 'delivered',
        ),
      );

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

    test('LP003 active delete dispatches one group leave', () async {
      final now = DateTime.now().toUtc();
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Active Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdBy: 'creator-peer',
          myRole: GroupRole.member,
          createdAt: now,
        ),
      );

      await deleteGroupAndMessages(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: groupMessageRepo,
        groupId: groupId,
      );

      expect(
        bridge.commandLog.where((command) => command == 'group:leave'),
        hasLength(1),
      );
      expect(await groupRepo.getGroup(groupId), isNull);
    });

    test('preserves messages when leave is blocked', () async {
      final now = DateTime.now().toUtc();
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Only Admin Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdBy: 'creator-peer',
          myRole: GroupRole.admin,
          createdAt: now,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'creator-peer',
          username: 'Creator',
          role: MemberRole.admin,
          joinedAt: now,
        ),
      );
      await groupMessageRepo.saveMessage(
        GroupMessage(
          id: 'msg-admin-only',
          groupId: groupId,
          senderPeerId: 'creator-peer',
          senderUsername: 'Creator',
          text: 'Do not lose this',
          timestamp: now,
          createdAt: now,
          isIncoming: true,
          status: 'delivered',
        ),
      );

      await expectLater(
        deleteGroupAndMessages(
          bridge: bridge,
          groupRepo: groupRepo,
          groupMessageRepo: groupMessageRepo,
          groupId: groupId,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await groupRepo.getGroup(groupId), isNotNull);
      expect(await groupMessageRepo.getMessage('msg-admin-only'), isNotNull);
      expect(bridge.commandLog, isNot(contains('group:leave')));
    });

    test('does not delete messages for other groups', () async {
      const otherGroupId = 'other-group-id-67890';
      final now = DateTime.now().toUtc();
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Target Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdBy: 'creator-peer',
          myRole: GroupRole.member,
          createdAt: now,
        ),
      );
      await groupRepo.saveGroup(
        GroupModel(
          id: otherGroupId,
          name: 'Other Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$otherGroupId',
          createdBy: 'creator-peer',
          myRole: GroupRole.member,
          createdAt: now,
        ),
      );
      await groupMessageRepo.saveMessage(
        GroupMessage(
          id: 'msg-target',
          groupId: groupId,
          senderPeerId: 'sender-1',
          senderUsername: 'Alice',
          text: 'Delete this',
          timestamp: now,
          createdAt: now,
          isIncoming: true,
          status: 'delivered',
        ),
      );
      await groupMessageRepo.saveMessage(
        GroupMessage(
          id: 'msg-other',
          groupId: otherGroupId,
          senderPeerId: 'sender-2',
          senderUsername: 'Bob',
          text: 'Keep this',
          timestamp: now,
          createdAt: now,
          isIncoming: true,
          status: 'delivered',
        ),
      );

      await deleteGroupAndMessages(
        bridge: bridge,
        groupRepo: groupRepo,
        groupMessageRepo: groupMessageRepo,
        groupId: groupId,
      );

      expect(await groupMessageRepo.getMessage('msg-target'), isNull);
      expect(await groupMessageRepo.getMessage('msg-other'), isNotNull);
      expect(await groupRepo.getGroup(groupId), isNull);
      expect(await groupRepo.getGroup(otherGroupId), isNotNull);
    });

    test(
      'dissolved local cleanup deletes group state without publishing group leave',
      () async {
        final now = DateTime.now().toUtc();
        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Dissolved Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdBy: 'creator-peer',
            myRole: GroupRole.member,
            createdAt: now,
            isDissolved: true,
            dissolvedAt: now,
            dissolvedBy: 'creator-peer',
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'creator-peer',
            username: 'Creator',
            role: MemberRole.admin,
            joinedAt: now,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-group-key-1',
            createdAt: now,
          ),
        );
        await groupMessageRepo.saveMessage(
          GroupMessage(
            id: 'msg-dissolved',
            groupId: groupId,
            senderPeerId: 'creator-peer',
            senderUsername: 'Creator',
            text: 'Group dissolved',
            timestamp: now,
            createdAt: now,
            isIncoming: true,
            status: 'delivered',
          ),
        );

        await deleteGroupAndMessages(
          bridge: bridge,
          groupRepo: groupRepo,
          groupMessageRepo: groupMessageRepo,
          groupId: groupId,
          deleteLocallyIfDissolved: true,
        );

        expect(groupMessageRepo.count, 0);
        expect(await groupRepo.getGroup(groupId), isNull);
        expect(await groupRepo.getMembers(groupId), isEmpty);
        expect(await groupRepo.getLatestKey(groupId), isNull);
        expect(bridge.commandLog, isNot(contains('group:leave')));
      },
    );

    test(
      'LP003 dissolved local cleanup does not publish a second group leave',
      () async {
        final now = DateTime.now().toUtc();
        bridge.commandLog.add(
          'group:leave',
        ); // Prior group_dissolved unsubscribe.
        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Dissolved Group',
            type: GroupType.chat,
            topicName: '/mknoon/group/$groupId',
            createdBy: 'creator-peer',
            myRole: GroupRole.member,
            createdAt: now,
            isDissolved: true,
            dissolvedAt: now,
            dissolvedBy: 'creator-peer',
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'creator-peer',
            username: 'Creator',
            role: MemberRole.admin,
            joinedAt: now,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-group-key-1',
            createdAt: now,
          ),
        );

        await deleteGroupAndMessages(
          bridge: bridge,
          groupRepo: groupRepo,
          groupMessageRepo: groupMessageRepo,
          groupId: groupId,
          deleteLocallyIfDissolved: true,
        );

        expect(
          bridge.commandLog.where((command) => command == 'group:leave'),
          hasLength(1),
        );
        expect(await groupRepo.getGroup(groupId), isNull);
        expect(await groupRepo.getMembers(groupId), isEmpty);
        expect(await groupRepo.getLatestKey(groupId), isNull);
      },
    );

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
