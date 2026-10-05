import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/utils/group_key_rotation_leader.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 5, 12);
  final group = GroupModel(
    id: 'g',
    name: 'Leader',
    type: GroupType.chat,
    topicName: 'topic',
    createdAt: t0,
    createdBy: 'peer-alice',
    myRole: GroupRole.admin,
  );

  GroupMember member(String peerId, MemberRole role, {int joinedMinute = 0}) {
    return GroupMember(
      groupId: 'g',
      peerId: peerId,
      username: peerId,
      role: role,
      publicKey: 'pk-$peerId',
      joinedAt: t0.add(Duration(minutes: joinedMinute)),
    );
  }

  String? leader(List<GroupMember> members) =>
      groupKeyRotationLeaderPeerId(group: group, members: members);

  test('the creator leads while it may rotate', () {
    expect(
      leader([
        member('peer-bob', MemberRole.admin),
        member('peer-alice', MemberRole.admin, joinedMinute: 5),
      ]),
      'peer-alice',
    );
  });

  test('a demoted creator hands the lead to the earliest admin', () {
    expect(
      leader([
        member('peer-alice', MemberRole.writer),
        member('peer-carol', MemberRole.admin, joinedMinute: 3),
        member('peer-bob', MemberRole.admin, joinedMinute: 1),
      ]),
      'peer-bob',
    );
  });

  test('a departed creator hands the lead to the earliest admin', () {
    expect(
      leader([
        member('peer-carol', MemberRole.admin, joinedMinute: 3),
        member('peer-bob', MemberRole.admin, joinedMinute: 1),
      ]),
      'peer-bob',
    );
  });

  test('equal join times fall back to the lowest peer ID', () {
    expect(
      leader([
        member('peer-dave', MemberRole.admin, joinedMinute: 2),
        member('peer-carol', MemberRole.admin, joinedMinute: 2),
      ]),
      'peer-carol',
    );
  });

  test('nobody leads when no member may rotate', () {
    expect(
      leader([
        member('peer-alice', MemberRole.writer),
        member('peer-bob', MemberRole.writer),
      ]),
      isNull,
    );
  });

  test('every device reaches the same leader whatever the list order', () {
    final members = [
      member('peer-alice', MemberRole.writer),
      member('peer-carol', MemberRole.admin, joinedMinute: 1),
      member('peer-bob', MemberRole.admin, joinedMinute: 1),
    ];
    expect(leader(members), 'peer-bob');
    expect(leader(members.reversed.toList()), 'peer-bob');
  });
}
