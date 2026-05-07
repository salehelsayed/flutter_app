enum GroupInviteDeliveryStatus {
  sent,
  queued,
  needsResend,
  cannotSend,
  joined,
  unknown;

  String toValue() {
    switch (this) {
      case GroupInviteDeliveryStatus.sent:
        return 'sent';
      case GroupInviteDeliveryStatus.queued:
        return 'queued';
      case GroupInviteDeliveryStatus.needsResend:
        return 'needs_resend';
      case GroupInviteDeliveryStatus.cannotSend:
        return 'cannot_send';
      case GroupInviteDeliveryStatus.joined:
        return 'joined';
      case GroupInviteDeliveryStatus.unknown:
        return 'unknown';
    }
  }

  static GroupInviteDeliveryStatus fromValue(String? value) {
    switch (value) {
      case 'sent':
        return GroupInviteDeliveryStatus.sent;
      case 'queued':
        return GroupInviteDeliveryStatus.queued;
      case 'needs_resend':
        return GroupInviteDeliveryStatus.needsResend;
      case 'cannot_send':
        return GroupInviteDeliveryStatus.cannotSend;
      case 'joined':
        return GroupInviteDeliveryStatus.joined;
      case 'unknown':
      case null:
        return GroupInviteDeliveryStatus.unknown;
      default:
        throw ArgumentError('Unknown GroupInviteDeliveryStatus: $value');
    }
  }
}

class GroupInviteDeliveryAttempt {
  final String groupId;
  final String peerId;
  final String? username;
  final GroupInviteDeliveryStatus status;
  final DateTime attemptedAt;
  final DateTime updatedAt;
  final String? lastError;

  const GroupInviteDeliveryAttempt({
    required this.groupId,
    required this.peerId,
    this.username,
    required this.status,
    required this.attemptedAt,
    required this.updatedAt,
    this.lastError,
  });

  factory GroupInviteDeliveryAttempt.fromMap(Map<String, Object?> map) {
    return GroupInviteDeliveryAttempt(
      groupId: map['group_id'] as String,
      peerId: map['peer_id'] as String,
      username: map['username'] as String?,
      status: GroupInviteDeliveryStatus.fromValue(map['status'] as String?),
      attemptedAt: DateTime.parse(map['attempted_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      lastError: map['last_error'] as String?,
    );
  }

  factory GroupInviteDeliveryAttempt.unknown({
    required String groupId,
    required String peerId,
    String? username,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return GroupInviteDeliveryAttempt(
      groupId: groupId,
      peerId: peerId,
      username: username,
      status: GroupInviteDeliveryStatus.unknown,
      attemptedAt: timestamp,
      updatedAt: timestamp,
    );
  }

  Map<String, Object?> toMap() {
    if (status == GroupInviteDeliveryStatus.unknown) {
      throw StateError('Unknown invite delivery status is not persisted');
    }
    return {
      'group_id': groupId,
      'peer_id': peerId,
      'username': username,
      'status': status.toValue(),
      'attempted_at': attemptedAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'last_error': lastError,
    };
  }

  GroupInviteDeliveryAttempt copyWith({
    String? username,
    GroupInviteDeliveryStatus? status,
    DateTime? attemptedAt,
    DateTime? updatedAt,
    String? lastError,
    bool clearLastError = false,
  }) {
    return GroupInviteDeliveryAttempt(
      groupId: groupId,
      peerId: peerId,
      username: username ?? this.username,
      status: status ?? this.status,
      attemptedAt: attemptedAt ?? this.attemptedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }
}
