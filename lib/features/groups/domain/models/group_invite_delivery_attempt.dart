enum GroupInviteDeliveryStatus {
  sent,
  queued,
  needsResend,
  cannotSend,
  joined,
  revoked,
  declined,
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
      case GroupInviteDeliveryStatus.revoked:
        return 'revoked';
      case GroupInviteDeliveryStatus.declined:
        return 'declined';
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
      case 'revoked':
        return GroupInviteDeliveryStatus.revoked;
      case 'declined':
        return GroupInviteDeliveryStatus.declined;
      case 'unknown':
      case null:
        return GroupInviteDeliveryStatus.unknown;
      default:
        // Forward-compat: a status written by a newer build must not crash an
        // older reader (getAttemptsForGroup maps every row). Degrade to
        // unknown instead of throwing.
        return GroupInviteDeliveryStatus.unknown;
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

  /// The exact invite id sent to this peer. Persisted so a later revocation
  /// can carry the matching id (the receiver only deletes the live pending
  /// invite when `pending.inviteId == payload.inviteId`). Null for legacy rows.
  final String? inviteId;

  const GroupInviteDeliveryAttempt({
    required this.groupId,
    required this.peerId,
    this.username,
    required this.status,
    required this.attemptedAt,
    required this.updatedAt,
    this.lastError,
    this.inviteId,
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
      inviteId: map['invite_id'] as String?,
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
      'invite_id': inviteId,
    };
  }

  GroupInviteDeliveryAttempt copyWith({
    String? username,
    GroupInviteDeliveryStatus? status,
    DateTime? attemptedAt,
    DateTime? updatedAt,
    String? lastError,
    bool clearLastError = false,
    String? inviteId,
  }) {
    return GroupInviteDeliveryAttempt(
      groupId: groupId,
      peerId: peerId,
      username: username ?? this.username,
      status: status ?? this.status,
      attemptedAt: attemptedAt ?? this.attemptedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastError: clearLastError ? null : lastError ?? this.lastError,
      inviteId: inviteId ?? this.inviteId,
    );
  }
}
