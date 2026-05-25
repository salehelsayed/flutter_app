import '../models/group_history_gap_repair.dart';

class GroupHistoryGapRepairUpsertResult {
  final GroupHistoryGapRepair repair;
  final bool created;

  const GroupHistoryGapRepairUpsertResult({
    required this.repair,
    required this.created,
  });
}

abstract class GroupHistoryGapRepairRepository {
  Future<GroupHistoryGapRepairUpsertResult> upsertDetected(
    GroupHistoryGapRepair repair,
  );

  Future<GroupHistoryGapRepair?> getRepair({
    required String groupId,
    required String gapId,
  });

  Future<GroupHistoryGapRepair?> getLatestRepairForGroup(String groupId);

  Future<List<GroupHistoryGapRepair>> getVisibleRepairsForGroup(
    String groupId, {
    int limit = 20,
  });

  Future<void> markRepairing({required String groupId, required String gapId});

  Future<void> recordAttempt({
    required String groupId,
    required String gapId,
    required String sourcePeerId,
    required String? lastError,
  });

  Future<void> markRepaired({
    required String groupId,
    required String gapId,
    required List<String> repairedMessageIds,
  });

  Future<void> markFailed({
    required String groupId,
    required String gapId,
    required String reason,
  });
}
