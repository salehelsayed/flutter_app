/// Persistence boundary for the Feed's "cleared" watermarks (134, decision 2).
///
/// A cleared watermark hides a thread from the pending-reply inbox. The Feed
/// projection (`projectPendingFeed`) drops a thread whose newest incoming
/// message is NOT strictly newer than its `cleared_at_ms` (connection letters
/// use presence — any cleared row hides them).
abstract class FeedClearedRepository {
  /// Persist a cleared watermark for [threadKind]/[threadId] at [clearedAtMs].
  ///
  /// When [markRead] is true (swipe-right commit), the underlying thread is
  /// ALSO marked read via the injected read-marking side effect. When false
  /// (swipe-left dismiss), ONLY the cleared row is written — read-state, the
  /// unread badge and Orbit are never touched (INV-2 dismiss isolation).
  Future<void> markCleared(
    String threadKind,
    String threadId,
    int clearedAtMs, {
    required bool markRead,
  });

  /// Reverse a prior [markCleared] (Undo): removes the cleared row so the
  /// thread can re-surface. Does not re-mark anything unread.
  Future<void> clearCleared(String threadKind, String threadId);

  /// All cleared watermarks keyed by `(threadKind, threadId)` → `cleared_at_ms`.
  Future<Map<(String, String), int>> getClearedWatermarks();
}
