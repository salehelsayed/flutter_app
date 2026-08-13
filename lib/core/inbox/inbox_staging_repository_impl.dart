import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

class InboxStagingRepositoryImpl
    implements
        InboxStagingRepository,
        InboxStagingPrerequisiteWaitingRepository,
        InboxStagingProtectedAckPendingRepository {
  final Future<int> Function(Map<String, Object?> row)
  dbInsertInboxStagingEntry;
  final Future<List<Map<String, Object?>>> Function({
    int limit,
    List<String>? entryIds,
  })
  dbLoadRecoverableInboxStagingEntries;
  final Future<Map<String, Object?>?> Function(String entryId)
  dbLoadInboxStagingEntry;
  final Future<int> Function(String entryId) dbDeleteInboxStagingEntry;
  final Future<int> Function(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  })
  dbMarkInboxStagingEntryRetryable;
  final Future<int> Function(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  })?
  dbMarkInboxStagingEntryPrerequisiteWaiting;
  final Future<int> Function(String entryId)?
  dbMarkInboxStagingEntryProtectedAckPending;
  final Future<int> Function(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  })
  dbMarkInboxStagingEntryRejected;
  final Future<int> Function(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  })
  dbMarkInboxStagingEntryQuarantined;
  final Future<int> Function() dbCountQuarantinedInboxStagingEntries;

  /// 172: optional so existing construction sites keep compiling; when absent,
  /// [countNeedsAttentionEntries] degrades to the quarantined-only count (a
  /// truthful subset — it under-counts historical rejected recoverables, never
  /// over-counts).
  final Future<int> Function()? dbCountNeedsAttentionInboxStagingEntries;

  InboxStagingRepositoryImpl({
    required this.dbInsertInboxStagingEntry,
    required this.dbLoadRecoverableInboxStagingEntries,
    required this.dbLoadInboxStagingEntry,
    required this.dbDeleteInboxStagingEntry,
    required this.dbMarkInboxStagingEntryRetryable,
    this.dbMarkInboxStagingEntryPrerequisiteWaiting,
    this.dbMarkInboxStagingEntryProtectedAckPending,
    required this.dbMarkInboxStagingEntryRejected,
    required this.dbMarkInboxStagingEntryQuarantined,
    required this.dbCountQuarantinedInboxStagingEntries,
    this.dbCountNeedsAttentionInboxStagingEntries,
  });

  @override
  Future<List<String>> stageEntries(List<InboxStagingEntry> entries) async {
    final ackableEntryIds = <String>[];

    for (final entry in entries) {
      emitFlowEvent(
        layer: 'FL',
        event: 'INBOX_STAGING_REPO_STAGE_ENTRY',
        details: {
          'entryId': entry.entryId.length > 8
              ? entry.entryId.substring(0, 8)
              : entry.entryId,
          'messageType': entry.messageType,
        },
      );
      final insertedRowId = await dbInsertInboxStagingEntry(entry.toMap());
      // Only ack an entry this drain actually inserted. A `ConflictAlgorithm
      // .ignore` no-op (entry already staged by a prior/concurrent drain)
      // returns 0 — re-acking it would let a second drain ack + replay the same
      // entry the first drain already owns, double-delivering it (F3).
      if (insertedRowId != 0) {
        ackableEntryIds.add(entry.entryId);
      }
    }

    return ackableEntryIds;
  }

  @override
  Future<List<InboxStagingEntry>> getRecoverableEntries({
    int limit = 50,
  }) async {
    final rows = await dbLoadRecoverableInboxStagingEntries(limit: limit);
    return rows.map(InboxStagingEntry.fromMap).toList();
  }

  @override
  Future<List<InboxStagingEntry>> getRecoverableEntriesByIds(
    List<String> entryIds,
  ) async {
    final rows = await dbLoadRecoverableInboxStagingEntries(
      limit: entryIds.length,
      entryIds: entryIds,
    );
    return rows.map(InboxStagingEntry.fromMap).toList();
  }

  @override
  Future<InboxStagingEntry?> getEntry(String entryId) async {
    final row = await dbLoadInboxStagingEntry(entryId);
    if (row == null) return null;
    return InboxStagingEntry.fromMap(row);
  }

  @override
  Future<void> deleteEntry(String entryId) async {
    await dbDeleteInboxStagingEntry(entryId);
  }

  @override
  Future<void> markRetryable(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    await dbMarkInboxStagingEntryRetryable(
      entryId,
      reasonCode: reasonCode,
      reasonDetail: reasonDetail,
    );
  }

  @override
  Future<void> markPrerequisiteWaiting(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    final mark = dbMarkInboxStagingEntryPrerequisiteWaiting;
    if (mark == null) return;
    await mark(entryId, reasonCode: reasonCode, reasonDetail: reasonDetail);
  }

  @override
  Future<void> markProtectedAckPending(String entryId) async {
    await dbMarkInboxStagingEntryProtectedAckPending?.call(entryId);
  }

  @override
  Future<void> markRejected(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    await dbMarkInboxStagingEntryRejected(
      entryId,
      reasonCode: reasonCode,
      reasonDetail: reasonDetail,
    );
  }

  @override
  Future<void> markQuarantined(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    await dbMarkInboxStagingEntryQuarantined(
      entryId,
      reasonCode: reasonCode,
      reasonDetail: reasonDetail,
    );
  }

  @override
  Future<int> countQuarantinedEntries() async {
    return dbCountQuarantinedInboxStagingEntries();
  }

  @override
  Future<int> countNeedsAttentionEntries() async {
    final needsAttention = dbCountNeedsAttentionInboxStagingEntries;
    if (needsAttention != null) {
      return needsAttention();
    }
    return dbCountQuarantinedInboxStagingEntries();
  }
}
