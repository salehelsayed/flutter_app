enum PushRegistrationHealthPhase {
  checking,
  healthy,
  retrying,
  permissionDenied,
}

enum PushRegistrationHealthReason {
  none,
  permissionDenied,
  noToken,
  registrationFailed,
  exception,
}

extension PushRegistrationHealthReasonX on PushRegistrationHealthReason {
  bool get isTransient => switch (this) {
    PushRegistrationHealthReason.noToken ||
    PushRegistrationHealthReason.registrationFailed ||
    PushRegistrationHealthReason.exception => true,
    PushRegistrationHealthReason.none ||
    PushRegistrationHealthReason.permissionDenied => false,
  };
}

final class PushRegistrationHealthRecord {
  PushRegistrationHealthRecord({
    required this.phase,
    required this.reason,
    required this.consecutiveFailures,
    required DateTime? firstFailureAt,
    required DateTime lastAttemptAt,
    required DateTime? lastSuccessAt,
  }) : firstFailureAt = firstFailureAt?.toUtc(),
       lastAttemptAt = lastAttemptAt.toUtc(),
       lastSuccessAt = lastSuccessAt?.toUtc() {
    if (consecutiveFailures < 0) {
      throw ArgumentError.value(
        consecutiveFailures,
        'consecutiveFailures',
        'must not be negative',
      );
    }
  }

  factory PushRegistrationHealthRecord.checking({
    required DateTime at,
    PushRegistrationHealthRecord? previous,
  }) {
    return PushRegistrationHealthRecord(
      phase: PushRegistrationHealthPhase.checking,
      reason: previous?.reason ?? PushRegistrationHealthReason.none,
      consecutiveFailures: previous?.consecutiveFailures ?? 0,
      firstFailureAt: previous?.firstFailureAt,
      lastAttemptAt: at,
      lastSuccessAt: previous?.lastSuccessAt,
    );
  }

  factory PushRegistrationHealthRecord.healthy({required DateTime at}) {
    return PushRegistrationHealthRecord(
      phase: PushRegistrationHealthPhase.healthy,
      reason: PushRegistrationHealthReason.none,
      consecutiveFailures: 0,
      firstFailureAt: null,
      lastAttemptAt: at,
      lastSuccessAt: at,
    );
  }

  factory PushRegistrationHealthRecord.permissionDenied({
    required DateTime at,
    DateTime? lastSuccessAt,
  }) {
    return PushRegistrationHealthRecord(
      phase: PushRegistrationHealthPhase.permissionDenied,
      reason: PushRegistrationHealthReason.permissionDenied,
      consecutiveFailures: 0,
      firstFailureAt: at,
      lastAttemptAt: at,
      lastSuccessAt: lastSuccessAt,
    );
  }

  factory PushRegistrationHealthRecord.retrying({
    required PushRegistrationHealthReason reason,
    required int consecutiveFailures,
    required DateTime firstFailureAt,
    required DateTime lastAttemptAt,
    DateTime? lastSuccessAt,
  }) {
    if (!reason.isTransient) {
      throw ArgumentError.value(reason, 'reason', 'must be transient');
    }
    if (consecutiveFailures <= 0) {
      throw ArgumentError.value(
        consecutiveFailures,
        'consecutiveFailures',
        'must be positive for a retrying record',
      );
    }
    return PushRegistrationHealthRecord(
      phase: PushRegistrationHealthPhase.retrying,
      reason: reason,
      consecutiveFailures: consecutiveFailures,
      firstFailureAt: firstFailureAt,
      lastAttemptAt: lastAttemptAt,
      lastSuccessAt: lastSuccessAt,
    );
  }

  final PushRegistrationHealthPhase phase;
  final PushRegistrationHealthReason reason;
  final int consecutiveFailures;
  final DateTime? firstFailureAt;
  final DateTime lastAttemptAt;
  final DateTime? lastSuccessAt;

  DateTime? get transientWarningSince {
    if (!reason.isTransient) return null;
    return lastSuccessAt ?? firstFailureAt;
  }

  bool warningVisibleAt(
    DateTime now, {
    int failureThreshold = 3,
    Duration warningAfter = const Duration(hours: 24),
  }) {
    if (reason == PushRegistrationHealthReason.permissionDenied &&
        (phase == PushRegistrationHealthPhase.permissionDenied ||
            phase == PushRegistrationHealthPhase.checking)) {
      return true;
    }
    if (!reason.isTransient ||
        (phase != PushRegistrationHealthPhase.retrying &&
            phase != PushRegistrationHealthPhase.checking)) {
      return false;
    }
    if (consecutiveFailures >= failureThreshold) return true;
    final warningSince = transientWarningSince;
    return warningSince != null &&
        !now.toUtc().isBefore(warningSince.add(warningAfter));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PushRegistrationHealthRecord &&
            other.phase == phase &&
            other.reason == reason &&
            other.consecutiveFailures == consecutiveFailures &&
            other.firstFailureAt == firstFailureAt &&
            other.lastAttemptAt == lastAttemptAt &&
            other.lastSuccessAt == lastSuccessAt;
  }

  @override
  int get hashCode => Object.hash(
    phase,
    reason,
    consecutiveFailures,
    firstFailureAt,
    lastAttemptAt,
    lastSuccessAt,
  );
}
