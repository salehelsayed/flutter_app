import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';

/// Shared in-memory fake for [GroupPendingKeyRepairRepository].
///
/// This mirrors the canonical private copy that lived in
/// `group_pending_key_repair_service_test.dart`. Four other test files
/// (`accept_pending_group_invite_use_case_test`, `drain_group_offline_inbox_use_case_test`,
/// `group_resume_recovery_test`, `group_messaging_smoke_test`) still carry their
/// own private copies with subtly divergent `upsertPendingRepair` merge,
/// `getPendingRepairsForGroupEpoch` sort, and `finalize*` idempotency semantics —
/// they are intentionally NOT migrated here to avoid behaviour change, and are
/// tracked as tech debt. New repair-repository methods MUST be added to this
/// shared fake AND to those divergent copies (the compiler enforces it via the
/// `implements GroupPendingKeyRepairRepository` contract).
class InMemoryGroupPendingKeyRepairRepository
    implements GroupPendingKeyRepairRepository {
  final Map<String, GroupPendingKeyRepair> repairs = {};

  @override
  Future<GroupPendingKeyRepairUpsertResult> upsertPendingRepair(
    GroupPendingKeyRepair repair,
  ) async {
    final existing = repairs[repair.id];
    if (existing == null) {
      repairs[repair.id] = repair;
      return GroupPendingKeyRepairUpsertResult(repair: repair, created: true);
    }
    final merged = existing.copyWith(updatedAt: repair.updatedAt);
    repairs[repair.id] = merged;
    return GroupPendingKeyRepairUpsertResult(repair: merged, created: false);
  }

  @override
  Future<GroupPendingKeyRepair?> getRepair(String id) async => repairs[id];

  @override
  Future<List<GroupPendingKeyRepair>> getPendingRepairsForGroupEpoch({
    required String groupId,
    required int keyEpoch,
    int limit = 50,
  }) async {
    return repairs.values
        .where(
          (repair) =>
              repair.groupId == groupId &&
              repair.keyEpoch == keyEpoch &&
              repair.status == groupPendingKeyRepairStatusPendingKey,
        )
        .take(limit)
        .toList();
  }

  @override
  Future<List<GroupPendingKeyRepair>> getAllPendingRepairs({
    int limit = 200,
  }) async {
    final pending =
        repairs.values
            .where(
              (repair) =>
                  repair.status == groupPendingKeyRepairStatusPendingKey,
            )
            .toList()
          ..sort(_byCreatedThenId);
    return pending.take(limit).toList();
  }

  @override
  Future<List<GroupPendingKeyRepair>> getPendingRepairsForGroup({
    required String groupId,
    int limit = 100,
  }) async {
    final pending =
        repairs.values
            .where(
              (repair) =>
                  repair.groupId == groupId &&
                  repair.status == groupPendingKeyRepairStatusPendingKey,
            )
            .toList()
          ..sort(_byCreatedThenId);
    return pending.take(limit).toList();
  }

  static int _byCreatedThenId(GroupPendingKeyRepair a, GroupPendingKeyRepair b) {
    final byCreated = a.createdAt.compareTo(b.createdAt);
    return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
  }

  @override
  Future<void> deleteRepair(String id) async {
    repairs.remove(id);
  }

  @override
  Future<void> recordAttempt(String id, {required String? lastError}) async {
    final existing = repairs[id];
    if (existing == null) return;
    repairs[id] = existing.copyWith(
      attempts: existing.attempts + 1,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> finalizeRepaired(String id) async {
    final existing = repairs[id];
    if (existing == null || existing.finalizedAt != null) return;
    final now = DateTime.now().toUtc();
    repairs[id] = existing.copyWith(
      status: groupPendingKeyRepairStatusRepaired,
      updatedAt: now,
      finalizedAt: now,
    );
  }

  @override
  Future<void> finalizeUndecryptable(
    String id, {
    required String lastError,
  }) async {
    final existing = repairs[id];
    if (existing == null || existing.finalizedAt != null) return;
    final now = DateTime.now().toUtc();
    repairs[id] = existing.copyWith(
      status: groupPendingKeyRepairStatusUndecryptable,
      lastError: lastError,
      updatedAt: now,
      finalizedAt: now,
    );
  }
}
