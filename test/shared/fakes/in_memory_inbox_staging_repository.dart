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
    final ackableEntryIds = <String>[];
    for (final entry in entries) {
      // Mirror the real repo (F3): only report an entry ackable when this call
      // actually inserted it. A re-stage of an already-present entry is a no-op
      // and must NOT be re-reported as ackable.
      final inserted = !_entries.containsKey(entry.entryId);
      if (inserted) {
        _entries[entry.entryId] = entry;
        ackableEntryIds.add(entry.entryId);
      }
    }
    return ackableEntryIds;
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

  @override
  Future<void> markQuarantined(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    final existing = _entries[entryId];
    if (existing == null) return;
    _entries[entryId] = existing.copyWith(
      status: 'quarantined',
      attemptCount: existing.attemptCount + 1,
      lastAttemptedAt: '2026-04-01T00:00:00.000Z',
      rejectReasonCode: reasonCode,
      rejectReasonDetail: reasonDetail,
    );
  }

  @override
  Future<int> countQuarantinedEntries() async {
    return _entries.values
        .where((entry) => entry.status == 'quarantined')
        .length;
  }
}
