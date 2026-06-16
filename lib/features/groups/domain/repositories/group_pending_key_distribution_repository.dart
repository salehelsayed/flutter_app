import '../models/group_pending_key_distribution.dart';

class GroupPendingKeyDistributionUpsertResult {
  final GroupPendingKeyDistribution distribution;
  final bool created;

  const GroupPendingKeyDistributionUpsertResult({
    required this.distribution,
    required this.created,
  });
}

abstract class GroupPendingKeyDistributionRepository {
  /// Records (or merges, via `UNIQUE(group_id, peer_id)`) a deferred
  /// distribution. `created` is true only on a fresh insert.
  Future<GroupPendingKeyDistributionUpsertResult> enqueue(
    GroupPendingKeyDistribution distribution,
  );

  /// (Re)opens a row to PENDING for re-delivery, OVERRIDING a terminal
  /// (distributed / unreachable) status (resets attempts/last_error/
  /// finalized_at). For when the member's device set changed (a sibling device
  /// was admitted) so the current key must be re-distributed to the now-larger
  /// device set — unlike [enqueue], it deliberately re-arms an exhausted row.
  Future<void> reopenForRedelivery(GroupPendingKeyDistribution distribution);

  Future<GroupPendingKeyDistribution?> getDistribution(String id);

  Future<List<GroupPendingKeyDistribution>> getPendingForPeer({
    required String peerId,
    String? groupId,
    int limit = 50,
  });

  Future<List<GroupPendingKeyDistribution>> getPendingForGroup({
    required String groupId,
    int limit = 50,
  });

  Future<void> recordAttempt(String id, {required String? lastError});

  Future<void> finalizeDistributed(String id);

  Future<void> finalizeUnreachable(String id, {required String lastError});
}
