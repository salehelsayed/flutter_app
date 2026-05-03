import '../models/group_history_gap_repair.dart';
import 'group_history_gap_repair_repository.dart';

class GroupHistoryGapRepairRepositoryImpl
    implements GroupHistoryGapRepairRepository {
  final Future<bool> Function(Map<String, Object?> row)
  dbUpsertGroupHistoryGapRepair;
  final Future<void> Function(Map<String, Object?> row)
  dbSaveGroupHistoryGapRepair;
  final Future<Map<String, Object?>?> Function({
    required String groupId,
    required String gapId,
  })
  dbLoadGroupHistoryGapRepair;
  final Future<Map<String, Object?>?> Function({required String groupId})
  dbLoadLatestGroupHistoryGapRepair;
  final Future<List<Map<String, Object?>>> Function({
    required String groupId,
    int limit,
  })
  dbLoadVisibleGroupHistoryGapRepairs;

  GroupHistoryGapRepairRepositoryImpl({
    required this.dbUpsertGroupHistoryGapRepair,
    required this.dbSaveGroupHistoryGapRepair,
    required this.dbLoadGroupHistoryGapRepair,
    required this.dbLoadLatestGroupHistoryGapRepair,
    required this.dbLoadVisibleGroupHistoryGapRepairs,
  });

  @override
  Future<GroupHistoryGapRepairUpsertResult> upsertDetected(
    GroupHistoryGapRepair repair,
  ) async {
    final created = await dbUpsertGroupHistoryGapRepair(repair.toMap());
    final loaded = await getRepair(
      groupId: repair.groupId,
      gapId: repair.gapId,
    );
    return GroupHistoryGapRepairUpsertResult(
      repair: loaded ?? repair,
      created: created,
    );
  }

  @override
  Future<GroupHistoryGapRepair?> getRepair({
    required String groupId,
    required String gapId,
  }) async {
    final row = await dbLoadGroupHistoryGapRepair(
      groupId: groupId,
      gapId: gapId,
    );
    return row == null ? null : GroupHistoryGapRepair.fromMap(row);
  }

  @override
  Future<GroupHistoryGapRepair?> getLatestRepairForGroup(String groupId) async {
    final row = await dbLoadLatestGroupHistoryGapRepair(groupId: groupId);
    return row == null ? null : GroupHistoryGapRepair.fromMap(row);
  }

  @override
  Future<List<GroupHistoryGapRepair>> getVisibleRepairsForGroup(
    String groupId, {
    int limit = 20,
  }) async {
    final rows = await dbLoadVisibleGroupHistoryGapRepairs(
      groupId: groupId,
      limit: limit,
    );
    return rows.map(GroupHistoryGapRepair.fromMap).toList(growable: false);
  }

  @override
  Future<void> markRepairing({
    required String groupId,
    required String gapId,
  }) async {
    await _mutate(
      groupId: groupId,
      gapId: gapId,
      update: (repair, now) {
        if (repair.isTerminal) return repair;
        return repair.copyWith(
          status: groupHistoryGapRepairStatusRepairing,
          updatedAt: now,
          failureReason: null,
        );
      },
    );
  }

  @override
  Future<void> recordAttempt({
    required String groupId,
    required String gapId,
    required String sourcePeerId,
    required String? lastError,
  }) async {
    await _mutate(
      groupId: groupId,
      gapId: gapId,
      update: (repair, now) {
        if (repair.isTerminal) return repair;
        final attempts = <String>{
          ...repair.attemptedSourcePeerIds,
          sourcePeerId,
        }.toList(growable: false);
        return repair.copyWith(
          status: groupHistoryGapRepairStatusRepairing,
          attemptedSourcePeerIds: attempts,
          failureReason: lastError,
          updatedAt: now,
        );
      },
    );
  }

  @override
  Future<void> markRepaired({
    required String groupId,
    required String gapId,
    required List<String> repairedMessageIds,
  }) async {
    await _mutate(
      groupId: groupId,
      gapId: gapId,
      update: (repair, now) {
        if (repair.status == groupHistoryGapRepairStatusRepaired) {
          return repair;
        }
        return repair.copyWith(
          status: groupHistoryGapRepairStatusRepaired,
          repairedMessageIds: repairedMessageIds,
          failureReason: null,
          updatedAt: now,
          repairedAt: now,
        );
      },
    );
  }

  @override
  Future<void> markFailed({
    required String groupId,
    required String gapId,
    required String reason,
  }) async {
    await _mutate(
      groupId: groupId,
      gapId: gapId,
      update: (repair, now) {
        if (repair.status == groupHistoryGapRepairStatusRepaired) {
          return repair;
        }
        return repair.copyWith(
          status: groupHistoryGapRepairStatusFailed,
          failureReason: reason,
          updatedAt: now,
          failedAt: now,
        );
      },
    );
  }

  Future<void> _mutate({
    required String groupId,
    required String gapId,
    required GroupHistoryGapRepair Function(
      GroupHistoryGapRepair repair,
      DateTime now,
    )
    update,
  }) async {
    final existing = await getRepair(groupId: groupId, gapId: gapId);
    if (existing == null) return;
    final next = update(existing, DateTime.now().toUtc());
    await dbSaveGroupHistoryGapRepair(next.toMap());
  }
}
