import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/update_group_metadata_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late InMemoryGroupRepository groupRepo;

  GroupModel makeAdminGroup() => GroupModel(
    id: 'group-1',
    name: 'Original Name',
    type: GroupType.chat,
    topicName: 'topic-1',
    description: 'Original description',
    createdAt: DateTime.utc(2026, 4, 5, 12),
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  GroupModel makeMemberGroup() => GroupModel(
    id: 'group-1',
    name: 'Original Name',
    type: GroupType.chat,
    topicName: 'topic-1',
    createdAt: DateTime.utc(2026, 4, 5, 12),
    createdBy: 'peer-admin',
    myRole: GroupRole.member,
  );

  setUp(() async {
    groupRepo = InMemoryGroupRepository();
  });

  group('updateGroupMetadata', () {
    test('updates name, description, avatar metadata, and watermark', () async {
      await groupRepo.saveGroup(makeAdminGroup());
      final changedAt = DateTime.utc(2026, 4, 5, 13, 15);

      final updated = await updateGroupMetadata(
        groupRepo: groupRepo,
        groupId: 'group-1',
        name: '  Fresh Name  ',
        description: '  New description  ',
        avatarBlobId: 'blob-1',
        avatarMime: 'image/jpeg',
        avatarPath: 'media/group_avatars/group-1.jpg',
        eventAt: changedAt,
      );

      expect(updated.name, 'Fresh Name');
      expect(updated.description, 'New description');
      expect(updated.avatarBlobId, 'blob-1');
      expect(updated.avatarMime, 'image/jpeg');
      expect(updated.avatarPath, 'media/group_avatars/group-1.jpg');
      expect(updated.lastMetadataEventAt, changedAt);

      final persisted = await groupRepo.getGroup('group-1');
      expect(persisted!.name, 'Fresh Name');
      expect(persisted.description, 'New description');
      expect(persisted.avatarBlobId, 'blob-1');
      expect(persisted.lastMetadataEventAt, changedAt);
    });

    test('clears blank description and avatar fields explicitly', () async {
      await groupRepo.saveGroup(
        makeAdminGroup().copyWith(
          avatarBlobId: 'blob-1',
          avatarMime: 'image/jpeg',
          avatarPath: 'media/group_avatars/group-1.jpg',
        ),
      );

      final updated = await updateGroupMetadata(
        groupRepo: groupRepo,
        groupId: 'group-1',
        name: 'Still Named',
        description: '   ',
        avatarBlobId: null,
        avatarMime: null,
        avatarPath: null,
        eventAt: DateTime.utc(2026, 4, 5, 13, 45),
      );

      expect(updated.description, isNull);
      expect(updated.avatarBlobId, isNull);
      expect(updated.avatarMime, isNull);
      expect(updated.avatarPath, isNull);
    });

    test('rejects non-admin edits', () async {
      await groupRepo.saveGroup(makeMemberGroup());

      await expectLater(
        updateGroupMetadata(
          groupRepo: groupRepo,
          groupId: 'group-1',
          name: 'Nope',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Only admins can edit group details',
          ),
        ),
      );
    });

    test('rejects empty names', () async {
      await groupRepo.saveGroup(makeAdminGroup());

      await expectLater(
        updateGroupMetadata(
          groupRepo: groupRepo,
          groupId: 'group-1',
          name: '   ',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Group name cannot be empty',
          ),
        ),
      );
    });
  });
}
