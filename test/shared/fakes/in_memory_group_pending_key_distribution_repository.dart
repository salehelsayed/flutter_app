import 'package:flutter_app/features/groups/domain/models/group_pending_key_distribution.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_distribution_repository.dart';

/// In-memory [GroupPendingKeyDistributionRepository] for tests — backs a real
/// [GroupPendingKeyDistributionRunner] so the durable enqueue→drain→re-distribute
/// path can be exercised in-process (e.g. the B1b sibling-device admission sim).
///
/// Behaviour mirrors the SQLCipher-backed implementation: enqueue is an upsert
/// that merges into a still-pending row and leaves finalized rows untouched;
/// recordAttempt/finalize* are no-ops once a row is finalized.
class InMemoryGroupPendingKeyDistributionRepository
    implements GroupPendingKeyDistributionRepository {
  final Map<String, GroupPendingKeyDistribution> rows = {};

  @override
  Future<GroupPendingKeyDistributionUpsertResult> enqueue(
    GroupPendingKeyDistribution distribution,
  ) async {
    final existing = rows[distribution.id];
    if (existing == null) {
      rows[distribution.id] = distribution;
      return GroupPendingKeyDistributionUpsertResult(
        distribution: distribution,
        created: true,
      );
    }
    if (existing.status != groupPendingKeyDistributionStatusPending) {
      return GroupPendingKeyDistributionUpsertResult(
        distribution: existing,
        created: false,
      );
    }
    final merged = existing.copyWith(
      keyEpoch: distribution.keyEpoch,
      updatedAt: distribution.updatedAt,
    );
    rows[distribution.id] = merged;
    return GroupPendingKeyDistributionUpsertResult(
      distribution: merged,
      created: false,
    );
  }

  @override
  Future<void> reopenForRedelivery(
    GroupPendingKeyDistribution distribution,
  ) async {
    final existing = rows[distribution.id];
    if (existing == null) {
      rows[distribution.id] = distribution;
      return;
    }
    final requestedGeneration = distribution.createdAt.toUtc();
    final minimumNextGeneration = existing.createdAt.toUtc().add(
      const Duration(microseconds: 1),
    );
    final nextGeneration = requestedGeneration.isAfter(minimumNextGeneration)
        ? requestedGeneration
        : minimumNextGeneration;
    // Force back to pending for re-delivery, OVERRIDING a terminal status and
    // resetting attempts/lastError/finalizedAt. `createdAt` is the durable
    // operation generation and advances for every intentional re-arm,
    // including an already-pending same-device re-announce.
    rows[distribution.id] = existing.copyWith(
      status: groupPendingKeyDistributionStatusPending,
      keyEpoch: distribution.keyEpoch,
      attempts: 0,
      lastError: null,
      finalizedAt: null,
      createdAt: nextGeneration,
      updatedAt: distribution.updatedAt,
    );
  }

  @override
  Future<GroupPendingKeyDistribution?> getDistribution(String id) async =>
      rows[id];

  @override
  Future<List<GroupPendingKeyDistribution>> getPendingForPeer({
    required String peerId,
    String? groupId,
    int limit = 50,
  }) async {
    return rows.values
        .where(
          (row) =>
              row.peerId == peerId &&
              (groupId == null || row.groupId == groupId) &&
              row.status == groupPendingKeyDistributionStatusPending,
        )
        .take(limit)
        .toList();
  }

  @override
  Future<List<GroupPendingKeyDistribution>> getPendingForGroup({
    required String groupId,
    int limit = 50,
  }) async {
    return rows.values
        .where(
          (row) =>
              row.groupId == groupId &&
              row.status == groupPendingKeyDistributionStatusPending,
        )
        .take(limit)
        .toList();
  }

  @override
  Future<void> recordAttempt(String id, {required String? lastError}) async {
    final existing = rows[id];
    if (existing == null ||
        existing.status != groupPendingKeyDistributionStatusPending) {
      return;
    }
    rows[id] = existing.copyWith(
      attempts: existing.attempts + 1,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> finalizeDistributed(String id) async {
    final existing = rows[id];
    if (existing == null || existing.finalizedAt != null) return;
    final now = DateTime.now().toUtc();
    rows[id] = existing.copyWith(
      status: groupPendingKeyDistributionStatusDistributed,
      updatedAt: now,
      finalizedAt: now,
    );
  }

  @override
  Future<void> finalizeUnreachable(String id, {required String lastError}) async {
    final existing = rows[id];
    if (existing == null || existing.finalizedAt != null) return;
    final now = DateTime.now().toUtc();
    rows[id] = existing.copyWith(
      status: groupPendingKeyDistributionStatusUnreachable,
      lastError: lastError,
      updatedAt: now,
      finalizedAt: now,
    );
  }
}
