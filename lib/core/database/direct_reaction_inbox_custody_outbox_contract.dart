import 'outgoing_transport_mutation.dart';

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

/// Result of atomically staging one ordinary edit/deletion parent and its
/// immutable event in the shared physical v109 outbox.
class DbDirectTextMutationCustodyStageResult {
  const DbDirectTextMutationCustodyStageResult({
    required this.outcome,
    required this.custodyRow,
  });

  final OutgoingOrdinaryMutationOutcome outcome;
  final Map<String, Object?>? custodyRow;
}

/// Result of atomically staging one v1 Protected/View-Once delete-for-everyone
/// tombstone and its immutable event in the same shared physical v109 outbox.
///
/// 356: the committed parent row is returned with the custody row so the caller
/// never re-reads a parent that private cleanup may already have terminalized.
class DbDirectPrivateDeletionCustodyStageResult {
  const DbDirectPrivateDeletionCustodyStageResult({
    required this.outcome,
    this.messageRow,
    this.custodyRow,
  });

  const DbDirectPrivateDeletionCustodyStageResult.refused()
    : outcome = OutgoingOrdinaryMutationOutcome.refused,
      messageRow = null,
      custodyRow = null;

  final OutgoingOrdinaryMutationOutcome outcome;
  final Map<String, Object?>? messageRow;
  final Map<String, Object?>? custodyRow;

  bool get authorizesTransport => outcome.authorizesTransport;
}

/// Result of transferring one exact mutation event to protected relay custody.
enum DirectMutationInboxCustodyCompletionOutcome {
  completed,
  absent,
  stale,
  ambiguous,
}

extension DirectMutationInboxCustodyCompletionOutcomePolicy
    on DirectMutationInboxCustodyCompletionOutcome {
  bool get converged =>
      this == DirectMutationInboxCustodyCompletionOutcome.completed ||
      this == DirectMutationInboxCustodyCompletionOutcome.absent;
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
