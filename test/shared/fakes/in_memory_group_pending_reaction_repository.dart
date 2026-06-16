import 'package:flutter_app/features/groups/domain/models/group_pending_reaction.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_reaction_repository.dart';

/// In-memory fake of [GroupPendingReactionRepository] for tests. Mirrors the
/// real impl's semantics: dedup by id (PK), oldest-first ordering, atomic
/// claim-on-delete, per-group cap, and TTL.
class InMemoryGroupPendingReactionRepository
    implements GroupPendingReactionRepository {
  final Map<String, GroupPendingReaction> _reactions = {};

  int savePendingReactionCallCount = 0;
  int deletePendingReactionCallCount = 0;

  List<GroupPendingReaction> get reactions {
    final rows = _reactions.values.toList()
      ..sort((a, b) {
        final byReceivedAt = a.receivedAt.compareTo(b.receivedAt);
        return byReceivedAt != 0 ? byReceivedAt : a.id.compareTo(b.id);
      });
    return rows;
  }

  @override
  Future<GroupPendingReaction> savePendingReaction(
    GroupPendingReaction reaction,
  ) async {
    savePendingReactionCallCount++;
    _reactions[reaction.id] = reaction;
    return reaction;
  }

  @override
  Future<List<GroupPendingReaction>> getPendingReactionsForMessage({
    required String groupId,
    required String messageId,
  }) async {
    return reactions
        .where((r) => r.groupId == groupId && r.messageId == messageId)
        .toList(growable: false);
  }

  @override
  Future<List<GroupPendingReaction>> getPendingReactions({
    int limit = 200,
  }) async {
    return reactions.take(limit).toList(growable: false);
  }

  @override
  Future<int> deletePendingReaction(String id) async {
    deletePendingReactionCallCount++;
    return _reactions.remove(id) != null ? 1 : 0;
  }

  @override
  Future<void> pruneGroup(String groupId, {required int maxRows}) async {
    if (maxRows < 1) return;
    final groupRows = reactions
        .where((r) => r.groupId == groupId)
        .toList(growable: false);
    if (groupRows.length <= maxRows) return;
    // Oldest-first eviction: drop the leading (oldest) rows beyond the cap.
    for (final row in groupRows.take(groupRows.length - maxRows)) {
      _reactions.remove(row.id);
    }
  }

  @override
  Future<void> deleteExpired({required DateTime olderThan}) async {
    _reactions.removeWhere(
      (_, r) => r.receivedAt.isBefore(olderThan.toUtc()),
    );
  }
}
