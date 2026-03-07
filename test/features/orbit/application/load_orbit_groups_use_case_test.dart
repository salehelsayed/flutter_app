import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/orbit/application/load_orbit_groups_use_case.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';

GroupModel _makeGroup({
  required String id,
  required String name,
  GroupType type = GroupType.chat,
  DateTime? createdAt,
  bool isArchived = false,
}) {
  return GroupModel(
    id: id,
    name: name,
    type: type,
    topicName: 'topic-$id',
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
    isArchived: isArchived,
    archivedAt: isArchived ? DateTime.utc(2026, 2, 1) : null,
  );
}

GroupMessage _makeMessage({
  required String id,
  required String groupId,
  required String text,
  required DateTime timestamp,
  String senderUsername = 'Alice',
  bool isIncoming = true,
}) {
  return GroupMessage(
    id: id,
    groupId: groupId,
    senderPeerId: 'peer-alice',
    senderUsername: senderUsername,
    text: text,
    timestamp: timestamp,
    isIncoming: isIncoming,
    createdAt: timestamp,
  );
}

void main() {
  group('loadOrbitGroups', () {
    late InMemoryGroupRepository groupRepo;
    late InMemoryGroupMessageRepository msgRepo;

    setUp(() {
      groupRepo = InMemoryGroupRepository();
      msgRepo = InMemoryGroupMessageRepository();
    });

    test('returns empty list when no groups', () async {
      final result = await loadOrbitGroups(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      expect(result, isEmpty);
    });

    test('loads active groups only (excludes archived)', () async {
      await groupRepo.saveGroup(_makeGroup(id: 'g-1', name: 'Active Group'));
      await groupRepo.saveGroup(
        _makeGroup(id: 'g-2', name: 'Archived Group', isArchived: true),
      );

      final result = await loadOrbitGroups(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      expect(result.length, 1);
      expect(result[0].groupId, 'g-1');
      expect(result[0].name, 'Active Group');
    });

    test('includes latest message preview', () async {
      await groupRepo.saveGroup(_makeGroup(id: 'g-1', name: 'Alpha'));
      await msgRepo.saveMessage(
        _makeMessage(
          id: 'msg-1',
          groupId: 'g-1',
          text: 'Hello group',
          timestamp: DateTime.utc(2026, 3, 1),
          senderUsername: 'Bob',
        ),
      );

      final result = await loadOrbitGroups(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      expect(result.length, 1);
      expect(result[0].latestMessage, 'Bob: Hello group');
    });

    test('includes unread count', () async {
      await groupRepo.saveGroup(_makeGroup(id: 'g-1', name: 'Alpha'));
      await msgRepo.saveMessage(
        _makeMessage(
          id: 'msg-1',
          groupId: 'g-1',
          text: 'Hello 1',
          timestamp: DateTime.utc(2026, 3, 1),
        ),
      );
      await msgRepo.saveMessage(
        _makeMessage(
          id: 'msg-2',
          groupId: 'g-1',
          text: 'Hello 2',
          timestamp: DateTime.utc(2026, 3, 1, 0, 1),
        ),
      );

      final result = await loadOrbitGroups(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      expect(result[0].unreadCount, 2);
    });

    test('sorts by most recent activity first', () async {
      await groupRepo.saveGroup(
        _makeGroup(
          id: 'g-old',
          name: 'Old Group',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await groupRepo.saveGroup(
        _makeGroup(
          id: 'g-new',
          name: 'New Group',
          createdAt: DateTime.utc(2026, 1, 2),
        ),
      );

      await msgRepo.saveMessage(
        _makeMessage(
          id: 'msg-old',
          groupId: 'g-old',
          text: 'Old message',
          timestamp: DateTime.utc(2026, 2, 1),
        ),
      );
      await msgRepo.saveMessage(
        _makeMessage(
          id: 'msg-new',
          groupId: 'g-new',
          text: 'New message',
          timestamp: DateTime.utc(2026, 3, 1),
        ),
      );

      final result = await loadOrbitGroups(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      expect(result[0].groupId, 'g-new');
      expect(result[1].groupId, 'g-old');
    });

    test('uses createdAt as fallback when no messages', () async {
      await groupRepo.saveGroup(
        _makeGroup(
          id: 'g-newer',
          name: 'Newer Group',
          createdAt: DateTime.utc(2026, 2, 1),
        ),
      );
      await groupRepo.saveGroup(
        _makeGroup(
          id: 'g-older',
          name: 'Older Group',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final result = await loadOrbitGroups(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      expect(result[0].groupId, 'g-newer');
      expect(result[1].groupId, 'g-older');
    });

    test('returns null latestMessage when group has no messages', () async {
      await groupRepo.saveGroup(_makeGroup(id: 'g-1', name: 'Empty Group'));

      final result = await loadOrbitGroups(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
      );

      expect(result[0].latestMessage, isNull);
      expect(result[0].unreadCount, 0);
    });

    test('loads a single group snapshot by group id', () async {
      await groupRepo.saveGroup(_makeGroup(id: 'g-1', name: 'Alpha'));
      await msgRepo.saveMessage(
        _makeMessage(
          id: 'msg-1',
          groupId: 'g-1',
          text: 'Hello group',
          timestamp: DateTime.utc(2026, 3, 1),
          senderUsername: 'Bob',
        ),
      );

      final result = await loadOrbitGroupSnapshot(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'g-1',
      );

      expect(result, isNotNull);
      expect(result!.groupId, 'g-1');
      expect(result.latestMessage, 'Bob: Hello group');
      expect(result.unreadCount, 1);
    });

    test('returns null when a group snapshot no longer exists', () async {
      final result = await loadOrbitGroupSnapshot(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'missing-group',
      );

      expect(result, isNull);
    });
  });
}
