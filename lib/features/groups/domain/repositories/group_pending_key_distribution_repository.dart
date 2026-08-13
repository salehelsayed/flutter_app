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
  /// finalized_at) and atomically advancing its durable operation generation.
  ///
  /// This is used both when the member's device set changed (a sibling device
  /// was admitted) and when an existing device re-announces to deliberately
  /// re-arm delivery. Unlike [enqueue], every call creates a distinct operation
  /// even if the row was already pending or the requested clock did not move.
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

abstract interface class GroupPendingKeyDistributionExactRepository {
  Future<GroupPendingKeyDistribution?> recordAttemptIfExact(
    GroupPendingKeyDistribution expected, {
    required String? lastError,
  });

  Future<bool> finalizeDistributedIfExact(GroupPendingKeyDistribution expected);

  Future<bool> finalizeUnreachableIfExact(
    GroupPendingKeyDistribution expected, {
    required String lastError,
  });
}

Future<GroupPendingKeyDistribution?>
recordGroupPendingKeyDistributionAttemptIfExact(
  GroupPendingKeyDistributionRepository repository,
  GroupPendingKeyDistribution expected, {
  required String? lastError,
}) async {
  if (repository case final GroupPendingKeyDistributionExactRepository exact) {
    return exact.recordAttemptIfExact(expected, lastError: lastError);
  }
  final current = await repository.getDistribution(expected.id);
  if (current == null ||
      !sameExactGroupPendingKeyDistribution(current, expected)) {
    return null;
  }
  await repository.recordAttempt(expected.id, lastError: lastError);
  return repository.getDistribution(expected.id);
}

Future<bool> finalizeGroupPendingKeyDistributionIfExact(
  GroupPendingKeyDistributionRepository repository,
  GroupPendingKeyDistribution expected,
) async {
  if (repository case final GroupPendingKeyDistributionExactRepository exact) {
    return exact.finalizeDistributedIfExact(expected);
  }
  final current = await repository.getDistribution(expected.id);
  if (current == null ||
      !sameExactGroupPendingKeyDistribution(current, expected)) {
    return false;
  }
  await repository.finalizeDistributed(expected.id);
  return true;
}

Future<bool> finalizeGroupPendingKeyDistributionUnreachableIfExact(
  GroupPendingKeyDistributionRepository repository,
  GroupPendingKeyDistribution expected, {
  required String lastError,
}) async {
  if (repository case final GroupPendingKeyDistributionExactRepository exact) {
    return exact.finalizeUnreachableIfExact(expected, lastError: lastError);
  }
  final current = await repository.getDistribution(expected.id);
  if (current == null ||
      !sameExactGroupPendingKeyDistribution(current, expected)) {
    return false;
  }
  await repository.finalizeUnreachable(expected.id, lastError: lastError);
  return true;
}
