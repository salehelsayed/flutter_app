import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../domain/models/group_reaction_replay_outbox_entry.dart';
import '../../domain/repositories/group_reaction_replay_outbox_repository.dart';

class GroupReactionReplayOutboxRepositoryImpl
    implements GroupReactionReplayOutboxRepository {
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertGroupReactionReplayOutboxEntry;
  final Future<Map<String, Object?>?> Function(String reactionId)
  dbLoadGroupReactionReplayOutboxEntry;
  final Future<Map<String, Object?>?> Function({
    required String groupId,
    required String messageId,
    required String senderPeerId,
  })
  dbLoadLatestGroupReactionReplayOutboxEntryForTarget;
  final Future<List<Map<String, Object?>>> Function({int limit})
  dbLoadRetryableGroupReactionReplayOutboxEntries;
  final Future<void> Function(
    String reactionId, {
    required String deliveryStatus,
    String? lastError,
    required String updatedAt,
  })
  dbUpdateGroupReactionReplayOutboxEntryStatus;
  final Future<bool> Function({
    required Map<String, Object?> expected,
    required String deliveryStatus,
    String? lastError,
    required String updatedAt,
  })
  dbUpdateGroupReactionReplayOutboxEntryStatusIfExact;
  final Future<void> Function(String reactionId)
  dbDeleteGroupReactionReplayOutboxEntry;

  GroupReactionReplayOutboxRepositoryImpl({
    required this.dbUpsertGroupReactionReplayOutboxEntry,
    required this.dbLoadGroupReactionReplayOutboxEntry,
    required this.dbLoadLatestGroupReactionReplayOutboxEntryForTarget,
    required this.dbLoadRetryableGroupReactionReplayOutboxEntries,
    required this.dbUpdateGroupReactionReplayOutboxEntryStatus,
    required this.dbUpdateGroupReactionReplayOutboxEntryStatusIfExact,
    required this.dbDeleteGroupReactionReplayOutboxEntry,
  });

  @override
  Future<void> saveEntry(GroupReactionReplayOutboxEntry entry) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_REPO_SAVE_START',
      details: {
        'reactionId': entry.reactionId.length > 8
            ? entry.reactionId.substring(0, 8)
            : entry.reactionId,
      },
    );
    await dbUpsertGroupReactionReplayOutboxEntry(entry.toMap());
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_REPO_SAVE_SUCCESS',
      details: {
        'reactionId': entry.reactionId.length > 8
            ? entry.reactionId.substring(0, 8)
            : entry.reactionId,
      },
    );
  }

  @override
  Future<GroupReactionReplayOutboxEntry?> getEntry(String reactionId) async {
    final row = await dbLoadGroupReactionReplayOutboxEntry(reactionId);
    if (row == null) return null;
    return GroupReactionReplayOutboxEntry.fromMap(row);
  }

  @override
  Future<GroupReactionReplayOutboxEntry?> getLatestEntryForTarget({
    required String groupId,
    required String messageId,
    required String senderPeerId,
  }) async {
    final row = await dbLoadLatestGroupReactionReplayOutboxEntryForTarget(
      groupId: groupId,
      messageId: messageId,
      senderPeerId: senderPeerId,
    );
    return row == null ? null : GroupReactionReplayOutboxEntry.fromMap(row);
  }

  @override
  Future<List<GroupReactionReplayOutboxEntry>> loadRetryableEntries({
    int limit = 20,
  }) async {
    final rows = await dbLoadRetryableGroupReactionReplayOutboxEntries(
      limit: limit,
    );
    return rows.map(GroupReactionReplayOutboxEntry.fromMap).toList();
  }

  @override
  Future<void> updateEntryStatus(
    String reactionId, {
    required String deliveryStatus,
    String? lastError,
  }) async {
    await dbUpdateGroupReactionReplayOutboxEntryStatus(
      reactionId,
      deliveryStatus: deliveryStatus,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<bool> updateEntryStatusIfExact(
    GroupReactionReplayOutboxEntry expected, {
    required String deliveryStatus,
    String? lastError,
  }) {
    return dbUpdateGroupReactionReplayOutboxEntryStatusIfExact(
      expected: expected.toMap(),
      deliveryStatus: deliveryStatus,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> deleteEntry(String reactionId) {
    return dbDeleteGroupReactionReplayOutboxEntry(reactionId);
  }
}
