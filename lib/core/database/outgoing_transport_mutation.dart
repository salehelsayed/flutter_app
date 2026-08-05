/// The caller-owned shape of an ordinary outgoing transport attempt.
///
/// This is deliberately not a status rank. Each kind selects one fixed
/// database predicate; callers cannot supply predecessor lists.
enum OutgoingOrdinaryAttemptKind {
  fresh,
  existing,
  edit,
  tombstoneInitial,
  tombstoneRetry,
}

/// Selects the fixed predecessor policy for an ordinary transport settlement.
enum OutgoingOrdinarySettlementMode {
  /// A locally completed live/inbox/retry attempt. This mode requires the
  /// exact non-empty envelope that was durably staged before transport.
  live,

  /// A currently accepted peer-bound delivery receipt. This mode accepts only
  /// `inboxed`, `sent`, and `failed` predecessors and may settle an eligible
  /// legacy row whose envelope is null. Peer correlation is not authentication.
  receipt,
}

/// Stable classification returned by the atomic ordinary mutation helpers.
enum OutgoingOrdinaryMutationOutcome {
  /// The requested column-only mutation committed.
  applied,

  /// The exact requested attempt/state was already durable; no column changed.
  idempotent,

  /// A stronger concurrent result, hide, or delete won.
  preserved,

  /// The exact parent was physically removed. Mutations never recreate it.
  removed,

  /// The row, policy, identity, envelope, or requested field shape was invalid.
  refused,
}

extension OutgoingOrdinaryMutationOutcomePolicy
    on OutgoingOrdinaryMutationOutcome {
  /// Only these outcomes authorize starting transport after attempt staging.
  bool get authorizesTransport =>
      this == OutgoingOrdinaryMutationOutcome.applied ||
      this == OutgoingOrdinaryMutationOutcome.idempotent;

  bool get changed => this == OutgoingOrdinaryMutationOutcome.applied;
}
