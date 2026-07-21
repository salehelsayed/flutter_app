import '../models/group_pending_key_repair.dart';

class GroupPendingKeyRepairUpsertResult {
  final GroupPendingKeyRepair repair;
  final bool created;

  const GroupPendingKeyRepairUpsertResult({
    required this.repair,
    required this.created,
  });
}

abstract class GroupPendingKeyRepairRepository {
  Future<GroupPendingKeyRepairUpsertResult> upsertPendingRepair(
    GroupPendingKeyRepair repair,
  );

  Future<GroupPendingKeyRepair?> getRepair(String id);

  Future<List<GroupPendingKeyRepair>> getPendingRepairsForGroupEpoch({
    required String groupId,
    required int keyEpoch,
    int limit = 50,
  });

  /// All `pending_key` repairs across every group/epoch, oldest first
  /// (`created_at ASC, id ASC`). Backs the resume sweep + backoff timer.
  Future<List<GroupPendingKeyRepair>> getAllPendingRepairs({int limit = 200});

  /// `pending_key` repairs for one group, oldest first.
  Future<List<GroupPendingKeyRepair>> getPendingRepairsForGroup({
    required String groupId,
    int limit = 100,
  });

  Future<void> recordAttempt(String id, {required String? lastError});

  /// Permanently removes a repair row (used by the TTL self-clear for stale
  /// no-envelope `live:` placeholders — distinct from the `finalize*` methods,
  /// which only UPDATE status and leave the row).
  Future<void> deleteRepair(String id);

  Future<void> finalizeRepaired(String id);

  Future<void> finalizeUndecryptable(String id, {required String lastError});
}

abstract interface class GroupPendingKeyRepairExactRepository {
  Future<GroupPendingKeyRepair?> recordAttemptIfExact(
    GroupPendingKeyRepair expected, {
    required String? lastError,
  });

  Future<bool> deleteRepairIfExact(GroupPendingKeyRepair expected);

  Future<bool> finalizeRepairedIfExact(GroupPendingKeyRepair expected);

  Future<bool> finalizeUndecryptableIfExact(
    GroupPendingKeyRepair expected, {
    required String lastError,
  });
}

Future<GroupPendingKeyRepair?> recordGroupPendingKeyRepairAttemptIfExact(
  GroupPendingKeyRepairRepository repository,
  GroupPendingKeyRepair expected, {
  required String? lastError,
}) async {
  if (repository case final GroupPendingKeyRepairExactRepository exact) {
    return exact.recordAttemptIfExact(expected, lastError: lastError);
  }
  final current = await repository.getRepair(expected.id);
  if (current == null || !sameExactGroupPendingKeyRepair(current, expected)) {
    return null;
  }
  await repository.recordAttempt(expected.id, lastError: lastError);
  return repository.getRepair(expected.id);
}

Future<bool> deleteGroupPendingKeyRepairIfExact(
  GroupPendingKeyRepairRepository repository,
  GroupPendingKeyRepair expected,
) async {
  if (repository case final GroupPendingKeyRepairExactRepository exact) {
    return exact.deleteRepairIfExact(expected);
  }
  final current = await repository.getRepair(expected.id);
  if (current == null || !sameExactGroupPendingKeyRepair(current, expected)) {
    return false;
  }
  await repository.deleteRepair(expected.id);
  return true;
}

Future<bool> finalizeGroupPendingKeyRepairIfExact(
  GroupPendingKeyRepairRepository repository,
  GroupPendingKeyRepair expected,
) async {
  if (repository case final GroupPendingKeyRepairExactRepository exact) {
    return exact.finalizeRepairedIfExact(expected);
  }
  final current = await repository.getRepair(expected.id);
  if (current == null || !sameExactGroupPendingKeyRepair(current, expected)) {
    return false;
  }
  await repository.finalizeRepaired(expected.id);
  return true;
}

Future<bool> finalizeGroupPendingKeyRepairUndecryptableIfExact(
  GroupPendingKeyRepairRepository repository,
  GroupPendingKeyRepair expected, {
  required String lastError,
}) async {
  if (repository case final GroupPendingKeyRepairExactRepository exact) {
    return exact.finalizeUndecryptableIfExact(expected, lastError: lastError);
  }
  final current = await repository.getRepair(expected.id);
  if (current == null || !sameExactGroupPendingKeyRepair(current, expected)) {
    return false;
  }
  await repository.finalizeUndecryptable(expected.id, lastError: lastError);
  return true;
}
