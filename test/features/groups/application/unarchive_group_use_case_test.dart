import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/application/unarchive_group_use_case.dart';
import '../../../../test/shared/fakes/in_memory_group_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

void main() {
  late InMemoryGroupRepository groupRepo;
  const groupId = 'test-group-id-12345';

  setUp(() {
    groupRepo = InMemoryGroupRepository();
  });

  group('unarchiveGroup', () {
    test('calls groupRepo.unarchiveGroup(groupId) successfully', () async {
      await groupRepo.saveGroup(GroupModel(
        id: groupId,
        name: 'Test Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdBy: 'creator-peer',
        myRole: GroupRole.admin,
        createdAt: DateTime.now().toUtc(),
        isArchived: true,
        archivedAt: DateTime.now().toUtc(),
      ));

      await unarchiveGroup(groupRepo: groupRepo, groupId: groupId);

      final group = await groupRepo.getGroup(groupId);
      expect(group!.isArchived, isFalse);
      expect(group.archivedAt, isNull);
    });

    test('propagates errors from repository', () async {
      final failingRepo = _FailingGroupRepository();

      expect(
        () => unarchiveGroup(groupRepo: failingRepo, groupId: groupId),
        throwsA(isA<Exception>()),
      );
    });
  });
}

class _FailingGroupRepository extends InMemoryGroupRepository {
  @override
  Future<void> unarchiveGroup(String id) async {
    throw Exception('DB error');
  }
}
