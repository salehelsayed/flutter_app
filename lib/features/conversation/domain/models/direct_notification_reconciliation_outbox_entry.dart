/// Identifier-only durable request to rebuild one direct conversation card.
class DirectNotificationReconciliationOutboxEntry {
  final String peerId;
  final String incarnationId;
  final int revision;
  final int retryCount;
  final String? lastAttemptAt;
  final String? nextAttemptAt;
  final String createdAt;
  final String updatedAt;

  const DirectNotificationReconciliationOutboxEntry({
    required this.peerId,
    required this.incarnationId,
    required this.revision,
    required this.retryCount,
    required this.lastAttemptAt,
    required this.nextAttemptAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DirectNotificationReconciliationOutboxEntry.fromMap(
    Map<String, Object?> map,
  ) => DirectNotificationReconciliationOutboxEntry(
    peerId: map['peer_id'] as String,
    incarnationId: map['incarnation_id'] as String,
    revision: (map['revision'] as num).toInt(),
    retryCount: (map['retry_count'] as num).toInt(),
    lastAttemptAt: map['last_attempt_at'] as String?,
    nextAttemptAt: map['next_attempt_at'] as String?,
    createdAt: map['created_at'] as String,
    updatedAt: map['updated_at'] as String,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'peer_id': peerId,
    'incarnation_id': incarnationId,
    'revision': revision,
    'retry_count': retryCount,
    'last_attempt_at': lastAttemptAt,
    'next_attempt_at': nextAttemptAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}
