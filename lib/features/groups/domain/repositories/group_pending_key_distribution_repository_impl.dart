import '../models/group_pending_key_distribution.dart';
import 'group_pending_key_distribution_repository.dart';

class GroupPendingKeyDistributionRepositoryImpl
    implements GroupPendingKeyDistributionRepository {
  final Future<bool> Function(Map<String, Object?> row)
  dbUpsertGroupPendingKeyDistribution;
  final Future<void> Function(Map<String, Object?> row)?
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
  final Future<void> Function(
    String id, {
    required String status,
    required String lastError,
    required String finalizedAt,
  })
  dbFinalizeGroupPendingKeyDistribution;

  GroupPendingKeyDistributionRepositoryImpl({
    required this.dbUpsertGroupPendingKeyDistribution,
    this.dbReopenGroupPendingKeyDistributionForRedelivery,
    required this.dbLoadGroupPendingKeyDistribution,
    required this.dbLoadPendingGroupKeyDistributionsForPeer,
    required this.dbLoadPendingGroupKeyDistributionsForGroup,
    required this.dbRecordGroupPendingKeyDistributionAttempt,
    required this.dbFinalizeGroupPendingKeyDistribution,
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
  Future<void> reopenForRedelivery(
    GroupPendingKeyDistribution distribution,
  ) async {
    final reopen = dbReopenGroupPendingKeyDistributionForRedelivery;
    if (reopen == null) {
      // No reopen helper wired: fall back to a best-effort enqueue (creates a
      // pending row if none exists; a terminal row stays terminal).
      await dbUpsertGroupPendingKeyDistribution(distribution.toMap());
      return;
    }
    await reopen(distribution.toMap());
  }

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
}
