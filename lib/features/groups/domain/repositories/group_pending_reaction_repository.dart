import '../models/group_pending_reaction.dart';

/// Durable buffer for group reactions whose target message has not yet arrived.
abstract class GroupPendingReactionRepository {
  /// Inserts/refreshes a buffered reaction (dedup by reaction id).
  Future<GroupPendingReaction> savePendingReaction(
    GroupPendingReaction reaction,
  );

  /// Buffered reactions targeting a specific message, oldest-first.
  Future<List<GroupPendingReaction>> getPendingReactionsForMessage({
    required String groupId,
    required String messageId,
  });

  /// All buffered reactions, oldest-first (used by the startup flush).
  Future<List<GroupPendingReaction>> getPendingReactions({int limit = 200});

  /// Deletes a buffered reaction by id after terminal handling succeeds.
  /// Returns the number of rows removed; in-process flush ownership prevents
  /// overlap while apply-before-delete preserves crash retryability (INV-R5).
  Future<int> deletePendingReaction(String id);

  /// Evicts oldest rows beyond [maxRows] for a group (per-group cap).
  Future<void> pruneGroup(String groupId, {required int maxRows});

  /// Deletes buffered reactions older than [olderThan] (TTL).
  Future<void> deleteExpired({required DateTime olderThan});
}
