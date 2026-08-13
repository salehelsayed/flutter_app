import 'inbox_staging_entry.dart';

abstract class InboxStagingRepository {
  Future<List<String>> stageEntries(List<InboxStagingEntry> entries);

  Future<List<InboxStagingEntry>> getRecoverableEntries({int limit = 50});

  Future<List<InboxStagingEntry>> getRecoverableEntriesByIds(
    List<String> entryIds,
  );

  Future<InboxStagingEntry?> getEntry(String entryId);

  Future<void> deleteEntry(String entryId);

  Future<void> markRetryable(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  });

  Future<void> markRejected(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  });

  /// Terminal keep-state: the entry is excluded from replay but its
  /// envelope is preserved (INV-1: never destroy content after custody
  /// transfer).
  Future<void> markQuarantined(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  });

  Future<int> countQuarantinedEntries();

  /// 172 (INV-2): kept-but-undisplayed entries the user must be able to see —
  /// quarantined rows PLUS historical `rejected` rows in the recoverable
  /// classes (unknown_sender / duplicate / edit_missing_original) that the
  /// pre-172 code terminally rejected. Content-safe rejections never count.
  Future<int> countNeedsAttentionEntries();
}

/// Optional status-only transition for protected group authority waiting on a
/// bootstrap. It deliberately does not increment `attempt_count`, so an
/// arbitrarily long authority-before-bootstrap race cannot quarantine itself.
abstract interface class InboxStagingPrerequisiteWaitingRepository {
  Future<void> markPrerequisiteWaiting(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  });
}

/// Terminal protected replay awaiting the relay's exact ACK. The local bytes
/// stay durable but are excluded from ordinary replay/attempt accounting.
abstract interface class InboxStagingProtectedAckPendingRepository {
  Future<void> markProtectedAckPending(String entryId);
}
