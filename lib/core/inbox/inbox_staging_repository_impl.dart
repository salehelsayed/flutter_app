import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

class InboxStagingRepositoryImpl implements InboxStagingRepository {
  final Future<void> Function(Map<String, Object?> row)
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
  })
  dbMarkInboxStagingEntryRejected;

  InboxStagingRepositoryImpl({
    required this.dbInsertInboxStagingEntry,
    required this.dbLoadRecoverableInboxStagingEntries,
    required this.dbLoadInboxStagingEntry,
    required this.dbDeleteInboxStagingEntry,
    required this.dbMarkInboxStagingEntryRetryable,
    required this.dbMarkInboxStagingEntryRejected,
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
      await dbInsertInboxStagingEntry(entry.toMap());
      ackableEntryIds.add(entry.entryId);
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
}
