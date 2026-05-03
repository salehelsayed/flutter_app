class GroupWelcomeKeyPackageTombstone {
  final String packageId;
  final String recipientDeviceId;
  final String groupId;
  final String inviteId;
  final String publicMaterialHash;
  final DateTime consumedAt;
  final DateTime expiresAt;

  const GroupWelcomeKeyPackageTombstone({
    required this.packageId,
    required this.recipientDeviceId,
    required this.groupId,
    required this.inviteId,
    required this.publicMaterialHash,
    required this.consumedAt,
    required this.expiresAt,
  });

  factory GroupWelcomeKeyPackageTombstone.fromMap(Map<String, Object?> map) {
    return GroupWelcomeKeyPackageTombstone(
      packageId: map['package_id'] as String,
      recipientDeviceId: map['recipient_device_id'] as String,
      groupId: map['group_id'] as String,
      inviteId: map['invite_id'] as String,
      publicMaterialHash: map['public_material_hash'] as String,
      consumedAt: DateTime.parse(map['consumed_at'] as String).toUtc(),
      expiresAt: DateTime.parse(map['expires_at'] as String).toUtc(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'package_id': packageId,
      'recipient_device_id': recipientDeviceId,
      'group_id': groupId,
      'invite_id': inviteId,
      'public_material_hash': publicMaterialHash,
      'consumed_at': consumedAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
    };
  }

  GroupWelcomeKeyPackageTombstone copyWith({
    String? packageId,
    String? recipientDeviceId,
    String? groupId,
    String? inviteId,
    String? publicMaterialHash,
    DateTime? consumedAt,
    DateTime? expiresAt,
  }) {
    return GroupWelcomeKeyPackageTombstone(
      packageId: packageId ?? this.packageId,
      recipientDeviceId: recipientDeviceId ?? this.recipientDeviceId,
      groupId: groupId ?? this.groupId,
      inviteId: inviteId ?? this.inviteId,
      publicMaterialHash: publicMaterialHash ?? this.publicMaterialHash,
      consumedAt: consumedAt ?? this.consumedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  bool isActiveAt(DateTime now) => expiresAt.isAfter(now.toUtc());
}
