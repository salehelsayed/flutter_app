/// Bounded failure classifications persisted with a retained reaction event.
abstract final class DirectReactionInboxCustodyErrorCode {
  static const String storeFailed = 'store_failed';
  static const String storeRejectedFull = 'store_rejected_full';
  static const String storeThrew = 'store_threw';
  static const String localCompletionFailed = 'local_completion_failed';

  static const Set<String> values = <String>{
    storeFailed,
    storeRejectedFull,
    storeThrew,
    localCompletionFailed,
  };
}

/// Result of the canonical-reaction plus immutable-custody transaction.
enum DirectReactionCustodyStageOutcome { applied, idempotent, refused }

extension DirectReactionCustodyStageOutcomePolicy
    on DirectReactionCustodyStageOutcome {
  bool get authorizesTransport =>
      this == DirectReactionCustodyStageOutcome.applied ||
      this == DirectReactionCustodyStageOutcome.idempotent;
}

/// Storage-level stage result. The exact persisted custody row is returned so
/// transport completion never needs a racy post-commit lookup.
class DbDirectReactionCustodyStageResult {
  const DbDirectReactionCustodyStageResult({
    required this.outcome,
    required this.custodyRow,
  });

  final DirectReactionCustodyStageOutcome outcome;
  final Map<String, Object?>? custodyRow;
}

/// Result of retiring one remotely accepted immutable event.
enum DirectReactionInboxCustodyCompletionOutcome {
  /// The exact row was deleted.
  completed,

  /// Another overlapping accepted attempt already deleted the tuple.
  absent,

  /// The tuple exists but no longer has the caller's exact envelope.
  stale,
}

extension DirectReactionInboxCustodyCompletionOutcomePolicy
    on DirectReactionInboxCustodyCompletionOutcome {
  bool get converged =>
      this != DirectReactionInboxCustodyCompletionOutcome.stale;
}
