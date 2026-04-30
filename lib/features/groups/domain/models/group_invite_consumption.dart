class GroupInviteConsumption {
  final String inviteId;
  final String groupId;
  final DateTime consumedAt;
  final DateTime expiresAt;

  const GroupInviteConsumption({
    required this.inviteId,
    required this.groupId,
    required this.consumedAt,
    required this.expiresAt,
  });

  factory GroupInviteConsumption.fromMap(Map<String, dynamic> map) {
    return GroupInviteConsumption(
      inviteId: map['invite_id'] as String,
      groupId: map['group_id'] as String,
      consumedAt: DateTime.parse(map['consumed_at'] as String).toUtc(),
      expiresAt: DateTime.parse(map['expires_at'] as String).toUtc(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'invite_id': inviteId,
      'group_id': groupId,
      'consumed_at': consumedAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
    };
  }

  bool isActiveAt(DateTime now) => expiresAt.isAfter(now.toUtc());
}
