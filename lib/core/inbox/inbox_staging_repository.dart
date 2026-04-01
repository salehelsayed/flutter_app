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
}
