/// Bounded failure classifications persisted with a retained custody row.
abstract final class DirectInboxCustodyErrorCode {
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

/// The exact local result of completing remotely accepted custody.
enum DirectInboxCustodyCompletionOutcome {
  /// The weaker outgoing message was advanced to `inboxed`.
  messageAdvanced,

  /// A delivered, deleted, hidden, or already-inboxed message was preserved.
  messagePreserved,

  /// The independent custody row completed after its message was removed.
  messageRemoved,

  /// The requested incarnation no longer owns the scoped outbox row.
  stale,
}

extension DirectInboxCustodyCompletionOutcomePolicy
    on DirectInboxCustodyCompletionOutcome {
  bool get completed => this != DirectInboxCustodyCompletionOutcome.stale;

  bool get messageChanged =>
      this == DirectInboxCustodyCompletionOutcome.messageAdvanced;
}
