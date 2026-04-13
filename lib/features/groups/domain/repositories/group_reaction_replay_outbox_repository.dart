import '../models/group_reaction_replay_outbox_entry.dart';

abstract class GroupReactionReplayOutboxRepository {
  Future<void> saveEntry(GroupReactionReplayOutboxEntry entry);

  Future<GroupReactionReplayOutboxEntry?> getEntry(String reactionId);

  Future<List<GroupReactionReplayOutboxEntry>> loadRetryableEntries({
    int limit = 20,
  });

  Future<void> updateEntryStatus(
    String reactionId, {
    required String deliveryStatus,
    String? lastError,
  });

  Future<void> deleteEntry(String reactionId);
}
