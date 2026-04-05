import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';

void main() {
  test('pins the repo-owned max group size contract at 50 members', () {
    expect(groupMembershipLimit, 50);
  });

  test('remaining slots counts total members including the creator', () {
    expect(groupMembershipRemainingSlots(currentMemberCount: 1), 49);
    expect(groupMembershipRemainingSlots(currentMemberCount: 50), 0);
    expect(groupMembershipRemainingSlots(currentMemberCount: 60), 0);
  });

  test('overflow count stays zero at the limit and grows past it', () {
    expect(
      groupMembershipOverflowCount(
        currentMemberCount: 49,
        requestedAdditionalMembers: 1,
      ),
      0,
    );
    expect(
      groupMembershipOverflowCount(
        currentMemberCount: 49,
        requestedAdditionalMembers: 2,
      ),
      1,
    );
  });

  test('ensureWithinGroupMembershipLimit throws with overflow metadata', () {
    expect(
      () => ensureWithinGroupMembershipLimit(
        currentMemberCount: 49,
        requestedAdditionalMembers: 2,
      ),
      throwsA(
        isA<GroupMembershipLimitException>()
            .having((e) => e.maxMembers, 'maxMembers', 50)
            .having((e) => e.currentMemberCount, 'currentMemberCount', 49)
            .having(
              (e) => e.requestedAdditionalMembers,
              'requestedAdditionalMembers',
              2,
            )
            .having((e) => e.remainingSlots, 'remainingSlots', 1)
            .having((e) => e.overflowCount, 'overflowCount', 1),
      ),
    );
  });
}
