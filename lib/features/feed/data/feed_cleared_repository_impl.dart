import 'feed_cleared_repository.dart';

/// Closure-injection implementation of [FeedClearedRepository] (mirrors
/// `PostsPrivacySettingsRepositoryImpl`): the DB helpers are injected as
/// closures, so this class never references a `Database` and stays trivially
/// unit-testable.
class FeedClearedRepositoryImpl implements FeedClearedRepository {
  final Future<void> Function(
    String threadKind,
    String threadId,
    int clearedAtMs,
  ) dbMarkFeedClearedThread;

  final Future<void> Function(String threadKind, String threadId)
      dbClearFeedClearedThread;

  final Future<List<Map<String, Object?>>> Function() dbLoadFeedClearedThreads;

  /// Invoked ONLY when [markCleared] is called with `markRead: true` (commit).
  /// Left null in pure-persistence contexts (tests, isolated wiring).
  final Future<void> Function(String threadKind, String threadId)?
      markThreadRead;

  FeedClearedRepositoryImpl({
    required this.dbMarkFeedClearedThread,
    required this.dbClearFeedClearedThread,
    required this.dbLoadFeedClearedThreads,
    this.markThreadRead,
  });

  @override
  Future<void> markCleared(
    String threadKind,
    String threadId,
    int clearedAtMs, {
    required bool markRead,
  }) async {
    await dbMarkFeedClearedThread(threadKind, threadId, clearedAtMs);
    if (markRead) {
      await markThreadRead?.call(threadKind, threadId);
    }
  }

  @override
  Future<void> clearCleared(String threadKind, String threadId) async {
    await dbClearFeedClearedThread(threadKind, threadId);
  }

  @override
  Future<Map<(String, String), int>> getClearedWatermarks() async {
    final rows = await dbLoadFeedClearedThreads();
    final result = <(String, String), int>{};
    for (final row in rows) {
      final kind = row['thread_kind'] as String;
      final id = row['thread_id'] as String;
      final ms = (row['cleared_at_ms'] as num).toInt();
      result[(kind, id)] = ms;
    }
    return result;
  }
}
