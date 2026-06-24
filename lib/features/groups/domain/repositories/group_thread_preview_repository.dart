import '../models/group_thread_preview.dart';

/// Batched group-thread preview reads (161 db-persistence-5, QUERY half).
///
/// Mirrors [ConversationThreadSummaryRepository] (160) for the group feed: the
/// feed casts the [GroupMessageRepository] to this interface, batches ONE
/// preview call for all active groups, and loads a bounded windowed message
/// page ONLY for pending groups. Implemented by [GroupMessageRepositoryImpl];
/// kept separate from [GroupThreadSummaryRepository] so the orbit unread-badge
/// path is untouched.
abstract class GroupThreadPreviewRepository {
  Future<GroupThreadPreview> getGroupThreadPreview(String groupId);

  Future<Map<String, GroupThreadPreview>> getGroupThreadPreviews(
    Iterable<String> groupIds,
  );
}
