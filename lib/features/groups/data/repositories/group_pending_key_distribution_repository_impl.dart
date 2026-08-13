import '../../domain/models/group_pending_key_distribution.dart';
import '../../domain/repositories/group_pending_key_distribution_repository.dart';

class GroupPendingKeyDistributionRepositoryImpl
    implements
        GroupPendingKeyDistributionRepository,
        GroupPendingKeyDistributionExactRepository {
  final Future<bool> Function(Map<String, Object?> row)
  dbUpsertGroupPendingKeyDistribution;
  final Future<void> Function(Map<String, Object?> row)
  dbReopenGroupPendingKeyDistributionForRedelivery;
  final Future<Map<String, Object?>?> Function(String id)
  dbLoadGroupPendingKeyDistribution;
  final Future<List<Map<String, Object?>>> Function({
    required String peerId,
    String? groupId,
    int limit,
  })
  dbLoadPendingGroupKeyDistributionsForPeer;
  final Future<List<Map<String, Object?>>> Function({
    required String groupId,
    int limit,
  })
  dbLoadPendingGroupKeyDistributionsForGroup;
  final Future<void> Function(
    String id, {
    required String? lastError,
    required String updatedAt,
  })
  dbRecordGroupPendingKeyDistributionAttempt;
  final Future<bool> Function(
    Map<String, Object?> expected, {
    required String? lastError,
    required String updatedAt,
  })?
  dbRecordGroupPendingKeyDistributionAttemptIfExact;
  final Future<void> Function(
    String id, {
    required String status,
    required String lastError,
    required String finalizedAt,
  })
  dbFinalizeGroupPendingKeyDistribution;
  final Future<bool> Function(
    Map<String, Object?> expected, {
    required String status,
    required String lastError,
    required String finalizedAt,
  })?
  dbFinalizeGroupPendingKeyDistributionIfExact;

  GroupPendingKeyDistributionRepositoryImpl({
    required this.dbUpsertGroupPendingKeyDistribution,
    required this.dbReopenGroupPendingKeyDistributionForRedelivery,
    required this.dbLoadGroupPendingKeyDistribution,
    required this.dbLoadPendingGroupKeyDistributionsForPeer,
    required this.dbLoadPendingGroupKeyDistributionsForGroup,
    required this.dbRecordGroupPendingKeyDistributionAttempt,
    this.dbRecordGroupPendingKeyDistributionAttemptIfExact,
    required this.dbFinalizeGroupPendingKeyDistribution,
    this.dbFinalizeGroupPendingKeyDistributionIfExact,
  });

  @override
  Future<GroupPendingKeyDistributionUpsertResult> enqueue(
    GroupPendingKeyDistribution distribution,
  ) async {
    final created = await dbUpsertGroupPendingKeyDistribution(
      distribution.toMap(),
    );
    final loaded = await getDistribution(distribution.id);
    return GroupPendingKeyDistributionUpsertResult(
      distribution: loaded ?? distribution,
      created: created,
    );
  }

  @override
  Future<void> reopenForRedelivery(GroupPendingKeyDistribution distribution) =>
      dbReopenGroupPendingKeyDistributionForRedelivery(distribution.toMap());

  @override
  Future<GroupPendingKeyDistribution?> getDistribution(String id) async {
    final row = await dbLoadGroupPendingKeyDistribution(id);
    return row == null ? null : GroupPendingKeyDistribution.fromMap(row);
  }

  @override
  Future<List<GroupPendingKeyDistribution>> getPendingForPeer({
    required String peerId,
    String? groupId,
    int limit = 50,
  }) async {
    final rows = await dbLoadPendingGroupKeyDistributionsForPeer(
      peerId: peerId,
      groupId: groupId,
      limit: limit,
    );
    return rows.map(GroupPendingKeyDistribution.fromMap).toList();
  }

  @override
  Future<List<GroupPendingKeyDistribution>> getPendingForGroup({
    required String groupId,
    int limit = 50,
  }) async {
    final rows = await dbLoadPendingGroupKeyDistributionsForGroup(
      groupId: groupId,
      limit: limit,
    );
    return rows.map(GroupPendingKeyDistribution.fromMap).toList();
  }

  @override
  Future<void> recordAttempt(String id, {required String? lastError}) async {
    await dbRecordGroupPendingKeyDistributionAttempt(
      id,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> finalizeDistributed(String id) async {
    await dbFinalizeGroupPendingKeyDistribution(
      id,
      status: groupPendingKeyDistributionStatusDistributed,
      lastError: '',
      finalizedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> finalizeUnreachable(
    String id, {
    required String lastError,
  }) async {
    await dbFinalizeGroupPendingKeyDistribution(
      id,
      status: groupPendingKeyDistributionStatusUnreachable,
      lastError: lastError,
      finalizedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<GroupPendingKeyDistribution?> recordAttemptIfExact(
    GroupPendingKeyDistribution expected, {
    required String? lastError,
  }) async {
    final now = DateTime.now().toUtc();
    final exact = dbRecordGroupPendingKeyDistributionAttemptIfExact;
    if (exact == null) {
      final current = await getDistribution(expected.id);
      if (current == null ||
          !sameExactGroupPendingKeyDistribution(current, expected)) {
        return null;
      }
      await recordAttempt(expected.id, lastError: lastError);
      return getDistribution(expected.id);
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
  Future<bool> finalizeDistributedIfExact(
    GroupPendingKeyDistribution expected,
  ) => _finalizeIfExact(
    expected,
    status: groupPendingKeyDistributionStatusDistributed,
    lastError: '',
  );

  @override
  Future<bool> finalizeUnreachableIfExact(
    GroupPendingKeyDistribution expected, {
    required String lastError,
  }) => _finalizeIfExact(
    expected,
    status: groupPendingKeyDistributionStatusUnreachable,
    lastError: lastError,
  );

  Future<bool> _finalizeIfExact(
    GroupPendingKeyDistribution expected, {
    required String status,
    required String lastError,
  }) async {
    final exact = dbFinalizeGroupPendingKeyDistributionIfExact;
    if (exact == null) {
      final current = await getDistribution(expected.id);
      if (current == null ||
          !sameExactGroupPendingKeyDistribution(current, expected)) {
        return false;
      }
      if (status == groupPendingKeyDistributionStatusDistributed) {
        await finalizeDistributed(expected.id);
      } else {
        await finalizeUnreachable(expected.id, lastError: lastError);
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
