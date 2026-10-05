import 'package:clock/clock.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository.dart';

class InMemoryInboxStagingRepository
    implements
        InboxStagingRepository,
        InboxStagingPrerequisiteWaitingRepository,
        InboxStagingProtectedAckPendingRepository,
        InboxStagingRecoverableWorkProbeRepository,
        InboxStagingNeedsAttentionMaintenanceRepository {
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
  Future<bool> hasRecoverableEntryExcluding({
    required String messageType,
    required String rejectReasonCode,
  }) async => _entries.values.any(
    (entry) =>
        (entry.status == 'pending' || entry.status == 'retryable') &&
        (entry.messageType != messageType ||
            entry.rejectReasonCode != rejectReasonCode),
  );

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
      lastAttemptedAt: clock.now().toUtc().toIso8601String(),
      rejectReasonCode: reasonCode,
      rejectReasonDetail: reasonDetail,
    );
  }

  @override
  Future<void> markProtectedAckPending(String entryId) async {
    final existing = _entries[entryId];
    if (existing == null) return;
    _entries[entryId] = existing.copyWith(status: 'protected_ack_pending');
  }

  @override
  Future<void> markPrerequisiteWaiting(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    final existing = _entries[entryId];
    if (existing == null) return;
    _entries[entryId] = existing.copyWith(
      status: 'retryable',
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
      lastAttemptedAt: clock.now().toUtc().toIso8601String(),
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
      lastAttemptedAt: clock.now().toUtc().toIso8601String(),
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

  static const _recoverableClassRejects = {
    'unknown_sender',
    'duplicate',
    'edit_missing_original',
  };

  bool _needsAttention(InboxStagingEntry entry) =>
      entry.status == 'quarantined' ||
      (entry.status == 'rejected' &&
          _recoverableClassRejects.contains(entry.rejectReasonCode));

  @override
  Future<int> countNeedsAttentionEntries() async {
    return _entries.values.where(_needsAttention).length;
  }

  /// Mirrors `dbRunInboxStagingNeedsAttentionMaintenance`.
  @override
  Future<({int abandoned, int deleted, int requeued})>
  runNeedsAttentionMaintenance({
    required List<String> messageTypes,
    required DateTime now,
    required Duration retryEvery,
    required Duration giveUpAfter,
    required Duration deleteAfter,
    required int attemptCount,
  }) async {
    bool olderThan(String? iso, Duration age) =>
        iso == null || DateTime.parse(iso).isBefore(now.subtract(age));
    bool inScope(InboxStagingEntry entry) =>
        _needsAttention(entry) && messageTypes.contains(entry.messageType);
    String previous(InboxStagingEntry entry) =>
        '${entry.status}:${entry.rejectReasonCode ?? ''}';

    var abandoned = 0;
    for (final entry in _entries.values.toList()) {
      if (inScope(entry) && olderThan(entry.stagedAt, giveUpAfter)) {
        _entries[entry.entryId] = entry.copyWith(
          status: 'abandoned',
          lastAttemptedAt: now.toUtc().toIso8601String(),
          rejectReasonCode: 'gave_up',
          rejectReasonDetail: 'gave up from ${previous(entry)}',
        );
        abandoned++;
      }
    }
    final toDelete = _entries.values
        .where(
          (entry) =>
              entry.status == 'abandoned' &&
              entry.lastAttemptedAt != null &&
              olderThan(entry.lastAttemptedAt, deleteAfter),
        )
        .map((entry) => entry.entryId)
        .toList();
    toDelete.forEach(_entries.remove);
    var requeued = 0;
    for (final entry in _entries.values.toList()) {
      if (inScope(entry) && olderThan(entry.lastAttemptedAt, retryEvery)) {
        _entries[entry.entryId] = entry.copyWith(
          status: 'retryable',
          attemptCount: attemptCount,
          rejectReasonCode: 'background_retry',
          rejectReasonDetail: 'background retry from ${previous(entry)}',
        );
        requeued++;
      }
    }
    return (abandoned: abandoned, deleted: toDelete.length, requeued: requeued);
  }
}
