import '../models/group_exit_intent.dart';
import '../models/group_message.dart';
import '../models/group_pending_broadcast.dart';

enum GroupExitIntentMutationDisposition {
  committed,
  alreadyCurrent,
  absent,
  refusedConflict,
  refusedInvalidTransition,
  refusedIdentityChanged,
  refusedParentAbsent,
  refusedDissolved,
  refusedSelfRemoved,
  refusedSelfMissing,
  refusedMembershipChanged,
  refusedLastAdmin,
  refusedRoleBroadcastPresent,
  refusedNoticeMissing,
  refusedTimelineConflict,
  retiredStaleMembership,
  cleanupAlreadyComplete,
}

class GroupExitIntentMutationResult {
  const GroupExitIntentMutationResult({
    required this.disposition,
    this.current,
  });

  final GroupExitIntentMutationDisposition disposition;
  final GroupExitIntent? current;

  bool get committed =>
      disposition == GroupExitIntentMutationDisposition.committed;
}

abstract interface class GroupExitIntentRepository {
  Future<GroupExitIntent?> forGroup(String groupId);

  Future<List<GroupExitIntent>> all();

  Future<GroupExitIntentMutationResult> enqueue(GroupExitIntent intent);

  Future<GroupExitIntentMutationResult> cancelQueued(
    GroupExitIntent expected, {
    required DateTime updatedAt,
  });

  /// Atomically rechecks exact membership, last-admin authority, and role-row
  /// absence, then persists the deterministic timeline row, exact leave-notice
  /// outbox row, and the `queued -> leave_notice_pending` intent transition.
  Future<GroupExitIntentMutationResult> prepareLeaveNotice({
    required GroupExitIntent expected,
    required GroupMessage timelineMessage,
    required GroupPendingBroadcast pendingBroadcast,
    required DateTime updatedAt,
  });

  /// Atomically removes only this intent's exact leave-notice row and advances
  /// `leave_notice_pending -> leave_notice_attempted`.
  Future<GroupExitIntentMutationResult> completeLeaveNoticeAttempt({
    required GroupExitIntent expected,
    required GroupPendingBroadcast pendingBroadcast,
    required String completionCode,
    required DateTime updatedAt,
  });

  /// Advances one legal post-notice phase with state + revision CAS. Passing
  /// the current state records a bounded diagnostic without changing phase.
  Future<GroupExitIntentMutationResult> advance({
    required GroupExitIntent expected,
    required GroupExitIntentState nextState,
    required DateTime updatedAt,
    String? lastErrorCode,
  });

  /// Performs exact-membership local SQL cleanup in one transaction, deletes
  /// the intent last, and retires only stale intent/notice work on re-entry.
  Future<GroupExitIntentMutationResult> cleanupOrRetire(
    GroupExitIntent expected, {
    required DateTime updatedAt,
  });

  /// CAS-deletes only the exact intent and its exact leave-notice row.
  Future<GroupExitIntentMutationResult> retireExact(GroupExitIntent expected);

  /// Terminal lifecycle path for self-removal, self-ban, or dissolution.
  Future<int> terminalizeForGroup(String groupId);
}
