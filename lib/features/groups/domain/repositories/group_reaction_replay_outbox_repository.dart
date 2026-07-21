import '../models/group_reaction_replay_outbox_entry.dart';

abstract class GroupReactionReplayOutboxRepository {
  Future<void> saveEntry(GroupReactionReplayOutboxEntry entry);

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
