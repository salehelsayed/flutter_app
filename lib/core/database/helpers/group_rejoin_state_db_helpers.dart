import 'package:sqflite_sqlcipher/sqflite.dart';

/// Finding 05 Phase 3: per-group rejoin retry state helpers.
///
/// A row exists only for a group that has failed to rejoin its topic; a healthy
/// group has no row (the row is deleted on a successful rejoin).

/// Loads every group's rejoin-retry state as raw row maps
/// (`group_id`, `rejoin_attempt_count`, `next_eligible_at`).
Future<List<Map<String, Object?>>> dbLoadGroupRejoinStates(
  DatabaseExecutor db,
) {
  return db.query('group_rejoin_state');
}

/// Records a failed rejoin attempt for [groupId]: increments the attempt count
/// and schedules the next eligible time (exponential backoff computed by the
/// caller). Upserts so the first failure creates the row.
Future<void> dbRecordGroupRejoinFailure(
  DatabaseExecutor db,
  String groupId, {
  required int nextEligibleAtMs,
}) async {
  await db.rawInsert(
    'INSERT INTO group_rejoin_state '
    '(group_id, rejoin_attempt_count, next_eligible_at) VALUES (?, 1, ?) '
    'ON CONFLICT(group_id) DO UPDATE SET '
    'rejoin_attempt_count = rejoin_attempt_count + 1, next_eligible_at = ?',
    [groupId, nextEligibleAtMs, nextEligibleAtMs],
  );
}

/// Clears the rejoin-retry state for [groupId] after a successful rejoin.
Future<void> dbClearGroupRejoinState(
  DatabaseExecutor db,
  String groupId,
) async {
  await db.delete(
    'group_rejoin_state',
    where: 'group_id = ?',
    whereArgs: [groupId],
  );
}

/// Forces [groupId]'s rejoin row immediately eligible by collapsing its backoff
/// window (`next_eligible_at = 0`, i.e. the epoch — always in the past) so the
/// next rejoin pass attempts it right away. Used by the stuck-rejoin "Retry now"
/// affordance (G2). Preserves the attempt count and the row itself (no
/// auto-delete — the row clears only on a successful rejoin); a no-op when no
/// row exists (a healthy group is never stuck).
Future<void> dbForceGroupRejoinEligible(
  DatabaseExecutor db,
  String groupId,
) async {
  await db.update(
    'group_rejoin_state',
    {'next_eligible_at': 0},
    where: 'group_id = ?',
    whereArgs: [groupId],
  );
}
