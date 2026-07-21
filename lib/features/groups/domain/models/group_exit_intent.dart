enum GroupExitIntentState {
  queued('queued'),
  leaveNoticePending('leave_notice_pending'),
  leaveNoticeAttempted('leave_notice_attempted'),
  rotationClaimed('rotation_claimed'),
  nativeLeavePending('native_leave_pending'),
  cleanupPending('cleanup_pending');

  const GroupExitIntentState(this.databaseValue);

  final String databaseValue;

  bool get isCancelable => this == GroupExitIntentState.queued;

  bool get hasLeaveNoticeIdentity => this != GroupExitIntentState.queued;

  bool get preventsRejoin =>
      index >= GroupExitIntentState.rotationClaimed.index;

  static GroupExitIntentState fromDatabase(String value) {
    for (final state in values) {
      if (state.databaseValue == value) return state;
    }
    throw FormatException('Unsupported group exit intent state: $value');
  }
}

class GroupExitIntent {
  const GroupExitIntent({
    required this.groupId,
    required this.intentId,
    required this.selfPeerId,
    required this.selfJoinedAt,
    required this.state,
    required this.pendingBroadcastId,
    this.sourceEventId,
    this.eventAt,
    this.revision = 0,
    this.lastErrorCode,
    required this.createdAt,
    required this.updatedAt,
  });

  final String groupId;
  final String intentId;
  final String selfPeerId;
  final DateTime selfJoinedAt;
  final GroupExitIntentState state;
  final String pendingBroadcastId;
  final String? sourceEventId;
  final DateTime? eventAt;
  final int revision;
  final String? lastErrorCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCancelable => state.isCancelable;

  bool get preventsRejoin => state.preventsRejoin;

  Map<String, Object?> toMap() => <String, Object?>{
    'group_id': groupId,
    'intent_id': intentId,
    'self_peer_id': selfPeerId,
    'self_joined_at': selfJoinedAt.toUtc().toIso8601String(),
    'state': state.databaseValue,
    'pending_broadcast_id': pendingBroadcastId,
    'source_event_id': sourceEventId,
    'event_at': eventAt?.toUtc().toIso8601String(),
    'revision': revision,
    'last_error_code': lastErrorCode,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory GroupExitIntent.fromMap(Map<String, Object?> map) {
    return GroupExitIntent(
      groupId: map['group_id'] as String,
      intentId: map['intent_id'] as String,
      selfPeerId: map['self_peer_id'] as String,
      selfJoinedAt: DateTime.parse(map['self_joined_at'] as String).toUtc(),
      state: GroupExitIntentState.fromDatabase(map['state'] as String),
      pendingBroadcastId: map['pending_broadcast_id'] as String,
      sourceEventId: map['source_event_id'] as String?,
      eventAt: map['event_at'] == null
          ? null
          : DateTime.parse(map['event_at'] as String).toUtc(),
      revision: (map['revision'] as num).toInt(),
      lastErrorCode: map['last_error_code'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }

  GroupExitIntent copyWith({
    String? groupId,
    String? intentId,
    String? selfPeerId,
    DateTime? selfJoinedAt,
    GroupExitIntentState? state,
    String? pendingBroadcastId,
    Object? sourceEventId = _unset,
    Object? eventAt = _unset,
    int? revision,
    Object? lastErrorCode = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GroupExitIntent(
      groupId: groupId ?? this.groupId,
      intentId: intentId ?? this.intentId,
      selfPeerId: selfPeerId ?? this.selfPeerId,
      selfJoinedAt: selfJoinedAt ?? this.selfJoinedAt,
      state: state ?? this.state,
      pendingBroadcastId: pendingBroadcastId ?? this.pendingBroadcastId,
      sourceEventId: sourceEventId == _unset
          ? this.sourceEventId
          : sourceEventId as String?,
      eventAt: eventAt == _unset ? this.eventAt : eventAt as DateTime?,
      revision: revision ?? this.revision,
      lastErrorCode: lastErrorCode == _unset
          ? this.lastErrorCode
          : lastErrorCode as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

bool sameExactGroupExitIntent(
  GroupExitIntent current,
  GroupExitIntent expected,
) =>
    current.groupId == expected.groupId &&
    current.intentId == expected.intentId &&
    current.selfPeerId == expected.selfPeerId &&
    current.selfJoinedAt.toUtc() == expected.selfJoinedAt.toUtc() &&
    current.state == expected.state &&
    current.pendingBroadcastId == expected.pendingBroadcastId &&
    current.sourceEventId == expected.sourceEventId &&
    current.eventAt?.toUtc() == expected.eventAt?.toUtc() &&
    current.revision == expected.revision &&
    current.lastErrorCode == expected.lastErrorCode &&
    current.createdAt.toUtc() == expected.createdAt.toUtc() &&
    current.updatedAt.toUtc() == expected.updatedAt.toUtc();

const Object _unset = Object();
