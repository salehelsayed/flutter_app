import 'package:flutter_app/features/feed/data/feed_cleared_repository.dart';

/// In-memory [FeedClearedRepository] for widget/unit tests (134-P4/P5). Holds
/// the cleared watermarks in a plain map; no database, no markRead side effect.
class InMemoryFeedClearedRepository implements FeedClearedRepository {
  final Map<(String, String), int> _watermarks = {};

  /// Records every (kind, id, ms, markRead) call so tests can assert dismiss vs
  /// commit semantics (markRead true only for swipe-commit).
  final List<({String kind, String id, int ms, bool markRead})> markCalls = [];
  final List<({String kind, String id})> clearCalls = [];

  @override
  Future<void> markCleared(
    String threadKind,
    String threadId,
    int clearedAtMs, {
    required bool markRead,
  }) async {
    _watermarks[(threadKind, threadId)] = clearedAtMs;
    markCalls.add((
      kind: threadKind,
      id: threadId,
      ms: clearedAtMs,
      markRead: markRead,
    ));
  }

  @override
  Future<void> clearCleared(String threadKind, String threadId) async {
    _watermarks.remove((threadKind, threadId));
    clearCalls.add((kind: threadKind, id: threadId));
  }

  @override
  Future<Map<(String, String), int>> getClearedWatermarks() async {
    return Map<(String, String), int>.from(_watermarks);
  }
}
