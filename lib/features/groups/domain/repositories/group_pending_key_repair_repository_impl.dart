import '../models/group_pending_key_repair.dart';
import 'group_pending_key_repair_repository.dart';

class GroupPendingKeyRepairRepositoryImpl
    implements
        GroupPendingKeyRepairRepository,
        GroupPendingKeyRepairExactRepository {
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
  final Future<List<Map<String, Object?>>> Function({int limit})
  dbLoadAllPendingGroupKeyRepairs;
  final Future<List<Map<String, Object?>>> Function({
    required String groupId,
    int limit,
  })
  dbLoadPendingGroupKeyRepairsForGroup;
  final Future<void> Function(String id) dbDeleteGroupPendingKeyRepair;
  final Future<bool> Function(Map<String, Object?> expected)?
  dbDeleteGroupPendingKeyRepairIfExact;
  final Future<void> Function(
    String id, {
    required String? lastError,
    required String updatedAt,
  })
  dbRecordGroupPendingKeyRepairAttempt;
  final Future<bool> Function(
    Map<String, Object?> expected, {
    required String? lastError,
    required String updatedAt,
  })?
  dbRecordGroupPendingKeyRepairAttemptIfExact;
  final Future<void> Function(
    String id, {
    required String status,
    required String lastError,
    required String finalizedAt,
  })
  dbFinalizeGroupPendingKeyRepair;
  final Future<bool> Function(
    Map<String, Object?> expected, {
    required String status,
    required String lastError,
    required String finalizedAt,
  })?
  dbFinalizeGroupPendingKeyRepairIfExact;

  GroupPendingKeyRepairRepositoryImpl({
    required this.dbUpsertGroupPendingKeyRepair,
    required this.dbLoadGroupPendingKeyRepair,
    required this.dbLoadPendingGroupKeyRepairsForEpoch,
    required this.dbLoadAllPendingGroupKeyRepairs,
    required this.dbLoadPendingGroupKeyRepairsForGroup,
    required this.dbDeleteGroupPendingKeyRepair,
    this.dbDeleteGroupPendingKeyRepairIfExact,
    required this.dbRecordGroupPendingKeyRepairAttempt,
    this.dbRecordGroupPendingKeyRepairAttemptIfExact,
    required this.dbFinalizeGroupPendingKeyRepair,
    this.dbFinalizeGroupPendingKeyRepairIfExact,
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
  Future<List<GroupPendingKeyRepair>> getAllPendingRepairs({
    int limit = 200,
  }) async {
    final rows = await dbLoadAllPendingGroupKeyRepairs(limit: limit);
    return rows.map(GroupPendingKeyRepair.fromMap).toList();
  }

  @override
  Future<List<GroupPendingKeyRepair>> getPendingRepairsForGroup({
    required String groupId,
    int limit = 100,
  }) async {
    final rows = await dbLoadPendingGroupKeyRepairsForGroup(
      groupId: groupId,
      limit: limit,
    );
    return rows.map(GroupPendingKeyRepair.fromMap).toList();
  }

  @override
  Future<void> deleteRepair(String id) async {
    await dbDeleteGroupPendingKeyRepair(id);
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

  @override
  Future<GroupPendingKeyRepair?> recordAttemptIfExact(
    GroupPendingKeyRepair expected, {
    required String? lastError,
  }) async {
    final now = DateTime.now().toUtc();
    final exact = dbRecordGroupPendingKeyRepairAttemptIfExact;
    if (exact == null) {
      final current = await getRepair(expected.id);
      if (current == null ||
          !sameExactGroupPendingKeyRepair(current, expected)) {
        return null;
      }
      await recordAttempt(expected.id, lastError: lastError);
      return getRepair(expected.id);
    }
    final applied = await exact(
      expected.toMap(),
      lastError: lastError,
      updatedAt: now.toIso8601String(),
    );
    return applied
        ? expected.copyWith(
            attempts: expected.attempts + 1,
            lastError: lastError,
            updatedAt: now,
          )
        : null;
  }

  @override
  Future<bool> deleteRepairIfExact(GroupPendingKeyRepair expected) async {
    final exact = dbDeleteGroupPendingKeyRepairIfExact;
    if (exact != null) return exact(expected.toMap());
    final current = await getRepair(expected.id);
    if (current == null || !sameExactGroupPendingKeyRepair(current, expected)) {
      return false;
    }
    await deleteRepair(expected.id);
    return true;
  }

  @override
  Future<bool> finalizeRepairedIfExact(GroupPendingKeyRepair expected) =>
      _finalizeIfExact(
        expected,
        status: groupPendingKeyRepairStatusRepaired,
        lastError: '',
      );

  @override
  Future<bool> finalizeUndecryptableIfExact(
    GroupPendingKeyRepair expected, {
    required String lastError,
  }) => _finalizeIfExact(
    expected,
    status: groupPendingKeyRepairStatusUndecryptable,
    lastError: lastError,
  );

  Future<bool> _finalizeIfExact(
    GroupPendingKeyRepair expected, {
    required String status,
    required String lastError,
  }) async {
    final exact = dbFinalizeGroupPendingKeyRepairIfExact;
    if (exact == null) {
      final current = await getRepair(expected.id);
      if (current == null ||
          !sameExactGroupPendingKeyRepair(current, expected)) {
        return false;
      }
      if (status == groupPendingKeyRepairStatusRepaired) {
        await finalizeRepaired(expected.id);
      } else {
        await finalizeUndecryptable(expected.id, lastError: lastError);
      }
      return true;
    }
    return exact(
      expected.toMap(),
      status: status,
      lastError: lastError,
      finalizedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }
}
