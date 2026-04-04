import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository.dart';

class InMemoryInboxStagingRepository implements InboxStagingRepository {
  final Map<String, InboxStagingEntry> _entries = {};

  void seed(InboxStagingEntry entry) {
    _entries[entry.entryId] = entry;
  }

  InboxStagingEntry? entry(String entryId) => _entries[entryId];

  @override
  Future<List<String>> stageEntries(List<InboxStagingEntry> entries) async {
    for (final entry in entries) {
      _entries.putIfAbsent(entry.entryId, () => entry);
    }
    return entries.map((entry) => entry.entryId).toList();
  }

  @override
  Future<List<InboxStagingEntry>> getRecoverableEntries({
    int limit = 50,
  }) async {
    final entries =
        _entries.values
            .where(
              (entry) =>
                  entry.status == 'pending' || entry.status == 'retryable',
            )
            .toList()
          ..sort((a, b) => a.relayTimestamp.compareTo(b.relayTimestamp));
    return entries.take(limit).toList();
  }

  @override
  Future<List<InboxStagingEntry>> getRecoverableEntriesByIds(
    List<String> entryIds,
  ) async {
    return entryIds
        .map((entryId) => _entries[entryId])
        .whereType<InboxStagingEntry>()
        .where(
          (entry) => entry.status == 'pending' || entry.status == 'retryable',
        )
        .toList();
  }

  @override
  Future<InboxStagingEntry?> getEntry(String entryId) async =>
      _entries[entryId];

  @override
  Future<void> deleteEntry(String entryId) async {
    _entries.remove(entryId);
  }

  @override
  Future<void> markRetryable(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    final existing = _entries[entryId];
    if (existing == null) return;
    _entries[entryId] = existing.copyWith(
      status: 'retryable',
      attemptCount: existing.attemptCount + 1,
      lastAttemptedAt: '2026-04-01T00:00:00.000Z',
      rejectReasonCode: reasonCode,
      rejectReasonDetail: reasonDetail,
    );
  }

  @override
  Future<void> markRejected(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    final existing = _entries[entryId];
    if (existing == null) return;
    _entries[entryId] = existing.copyWith(
      status: 'rejected',
      attemptCount: existing.attemptCount + 1,
      lastAttemptedAt: '2026-04-01T00:00:00.000Z',
      rejectReasonCode: reasonCode,
      rejectReasonDetail: reasonDetail,
    );
  }
}
