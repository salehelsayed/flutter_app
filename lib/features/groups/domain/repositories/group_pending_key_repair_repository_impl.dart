import '../models/group_pending_key_repair.dart';
import 'group_pending_key_repair_repository.dart';

class GroupPendingKeyRepairRepositoryImpl
    implements GroupPendingKeyRepairRepository {
  final Future<bool> Function(Map<String, Object?> row)
  dbUpsertGroupPendingKeyRepair;
  final Future<Map<String, Object?>?> Function(String id)
  dbLoadGroupPendingKeyRepair;
  final Future<List<Map<String, Object?>>> Function({
    required String groupId,
    required int keyEpoch,
    int limit,
  })
  dbLoadPendingGroupKeyRepairsForEpoch;
  final Future<void> Function(
    String id, {
    required String? lastError,
    required String updatedAt,
  })
  dbRecordGroupPendingKeyRepairAttempt;
  final Future<void> Function(
    String id, {
    required String status,
    required String lastError,
    required String finalizedAt,
  })
  dbFinalizeGroupPendingKeyRepair;

  GroupPendingKeyRepairRepositoryImpl({
    required this.dbUpsertGroupPendingKeyRepair,
    required this.dbLoadGroupPendingKeyRepair,
    required this.dbLoadPendingGroupKeyRepairsForEpoch,
    required this.dbRecordGroupPendingKeyRepairAttempt,
    required this.dbFinalizeGroupPendingKeyRepair,
  });

  @override
  Future<GroupPendingKeyRepairUpsertResult> upsertPendingRepair(
    GroupPendingKeyRepair repair,
  ) async {
    final created = await dbUpsertGroupPendingKeyRepair(repair.toMap());
    final loaded = await getRepair(repair.id);
    return GroupPendingKeyRepairUpsertResult(
      repair: loaded ?? repair,
      created: created,
    );
  }

  @override
  Future<GroupPendingKeyRepair?> getRepair(String id) async {
    final row = await dbLoadGroupPendingKeyRepair(id);
    return row == null ? null : GroupPendingKeyRepair.fromMap(row);
  }

  @override
  Future<List<GroupPendingKeyRepair>> getPendingRepairsForGroupEpoch({
    required String groupId,
    required int keyEpoch,
    int limit = 50,
  }) async {
    final rows = await dbLoadPendingGroupKeyRepairsForEpoch(
      groupId: groupId,
      keyEpoch: keyEpoch,
      limit: limit,
    );
    return rows.map(GroupPendingKeyRepair.fromMap).toList();
  }

  @override
  Future<void> recordAttempt(String id, {required String? lastError}) async {
    await dbRecordGroupPendingKeyRepairAttempt(
      id,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> finalizeRepaired(String id) async {
    await dbFinalizeGroupPendingKeyRepair(
      id,
      status: groupPendingKeyRepairStatusRepaired,
      lastError: '',
      finalizedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> finalizeUndecryptable(
    String id, {
    required String lastError,
  }) async {
    await dbFinalizeGroupPendingKeyRepair(
      id,
      status: groupPendingKeyRepairStatusUndecryptable,
      lastError: lastError,
      finalizedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }
}
