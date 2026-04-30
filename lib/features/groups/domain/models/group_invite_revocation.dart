class GroupInviteRevocation {
  final String inviteId;
  final String groupId;
  final DateTime revokedAt;
  final DateTime expiresAt;
  final String? revokedBy;

  const GroupInviteRevocation({
    required this.inviteId,
    required this.groupId,
    required this.revokedAt,
    required this.expiresAt,
    this.revokedBy,
  });

  factory GroupInviteRevocation.fromMap(Map<String, dynamic> map) {
    return GroupInviteRevocation(
      inviteId: map['invite_id'] as String,
      groupId: map['group_id'] as String,
      revokedAt: DateTime.parse(map['revoked_at'] as String).toUtc(),
      expiresAt: DateTime.parse(map['expires_at'] as String).toUtc(),
      revokedBy: map['revoked_by'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'invite_id': inviteId,
      'group_id': groupId,
      'revoked_at': revokedAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'revoked_by': revokedBy,
    };
  }

  bool isActiveAt(DateTime now) => expiresAt.isAfter(now.toUtc());
}
