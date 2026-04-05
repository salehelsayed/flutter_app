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
      String? avatarBlobId = 'blob-1',
      String? avatarMime = 'image/jpeg',
      String? avatarPath = 'media/group_avatars/group-1.jpg',
      String createdAt = '2026-01-15T12:00:00.000Z',
      String createdBy = 'peer-creator',
      String myRole = 'admin',
      int isMuted = 1,
      int isDissolved = 1,
      String? dissolvedAt = '2026-01-15T14:00:00.000Z',
      String? dissolvedBy = 'peer-admin',
      int isArchived = 0,
      String? archivedAt,
      String? lastMetadataEventAt = '2026-01-15T13:00:00.000Z',
      String? lastBacklogExpiredAt = '2026-01-11T12:00:00.000Z',
      String? lastBacklogRetainedAt = '2026-01-14T18:30:00.000Z',
    }) {
      return {
        'id': id,
        'name': name,
        'type': type,
        'topic_name': topicName,
        'description': description,
        'avatar_blob_id': avatarBlobId,
        'avatar_mime': avatarMime,
        'avatar_path': avatarPath,
        'created_at': createdAt,
        'created_by': createdBy,
        'my_role': myRole,
        'is_muted': isMuted,
        'is_dissolved': isDissolved,
        'dissolved_at': dissolvedAt,
        'dissolved_by': dissolvedBy,
        'is_archived': isArchived,
        'archived_at': archivedAt,
        'last_metadata_event_at': lastMetadataEventAt,
        'last_backlog_expired_at': lastBacklogExpiredAt,
        'last_backlog_retained_at': lastBacklogRetainedAt,
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
      expect(result['avatar_blob_id'], 'blob-1');
      expect(result['avatar_mime'], 'image/jpeg');
      expect(result['avatar_path'], 'media/group_avatars/group-1.jpg');
      expect(result['created_at'], '2026-01-15T12:00:00.000Z');
      expect(result['created_by'], 'peer-creator');
      expect(result['my_role'], 'admin');
      expect(result['is_muted'], 1);
      expect(result['is_dissolved'], 1);
      expect(result['dissolved_at'], '2026-01-15T14:00:00.000Z');
      expect(result['dissolved_by'], 'peer-admin');
      expect(result['is_archived'], 0);
      expect(result['archived_at'], isNull);
      expect(result['last_metadata_event_at'], '2026-01-15T13:00:00.000Z');
      expect(result['last_backlog_expired_at'], '2026-01-11T12:00:00.000Z');
      expect(result['last_backlog_retained_at'], '2026-01-14T18:30:00.000Z');
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
        avatarBlobId: 'blob-1',
        avatarMime: 'image/jpeg',
        avatarPath: 'media/group_avatars/group-1.jpg',
        createdAt: now,
        createdBy: 'peer-1',
        myRole: GroupRole.admin,
        isMuted: false,
        isDissolved: false,
        lastBacklogExpiredAt: DateTime.utc(2026, 1, 10, 9),
      );

      final updated = model.copyWith(
        name: 'Updated',
        myRole: GroupRole.member,
        isMuted: true,
        isDissolved: true,
        dissolvedAt: now,
        dissolvedBy: 'peer-admin',
        description: null,
        avatarBlobId: null,
        avatarMime: null,
        avatarPath: null,
        lastBacklogExpiredAt: DateTime.utc(2026, 1, 11, 15),
        lastBacklogRetainedAt: DateTime.utc(2026, 1, 14, 18, 30),
      );

      expect(updated.name, 'Updated');
      expect(updated.myRole, GroupRole.member);
      expect(updated.isMuted, isTrue);
      expect(updated.isDissolved, isTrue);
      expect(updated.dissolvedAt, now);
      expect(updated.dissolvedBy, 'peer-admin');
      expect(updated.description, isNull);
      expect(updated.avatarBlobId, isNull);
      expect(updated.avatarMime, isNull);
      expect(updated.avatarPath, isNull);
      expect(updated.lastBacklogExpiredAt, DateTime.utc(2026, 1, 11, 15));
      expect(updated.lastBacklogRetainedAt, DateTime.utc(2026, 1, 14, 18, 30));
      // Unchanged fields
      expect(updated.id, 'group-1');
      expect(updated.type, GroupType.chat);
      expect(updated.topicName, '/topic/1');
    });
  });
}
