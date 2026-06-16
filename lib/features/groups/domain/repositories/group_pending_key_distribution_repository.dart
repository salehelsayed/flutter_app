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
