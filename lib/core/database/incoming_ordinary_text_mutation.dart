/// The three ordinary incoming projections serialized by one DB transaction.
enum IncomingOrdinaryTextMutationKind { initial, edit, deletion }

/// Durable disposition of one conditional incoming ordinary-text apply.
enum IncomingOrdinaryTextMutationOutcome {
  inserted,
  updated,
  exactReplay,
  superseded,
  unauthorized,
  refused,
}

extension IncomingOrdinaryTextMutationOutcomePolicy
    on IncomingOrdinaryTextMutationOutcome {
  bool get isDurable => switch (this) {
    IncomingOrdinaryTextMutationOutcome.inserted ||
    IncomingOrdinaryTextMutationOutcome.updated ||
    IncomingOrdinaryTextMutationOutcome.exactReplay ||
    IncomingOrdinaryTextMutationOutcome.superseded => true,
    IncomingOrdinaryTextMutationOutcome.unauthorized ||
    IncomingOrdinaryTextMutationOutcome.refused => false,
  };

  bool get changed =>
      this == IncomingOrdinaryTextMutationOutcome.inserted ||
      this == IncomingOrdinaryTextMutationOutcome.updated;
}

class DbIncomingOrdinaryTextMutationResult {
  const DbIncomingOrdinaryTextMutationResult({
    required this.outcome,
    required this.row,
  });

  final IncomingOrdinaryTextMutationOutcome outcome;
  final Map<String, Object?>? row;
}

/// Durable disposition of one transactional incoming current-deletion apply.
///
/// The tombstone is the durable authority for both ordinary direct text and
/// strict ordinary direct media. It never depends on the target existing first
/// and never depends on best-effort artifact cleanup succeeding afterwards.
enum IncomingDirectDeletionOutcome {
  /// The tombstone was created for an absent target or replaced a live one.
  tombstoned,

  /// The exact same author tombstone was already durable.
  exactReplay,

  /// An already-durable deletion wins: an older or repeated event never
  /// replaces a newer tombstone.
  superseded,

  /// The event cannot authenticate against the stored target.
  unauthorized,

  /// The target is owned by another lane (private/outgoing/future policy).
  refused,
}

extension IncomingDirectDeletionOutcomePolicy on IncomingDirectDeletionOutcome {
  bool get isDurable => switch (this) {
    IncomingDirectDeletionOutcome.tombstoned ||
    IncomingDirectDeletionOutcome.exactReplay ||
    IncomingDirectDeletionOutcome.superseded => true,
    IncomingDirectDeletionOutcome.unauthorized ||
    IncomingDirectDeletionOutcome.refused => false,
  };

  bool get changed => this == IncomingDirectDeletionOutcome.tombstoned;
}

class DbIncomingDirectDeletionResult {
  const DbIncomingDirectDeletionResult({
    required this.outcome,
    required this.row,
  });

  final IncomingDirectDeletionOutcome outcome;
  final Map<String, Object?>? row;
}
