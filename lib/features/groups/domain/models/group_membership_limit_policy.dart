const int groupMembershipLimit = 50;

int groupMembershipRemainingSlots({required int currentMemberCount}) {
  final remaining = groupMembershipLimit - currentMemberCount;
  return remaining > 0 ? remaining : 0;
}

int groupMembershipOverflowCount({
  required int currentMemberCount,
  required int requestedAdditionalMembers,
}) {
  final overflow =
      currentMemberCount + requestedAdditionalMembers - groupMembershipLimit;
  return overflow > 0 ? overflow : 0;
}

bool exceedsGroupMembershipLimit({
  required int currentMemberCount,
  required int requestedAdditionalMembers,
}) =>
    groupMembershipOverflowCount(
      currentMemberCount: currentMemberCount,
      requestedAdditionalMembers: requestedAdditionalMembers,
    ) >
    0;

void ensureWithinGroupMembershipLimit({
  required int currentMemberCount,
  required int requestedAdditionalMembers,
}) {
  if (!exceedsGroupMembershipLimit(
    currentMemberCount: currentMemberCount,
    requestedAdditionalMembers: requestedAdditionalMembers,
  )) {
    return;
  }

  throw GroupMembershipLimitException(
    maxMembers: groupMembershipLimit,
    currentMemberCount: currentMemberCount,
    requestedAdditionalMembers: requestedAdditionalMembers,
  );
}

class GroupMembershipLimitException implements Exception {
  final int maxMembers;
  final int currentMemberCount;
  final int requestedAdditionalMembers;

  const GroupMembershipLimitException({
    required this.maxMembers,
    required this.currentMemberCount,
    required this.requestedAdditionalMembers,
  });

  int get overflowCount =>
      groupMembershipOverflowCount(
        currentMemberCount: currentMemberCount,
        requestedAdditionalMembers: requestedAdditionalMembers,
      );

  int get remainingSlots =>
      groupMembershipRemainingSlots(currentMemberCount: currentMemberCount);

  @override
  String toString() {
    return 'GroupMembershipLimitException('
        'maxMembers: $maxMembers, '
        'currentMemberCount: $currentMemberCount, '
        'requestedAdditionalMembers: $requestedAdditionalMembers'
        ')';
  }
}
