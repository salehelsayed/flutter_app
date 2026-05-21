import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/set_group_muted_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late InMemoryGroupRepository groupRepo;

  GroupModel makeGroup({bool isMuted = false}) => GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'topic-1',
    createdAt: DateTime.utc(2026, 4, 5, 12),
    createdBy: 'peer-admin',
    myRole: GroupRole.member,
    isMuted: isMuted,
  );

  setUp(() async {
    groupRepo = InMemoryGroupRepository();
  });

  group('setGroupMuted', () {
    test('updates mute state for an existing group', () async {
      await groupRepo.saveGroup(makeGroup());

      final muted = await setGroupMuted(
        groupRepo: groupRepo,
        groupId: 'group-1',
        isMuted: true,
      );
      expect(muted.isMuted, isTrue);

      final persistedMuted = await groupRepo.getGroup('group-1');
      expect(persistedMuted, isNotNull);
      expect(persistedMuted!.isMuted, isTrue);

      final unmuted = await setGroupMuted(
        groupRepo: groupRepo,
        groupId: 'group-1',
        isMuted: false,
      );
      expect(unmuted.isMuted, isFalse);

      final persistedUnmuted = await groupRepo.getGroup('group-1');
      expect(persistedUnmuted, isNotNull);
      expect(persistedUnmuted!.isMuted, isFalse);
    });

    test(
      'UP-011 persists local mute without changing group membership',
      () async {
        await groupRepo.saveGroup(makeGroup());
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            joinedAt: DateTime.utc(2026, 4, 5, 12),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 4, 5, 12, 1),
          ),
        );

        final muted = await setGroupMuted(
          groupRepo: groupRepo,
          groupId: 'group-1',
          isMuted: true,
        );

        expect(muted.isMuted, isTrue);
        expect((await groupRepo.getGroup('group-1'))!.isMuted, isTrue);
        expect(
          (await groupRepo.getMembers(
            'group-1',
          )).map((member) => member.peerId).toSet(),
          {'peer-admin', 'peer-bob'},
        );
      },
    );

    test('throws when the group does not exist', () async {
      await expectLater(
        setGroupMuted(
          groupRepo: groupRepo,
          groupId: 'missing-group',
          isMuted: true,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Group not found: missing-group',
          ),
        ),
      );
    });
  });
}
