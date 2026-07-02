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
