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

  /// 172: kept-but-undisplayed entries: quarantined rows PLUS historical `rejected` rows in the recoverable
  /// classes (unknown_sender / duplicate / edit_missing_original) that the
  /// pre-172 code terminally rejected. Content-safe rejections never count.
  Future<int> countNeedsAttentionEntries();
}

/// Optional background clean-up of the needs-attention rows (quarantined and
/// recoverable-class rejected). The app shows no UI for them: each run gives
/// them one more replay attempt at most once per [retryEvery], gives up on
/// rows older than [giveUpAfter], and deletes given-up rows after
/// [deleteAfter]. Only rows of [messageTypes] are touched.
abstract interface class InboxStagingNeedsAttentionMaintenanceRepository {
  Future<({int abandoned, int deleted, int requeued})>
  runNeedsAttentionMaintenance({
    required List<String> messageTypes,
    required DateTime now,
    required Duration retryEvery,
    required Duration giveUpAfter,
    required Duration deleteAfter,
    required int attemptCount,
  });
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

/// Optional existence probe for recoverable work other than one parked kind.
/// A recovery-only runtime parks foreground-only rows (for example plaintext
/// delivery receipts) as retryable; they can outnumber any page size, so a
/// capped page of recoverable rows cannot prove nothing else is waiting.
abstract interface class InboxStagingRecoverableWorkProbeRepository {
  Future<bool> hasRecoverableEntryExcluding({
    required String messageType,
    required String rejectReasonCode,
  });
}

/// Terminal protected replay awaiting the relay's exact ACK. The local bytes
/// stay durable but are excluded from ordinary replay/attempt accounting.
abstract interface class InboxStagingProtectedAckPendingRepository {
  Future<void> markProtectedAckPending(String entryId);
}
