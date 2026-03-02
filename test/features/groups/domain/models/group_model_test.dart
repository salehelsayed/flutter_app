import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

void main() {
  group('GroupModel', () {
    final now = DateTime.utc(2026, 1, 15, 12, 0, 0);

    Map<String, dynamic> makeMap({
      String id = 'group-1',
      String name = 'Test Group',
      String type = 'chat',
      String topicName = '/mknoon/groups/group-1',
      String? description = 'A test group',
      String createdAt = '2026-01-15T12:00:00.000Z',
      String createdBy = 'peer-creator',
      String myRole = 'admin',
      int isArchived = 0,
      String? archivedAt,
    }) {
      return {
        'id': id,
        'name': name,
        'type': type,
        'topic_name': topicName,
        'description': description,
        'created_at': createdAt,
        'created_by': createdBy,
        'my_role': myRole,
        'is_archived': isArchived,
        'archived_at': archivedAt,
      };
    }

    test('fromMap/toMap round-trip preserves all fields', () {
      final map = makeMap();
      final model = GroupModel.fromMap(map);
      final result = model.toMap();

      expect(result['id'], 'group-1');
      expect(result['name'], 'Test Group');
      expect(result['type'], 'chat');
      expect(result['topic_name'], '/mknoon/groups/group-1');
      expect(result['description'], 'A test group');
      expect(result['created_at'], '2026-01-15T12:00:00.000Z');
      expect(result['created_by'], 'peer-creator');
      expect(result['my_role'], 'admin');
      expect(result['is_archived'], 0);
      expect(result['archived_at'], isNull);
    });

    test('GroupType enum converts correctly', () {
      expect(GroupType.fromValue('chat'), GroupType.chat);
      expect(GroupType.fromValue('announcement'), GroupType.announcement);
      expect(GroupType.fromValue('qa'), GroupType.qa);
      expect(GroupType.chat.toValue(), 'chat');
      expect(GroupType.announcement.toValue(), 'announcement');
      expect(GroupType.qa.toValue(), 'qa');
    });

    test('GroupRole enum converts correctly', () {
      expect(GroupRole.fromValue('admin'), GroupRole.admin);
      expect(GroupRole.fromValue('member'), GroupRole.member);
      expect(GroupRole.admin.toValue(), 'admin');
      expect(GroupRole.member.toValue(), 'member');
    });

    test('copyWith creates new instance with updated fields', () {
      final model = GroupModel(
        id: 'group-1',
        name: 'Original',
        type: GroupType.chat,
        topicName: '/topic/1',
        description: 'desc',
        createdAt: now,
        createdBy: 'peer-1',
        myRole: GroupRole.admin,
      );

      final updated = model.copyWith(
        name: 'Updated',
        myRole: GroupRole.member,
        description: null,
      );

      expect(updated.name, 'Updated');
      expect(updated.myRole, GroupRole.member);
      expect(updated.description, isNull);
      // Unchanged fields
      expect(updated.id, 'group-1');
      expect(updated.type, GroupType.chat);
      expect(updated.topicName, '/topic/1');
    });
  });
}
