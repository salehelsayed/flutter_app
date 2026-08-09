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
