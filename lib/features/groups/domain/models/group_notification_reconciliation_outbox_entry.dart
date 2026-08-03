/// Identifier-only durable request to rebuild one group's notification card.
///
/// User-visible copy, message/reaction identifiers, and decrypted content are
/// deliberately absent. Projection must reload current canonical group state.
class GroupNotificationReconciliationOutboxEntry {
  final String groupId;
  final String incarnationId;
  final int revision;
  final int retryCount;
  final String? lastAttemptAt;
  final String? nextAttemptAt;
  final String createdAt;
  final String updatedAt;

  const GroupNotificationReconciliationOutboxEntry({
    required this.groupId,
    required this.incarnationId,
    required this.revision,
    required this.retryCount,
    required this.lastAttemptAt,
    required this.nextAttemptAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GroupNotificationReconciliationOutboxEntry.fromMap(
    Map<String, Object?> map,
  ) {
    return GroupNotificationReconciliationOutboxEntry(
      groupId: map['group_id'] as String,
      incarnationId: map['incarnation_id'] as String,
      revision: (map['revision'] as num).toInt(),
      retryCount: (map['retry_count'] as num).toInt(),
      lastAttemptAt: map['last_attempt_at'] as String?,
      nextAttemptAt: map['next_attempt_at'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'group_id': groupId,
    'incarnation_id': incarnationId,
    'revision': revision,
    'retry_count': retryCount,
    'last_attempt_at': lastAttemptAt,
    'next_attempt_at': nextAttemptAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  GroupNotificationReconciliationOutboxEntry copyWith({
    String? groupId,
    String? incarnationId,
    int? revision,
    int? retryCount,
    Object? lastAttemptAt = _unset,
    Object? nextAttemptAt = _unset,
    String? createdAt,
    String? updatedAt,
  }) {
    return GroupNotificationReconciliationOutboxEntry(
      groupId: groupId ?? this.groupId,
      incarnationId: incarnationId ?? this.incarnationId,
      revision: revision ?? this.revision,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: identical(lastAttemptAt, _unset)
          ? this.lastAttemptAt
          : lastAttemptAt as String?,
      nextAttemptAt: identical(nextAttemptAt, _unset)
          ? this.nextAttemptAt
          : nextAttemptAt as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const Object _unset = Object();
