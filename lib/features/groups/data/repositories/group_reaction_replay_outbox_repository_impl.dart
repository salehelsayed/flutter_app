import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../domain/models/group_reaction_replay_outbox_entry.dart';
import '../../domain/repositories/group_reaction_replay_outbox_repository.dart';

class GroupReactionReplayOutboxRepositoryImpl
    implements
        GroupReactionReplayOutboxRepository,
        GroupReactionReplayPayloadCasRepository,
        GroupReactionStrictContentCompletionRepository,
        GroupReactionStrictLocalTerminalRepository,
        GroupReactionStrictPreparedRepository,
        GroupReactionStrictPreparedTerminalRepository {
  final Future<bool> Function(Map<String, Object?> row)
  dbUpsertGroupReactionReplayOutboxEntry;
  final Future<bool> Function({
    required String reactionId,
    required String inboxRetryPayload,
    required String updatedAt,
  })
  dbAttachGroupReactionReplayOutboxPayload;
  final Future<Map<String, Object?>?> Function(String reactionId)
  dbLoadGroupReactionReplayOutboxEntry;
  final Future<Map<String, Object?>?> Function({
    required String groupId,
    required String messageId,
    required String senderPeerId,
  })
  dbLoadLatestGroupReactionReplayOutboxEntryForTarget;
  final Future<List<Map<String, Object?>>> Function({
    int limit,
    bool strictContentOnly,
    int offset,
  })
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
  final Future<bool> Function({
    required Map<String, Object?> expected,
    required String replacement,
    required String updatedAt,
  })?
  dbReplaceGroupReactionReplayOutboxPayloadIfExact;
  final Future<bool> Function({
    required Map<String, Object?> expected,
    required Map<String, Object?> reactionRow,
    required String action,
    required String transitionId,
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> eventPayload,
    required String updatedAt,
  })?
  dbCompleteGroupReactionContentIfExact;
  final Future<bool> Function({
    required Map<String, Object?> expected,
    required Map<String, Object?> reactionRow,
    required String action,
    required String transitionId,
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> eventPayload,
  })?
  dbStageAndCompleteLocalGroupReactionContentFn;
  final Future<bool> Function({
    required Map<String, Object?> expected,
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> preparedEventPayload,
  })?
  dbStagePreparedLocalGroupReactionContentFn;
  final Future<bool> Function({
    required Map<String, Object?> expected,
    required Map<String, Object?> preparedEventPayload,
    required String terminalSourcePeerId,
    required String terminalSourceEventId,
    required String terminalSourceTimestamp,
    required Map<String, Object?> terminalEventPayload,
  })?
  dbTerminalizePreparedLocalGroupReactionIfExactFn;
  final Future<bool> Function({
    required Map<String, Object?> expected,
    required Map<String, Object?> eventPayload,
  })?
  dbHasExactPreparedLocalGroupReactionFn;
  final Future<void> Function(String reactionId)
  dbDeleteGroupReactionReplayOutboxEntry;

  GroupReactionReplayOutboxRepositoryImpl({
    required this.dbUpsertGroupReactionReplayOutboxEntry,
    required this.dbAttachGroupReactionReplayOutboxPayload,
    required this.dbLoadGroupReactionReplayOutboxEntry,
    required this.dbLoadLatestGroupReactionReplayOutboxEntryForTarget,
    required this.dbLoadRetryableGroupReactionReplayOutboxEntries,
    required this.dbUpdateGroupReactionReplayOutboxEntryStatus,
    required this.dbUpdateGroupReactionReplayOutboxEntryStatusIfExact,
    this.dbReplaceGroupReactionReplayOutboxPayloadIfExact,
    this.dbCompleteGroupReactionContentIfExact,
    this.dbStageAndCompleteLocalGroupReactionContentFn,
    this.dbStagePreparedLocalGroupReactionContentFn,
    this.dbTerminalizePreparedLocalGroupReactionIfExactFn,
    this.dbHasExactPreparedLocalGroupReactionFn,
    required this.dbDeleteGroupReactionReplayOutboxEntry,
  });

  @override
  Future<bool> saveEntry(GroupReactionReplayOutboxEntry entry) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_REPO_SAVE_START',
      details: {
        'reactionId': entry.reactionId.length > 8
            ? entry.reactionId.substring(0, 8)
            : entry.reactionId,
      },
    );
    final inserted = await dbUpsertGroupReactionReplayOutboxEntry(
      entry.toMap(),
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REACTION_REPLAY_OUTBOX_REPO_SAVE_SUCCESS',
      details: {
        'reactionId': entry.reactionId.length > 8
            ? entry.reactionId.substring(0, 8)
            : entry.reactionId,
      },
    );
    return inserted;
  }

  @override
  Future<bool> attachBuiltPayload({
    required String reactionId,
    required String inboxRetryPayload,
  }) => dbAttachGroupReactionReplayOutboxPayload(
    reactionId: reactionId,
    inboxRetryPayload: inboxRetryPayload,
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

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
    bool strictContentOnly = false,
    int offset = 0,
  }) async {
    final rows = await dbLoadRetryableGroupReactionReplayOutboxEntries(
      limit: limit,
      strictContentOnly: strictContentOnly,
      offset: offset,
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
  Future<bool> replaceInboxRetryPayloadIfExact(
    GroupReactionReplayOutboxEntry expected,
    String replacement,
  ) {
    final replace = dbReplaceGroupReactionReplayOutboxPayloadIfExact;
    if (replace == null) return Future<bool>.value(false);
    return replace(
      expected: expected.toMap(),
      replacement: replacement,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<bool> completeStrictContentIfExact(
    GroupReactionReplayOutboxEntry expected, {
    required Map<String, Object?> reactionRow,
    required String action,
    required String transitionId,
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> eventPayload,
  }) {
    final complete = dbCompleteGroupReactionContentIfExact;
    if (complete == null) return Future<bool>.value(false);
    return complete(
      expected: expected.toMap(),
      reactionRow: reactionRow,
      action: action,
      transitionId: transitionId,
      sourcePeerId: sourcePeerId,
      sourceEventId: sourceEventId,
      sourceTimestamp: sourceTimestamp,
      eventPayload: eventPayload,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<bool> stageAndCompleteStrictLocalContent(
    GroupReactionReplayOutboxEntry entry, {
    required Map<String, Object?> reactionRow,
    required String action,
    required String transitionId,
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> eventPayload,
  }) {
    final stage = dbStageAndCompleteLocalGroupReactionContentFn;
    if (stage == null) return Future<bool>.value(false);
    return stage(
      expected: entry.toMap(),
      reactionRow: reactionRow,
      action: action,
      transitionId: transitionId,
      sourcePeerId: sourcePeerId,
      sourceEventId: sourceEventId,
      sourceTimestamp: sourceTimestamp,
      eventPayload: eventPayload,
    );
  }

  @override
  Future<bool> stageStrictContentPrepared(
    GroupReactionReplayOutboxEntry entry, {
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> preparedEventPayload,
  }) {
    final stage = dbStagePreparedLocalGroupReactionContentFn;
    if (stage == null) return Future<bool>.value(false);
    return stage(
      expected: entry.toMap(),
      sourcePeerId: sourcePeerId,
      sourceEventId: sourceEventId,
      sourceTimestamp: sourceTimestamp,
      preparedEventPayload: preparedEventPayload,
    );
  }

  @override
  Future<bool> hasExactStrictContentPrepared(
    GroupReactionReplayOutboxEntry expected, {
    required Map<String, Object?> eventPayload,
  }) {
    final check = dbHasExactPreparedLocalGroupReactionFn;
    if (check == null) return Future<bool>.value(false);
    return check(expected: expected.toMap(), eventPayload: eventPayload);
  }

  @override
  Future<bool> terminalizeStrictContentPreparedIfExact(
    GroupReactionReplayOutboxEntry expected, {
    required Map<String, Object?> preparedEventPayload,
    required String terminalSourcePeerId,
    required String terminalSourceEventId,
    required String terminalSourceTimestamp,
    required Map<String, Object?> terminalEventPayload,
  }) {
    final terminalize = dbTerminalizePreparedLocalGroupReactionIfExactFn;
    if (terminalize == null) return Future<bool>.value(false);
    return terminalize(
      expected: expected.toMap(),
      preparedEventPayload: preparedEventPayload,
      terminalSourcePeerId: terminalSourcePeerId,
      terminalSourceEventId: terminalSourceEventId,
      terminalSourceTimestamp: terminalSourceTimestamp,
      terminalEventPayload: terminalEventPayload,
    );
  }

  @override
  Future<void> deleteEntry(String reactionId) {
    return dbDeleteGroupReactionReplayOutboxEntry(reactionId);
  }
}
