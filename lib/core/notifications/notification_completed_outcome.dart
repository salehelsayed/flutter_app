enum NotificationCompletedOutcomeCategory {
  inChat('in_chat'),
  osPosted('os_posted'),
  suppressedPolicy('suppressed_policy');

  const NotificationCompletedOutcomeCategory(this.wireValue);

  final String wireValue;

  static NotificationCompletedOutcomeCategory? tryParse(String value) {
    for (final category in values) {
      if (category.wireValue == value) return category;
    }
    return null;
  }
}

enum NotificationCompletedOutcomeProducerKind {
  directMessage('direct_message', 0x01),
  directReaction('direct_reaction', 0x02),
  groupMessage('group_message', 0x03),
  groupReaction('group_reaction', 0x04);

  const NotificationCompletedOutcomeProducerKind(this.wireValue, this.kindByte);

  final String wireValue;
  final int kindByte;

  static NotificationCompletedOutcomeProducerKind? tryParse(String value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    return null;
  }
}

/// Immutable evidence offered by a canonical notification projection owner.
///
/// The database boundary validates the physical peer ID and exact authenticated
/// event key before deriving a correlation. Keeping the raw authority here is
/// intentional: callers must not side-map a bounded notification identifier
/// back to an outcome after the fact.
final class NotificationCompletedOutcomeCandidate {
  final String physicalPeerId;
  final NotificationCompletedOutcomeProducerKind producerKind;
  final String eventKey;
  final NotificationCompletedOutcomeCategory outcome;
  final DateTime completedAt;

  const NotificationCompletedOutcomeCandidate({
    required this.physicalPeerId,
    required this.producerKind,
    required this.eventKey,
    required this.outcome,
    required this.completedAt,
  });
}

/// Plan-language compatibility name used by projection dispositions.
typedef OutcomeCandidate = NotificationCompletedOutcomeCandidate;

/// One revisioned, installation-local completed-outcome delivery row.
final class NotificationCompletedOutcomeOutboxEntry {
  final String wakeCorrelation;
  final NotificationCompletedOutcomeCategory outcome;
  final int revision;
  final int retryCount;
  final String? lastErrorCode;
  final DateTime? lastAttemptAt;
  final DateTime? nextAttemptAt;
  final DateTime completedAt;
  final DateTime createdAt;
  final DateTime expiresAt;

  const NotificationCompletedOutcomeOutboxEntry({
    required this.wakeCorrelation,
    required this.outcome,
    required this.revision,
    required this.retryCount,
    required this.lastErrorCode,
    required this.lastAttemptAt,
    required this.nextAttemptAt,
    required this.completedAt,
    required this.createdAt,
    required this.expiresAt,
  });

  factory NotificationCompletedOutcomeOutboxEntry.fromMap(
    Map<String, Object?> map,
  ) {
    final outcome = NotificationCompletedOutcomeCategory.tryParse(
      map['outcome'] as String,
    );
    if (outcome == null) {
      throw StateError('unknown completed notification outcome category');
    }
    return NotificationCompletedOutcomeOutboxEntry(
      wakeCorrelation: map['wake_correlation'] as String,
      outcome: outcome,
      revision: (map['revision'] as num).toInt(),
      retryCount: (map['retry_count'] as num).toInt(),
      lastErrorCode: map['last_error_code'] as String?,
      lastAttemptAt: _parseNullableUtc(map['last_attempt_at']),
      nextAttemptAt: _parseNullableUtc(map['next_attempt_at']),
      completedAt: DateTime.parse(map['completed_at'] as String).toUtc(),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      expiresAt: DateTime.parse(map['expires_at'] as String).toUtc(),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'wake_correlation': wakeCorrelation,
    'outcome': outcome.wireValue,
    'revision': revision,
    'retry_count': retryCount,
    'last_error_code': lastErrorCode,
    'last_attempt_at': lastAttemptAt?.toUtc().toIso8601String(),
    'next_attempt_at': nextAttemptAt?.toUtc().toIso8601String(),
    'completed_at': completedAt.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };
}

DateTime? _parseNullableUtc(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toUtc();
