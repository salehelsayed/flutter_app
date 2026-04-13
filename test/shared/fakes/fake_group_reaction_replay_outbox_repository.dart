import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';

class FakeGroupReactionReplayOutboxRepository
    implements GroupReactionReplayOutboxRepository {
  final Map<String, GroupReactionReplayOutboxEntry> _entries = {};

  int saveEntryCallCount = 0;
  int updateEntryStatusCallCount = 0;
  int deleteEntryCallCount = 0;

  List<GroupReactionReplayOutboxEntry> get entries =>
      _entries.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> saveEntry(GroupReactionReplayOutboxEntry entry) async {
    saveEntryCallCount++;
    _entries[entry.reactionId] = entry;
  }

  @override
  Future<GroupReactionReplayOutboxEntry?> getEntry(String reactionId) async {
    return _entries[reactionId];
  }

  @override
  Future<List<GroupReactionReplayOutboxEntry>> loadRetryableEntries({
    int limit = 20,
  }) async {
    return entries
        .where(
          (entry) =>
              entry.deliveryStatus == GroupReactionReplayOutboxStatus.pending ||
              entry.deliveryStatus == GroupReactionReplayOutboxStatus.failed,
        )
        .take(limit)
        .toList();
  }

  @override
  Future<void> updateEntryStatus(
    String reactionId, {
    required String deliveryStatus,
    String? lastError,
  }) async {
    updateEntryStatusCallCount++;
    final existing = _entries[reactionId];
    if (existing == null) return;
    _entries[reactionId] = existing.copyWith(
      deliveryStatus: deliveryStatus,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> deleteEntry(String reactionId) async {
    deleteEntryCallCount++;
    _entries.remove(reactionId);
  }
}
