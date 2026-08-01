import '../models/group_reaction_replay_outbox_entry.dart';

abstract class GroupReactionReplayOutboxRepository {
  /// Persists (upsert by reaction id) and reports whether a row now exists.
  ///
  /// Plan 319: the return value is load-bearing — the group-parent write guard
  /// silently inserts zero rows for a self-removed parent, and a caller that
  /// assumed success staged custody that does not exist.
  Future<bool> saveEntry(GroupReactionReplayOutboxEntry entry);

  /// Plan 319: promotes a `needs_build` row to `pending` with its built
  /// payload, atomically. Returns false when no such row exists (it was swept
  /// by a group exit, self-removal, or message deletion mid-build).
  Future<bool> attachBuiltPayload({
    required String reactionId,
    required String inboxRetryPayload,
  }) async => false;

  Future<GroupReactionReplayOutboxEntry?> getEntry(String reactionId);

  /// Latest persisted transition for one logical sender/target pair. Send and
  /// remove use this to reuse an exact pending/stored transition on retry while
  /// still allocating a fresh id after the opposite action.
  Future<GroupReactionReplayOutboxEntry?> getLatestEntryForTarget({
    required String groupId,
    required String messageId,
    required String senderPeerId,
  }) async => null;

  Future<List<GroupReactionReplayOutboxEntry>> loadRetryableEntries({
    int limit = 20,
  });

  Future<void> updateEntryStatus(
    String reactionId, {
    required String deliveryStatus,
    String? lastError,
  });

  /// Applies a loaded replay action's completion only if the complete durable
  /// row is still identical. Implementations without the atomic capability
  /// fail closed so an old network result cannot settle replacement work.
  Future<bool> updateEntryStatusIfExact(
    GroupReactionReplayOutboxEntry expected, {
    required String deliveryStatus,
    String? lastError,
  }) async => false;

  Future<void> deleteEntry(String reactionId);
}
