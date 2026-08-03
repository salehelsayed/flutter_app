class GroupNotificationDisplayOutboxKind {
  static const String message = 'message';
  static const String reaction = 'reaction';
}

class GroupNotificationDisplayOutboxReadiness {
  static const String notReady = 'not_ready';
  static const String ready = 'ready';
}

class GroupNotificationDisplayOutboxErrorCode {
  static const String displayFailed = 'display_failed';
  static const String claimPending = 'claim_pending';
  static const String stateUnavailable = 'state_unavailable';
}

/// Identifier-only durable custody for one group notification transition.
///
/// Copy, target text, emoji, media paths and decrypted payloads are purposely
/// absent. A retrier must reload every user-visible value and policy decision
/// from current canonical state.
class GroupNotificationDisplayOutboxEntry {
  final String eventId;
  final String eventKind;
  final String groupId;
  final String messageId;
  final String actorPeerId;
  final String eventTimestamp;
  final String? reactionId;
  final String? reactionAction;
  final bool? reactionTombstone;
  final String readiness;
  final int revision;
  final int retryCount;
  final String? lastErrorCode;
  final String? lastAttemptAt;
  final String? nextAttemptAt;
  final String createdAt;
  final String updatedAt;

  const GroupNotificationDisplayOutboxEntry({
    required this.eventId,
    required this.eventKind,
    required this.groupId,
    required this.messageId,
    required this.actorPeerId,
    required this.eventTimestamp,
    this.reactionId,
    this.reactionAction,
    this.reactionTombstone,
    this.readiness = GroupNotificationDisplayOutboxReadiness.notReady,
    this.revision = 1,
    this.retryCount = 0,
    this.lastErrorCode,
    this.lastAttemptAt,
    this.nextAttemptAt,
    required this.createdAt,
    required this.updatedAt,
  });

  const GroupNotificationDisplayOutboxEntry.message({
    required String eventId,
    required String groupId,
    required String messageId,
    required String actorPeerId,
    required String eventTimestamp,
    String readiness = GroupNotificationDisplayOutboxReadiness.notReady,
    int revision = 1,
    int retryCount = 0,
    String? lastErrorCode,
    String? lastAttemptAt,
    String? nextAttemptAt,
    required String createdAt,
    required String updatedAt,
  }) : this(
         eventId: eventId,
         eventKind: GroupNotificationDisplayOutboxKind.message,
         groupId: groupId,
         messageId: messageId,
         actorPeerId: actorPeerId,
         eventTimestamp: eventTimestamp,
         readiness: readiness,
         revision: revision,
         retryCount: retryCount,
         lastErrorCode: lastErrorCode,
         lastAttemptAt: lastAttemptAt,
         nextAttemptAt: nextAttemptAt,
         createdAt: createdAt,
         updatedAt: updatedAt,
       );

  const GroupNotificationDisplayOutboxEntry.reaction({
    required String eventId,
    required String groupId,
    required String messageId,
    required String actorPeerId,
    required String eventTimestamp,
    required String reactionId,
    required String reactionAction,
    required bool reactionTombstone,
    String readiness = GroupNotificationDisplayOutboxReadiness.notReady,
    int revision = 1,
    int retryCount = 0,
    String? lastErrorCode,
    String? lastAttemptAt,
    String? nextAttemptAt,
    required String createdAt,
    required String updatedAt,
  }) : this(
         eventId: eventId,
         eventKind: GroupNotificationDisplayOutboxKind.reaction,
         groupId: groupId,
         messageId: messageId,
         actorPeerId: actorPeerId,
         eventTimestamp: eventTimestamp,
         reactionId: reactionId,
         reactionAction: reactionAction,
         reactionTombstone: reactionTombstone,
         readiness: readiness,
         revision: revision,
         retryCount: retryCount,
         lastErrorCode: lastErrorCode,
         lastAttemptAt: lastAttemptAt,
         nextAttemptAt: nextAttemptAt,
         createdAt: createdAt,
         updatedAt: updatedAt,
       );

  factory GroupNotificationDisplayOutboxEntry.fromMap(
    Map<String, Object?> map,
  ) {
    return GroupNotificationDisplayOutboxEntry(
      eventId: map['event_id'] as String,
      eventKind: map['event_kind'] as String,
      groupId: map['group_id'] as String,
      messageId: map['message_id'] as String,
      actorPeerId: map['actor_peer_id'] as String,
      eventTimestamp: map['event_timestamp'] as String,
      reactionId: map['reaction_id'] as String?,
      reactionAction: map['reaction_action'] as String?,
      reactionTombstone: switch (map['reaction_tombstone']) {
        0 => false,
        1 => true,
        _ => null,
      },
      readiness: map['readiness'] as String,
      revision: (map['revision'] as num).toInt(),
      retryCount: (map['retry_count'] as num).toInt(),
      lastErrorCode: map['last_error_code'] as String?,
      lastAttemptAt: map['last_attempt_at'] as String?,
      nextAttemptAt: map['next_attempt_at'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  bool get isReady =>
      readiness == GroupNotificationDisplayOutboxReadiness.ready;

  Map<String, Object?> toMap() => <String, Object?>{
    'event_id': eventId,
    'event_kind': eventKind,
    'group_id': groupId,
    'message_id': messageId,
    'actor_peer_id': actorPeerId,
    'event_timestamp': eventTimestamp,
    'reaction_id': reactionId,
    'reaction_action': reactionAction,
    'reaction_tombstone': reactionTombstone == null
        ? null
        : (reactionTombstone! ? 1 : 0),
    'readiness': readiness,
    'revision': revision,
    'retry_count': retryCount,
    'last_error_code': lastErrorCode,
    'last_attempt_at': lastAttemptAt,
    'next_attempt_at': nextAttemptAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  GroupNotificationDisplayOutboxEntry copyWith({
    String? eventId,
    String? eventKind,
    String? groupId,
    String? messageId,
    String? actorPeerId,
    String? eventTimestamp,
    Object? reactionId = _unset,
    Object? reactionAction = _unset,
    Object? reactionTombstone = _unset,
    String? readiness,
    int? revision,
    int? retryCount,
    Object? lastErrorCode = _unset,
    Object? lastAttemptAt = _unset,
    Object? nextAttemptAt = _unset,
    String? createdAt,
    String? updatedAt,
  }) {
    return GroupNotificationDisplayOutboxEntry(
      eventId: eventId ?? this.eventId,
      eventKind: eventKind ?? this.eventKind,
      groupId: groupId ?? this.groupId,
      messageId: messageId ?? this.messageId,
      actorPeerId: actorPeerId ?? this.actorPeerId,
      eventTimestamp: eventTimestamp ?? this.eventTimestamp,
      reactionId: identical(reactionId, _unset)
          ? this.reactionId
          : reactionId as String?,
      reactionAction: identical(reactionAction, _unset)
          ? this.reactionAction
          : reactionAction as String?,
      reactionTombstone: identical(reactionTombstone, _unset)
          ? this.reactionTombstone
          : reactionTombstone as bool?,
      readiness: readiness ?? this.readiness,
      revision: revision ?? this.revision,
      retryCount: retryCount ?? this.retryCount,
      lastErrorCode: identical(lastErrorCode, _unset)
          ? this.lastErrorCode
          : lastErrorCode as String?,
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
