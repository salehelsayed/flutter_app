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

  Future<void> recordAttempt(String id, {required String? lastError});

  Future<void> finalizeRepaired(String id);

  Future<void> finalizeUndecryptable(String id, {required String lastError});
}
