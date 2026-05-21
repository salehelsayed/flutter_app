import 'dart:convert';

/// Enum representing a member's role within a group.
enum MemberRole {
  admin,
  writer,
  reader;

  /// Converts to a database/wire string value.
  String toValue() => name;

  /// Parses from a database/wire string value.
  static MemberRole fromValue(String value) {
    switch (value) {
      case 'admin':
        return MemberRole.admin;
      case 'writer':
        return MemberRole.writer;
      case 'reader':
        return MemberRole.reader;
      default:
        throw ArgumentError('Unknown MemberRole: $value');
    }
  }
}

enum GroupMemberPermission {
  inviteMembers,
  removeMembers,
  manageRoles,
  rotateKeys,
  editMetadata,
  pinMessages,
  deleteMessages;

  String get wireName {
    switch (this) {
      case GroupMemberPermission.inviteMembers:
        return 'inviteMembers';
      case GroupMemberPermission.removeMembers:
        return 'removeMembers';
      case GroupMemberPermission.manageRoles:
        return 'manageRoles';
      case GroupMemberPermission.rotateKeys:
        return 'rotateKeys';
      case GroupMemberPermission.editMetadata:
        return 'editMetadata';
      case GroupMemberPermission.pinMessages:
        return 'pinMessages';
      case GroupMemberPermission.deleteMessages:
        return 'deleteMessages';
    }
  }
}

enum GroupMemberDeviceStatus {
  active,
  revoked;

  String toValue() => name;

  static GroupMemberDeviceStatus fromValue(String? value) {
    switch (value) {
      case 'active':
        return GroupMemberDeviceStatus.active;
      case 'revoked':
        return GroupMemberDeviceStatus.revoked;
      default:
        return GroupMemberDeviceStatus.active;
    }
  }
}

/// First-class identity for one registered device under a group member.
///
/// [GroupMember.peerId] remains the account/member identity. Device identities
/// bind transport Peer ID, signing key, and key-package material for send,
/// replay, and admission checks.
class GroupMemberDeviceIdentity {
  final String deviceId;
  final String transportPeerId;
  final String deviceSigningPublicKey;
  final String? mlKemPublicKey;
  final String? keyPackageId;
  final String? keyPackagePublicMaterial;
  final GroupMemberDeviceStatus status;
  final DateTime? revokedAt;

  const GroupMemberDeviceIdentity({
    required this.deviceId,
    required this.transportPeerId,
    required this.deviceSigningPublicKey,
    this.mlKemPublicKey,
    this.keyPackageId,
    this.keyPackagePublicMaterial,
    this.status = GroupMemberDeviceStatus.active,
    this.revokedAt,
  });

  bool get isActive =>
      status == GroupMemberDeviceStatus.active && revokedAt == null;

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'transportPeerId': transportPeerId,
      'deviceSigningPublicKey': deviceSigningPublicKey,
      if (mlKemPublicKey != null && mlKemPublicKey!.isNotEmpty)
        'mlKemPublicKey': mlKemPublicKey,
      if (keyPackageId != null && keyPackageId!.isNotEmpty)
        'keyPackageId': keyPackageId,
      if (keyPackagePublicMaterial != null &&
          keyPackagePublicMaterial!.isNotEmpty)
        'keyPackagePublicMaterial': keyPackagePublicMaterial,
      'status': status.toValue(),
      if (revokedAt != null) 'revokedAt': revokedAt!.toUtc().toIso8601String(),
    };
  }

  static GroupMemberDeviceIdentity? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final deviceId = _readString(value, 'deviceId');
    final transportPeerId =
        _readString(value, 'transportPeerId') ??
        _readString(value, 'transportPeerID') ??
        _readString(value, 'peerId');
    final signingPublicKey =
        _readString(value, 'deviceSigningPublicKey') ??
        _readString(value, 'signingPublicKey') ??
        _readString(value, 'devicePublicKey') ??
        _readString(value, 'publicKey');
    if (deviceId == null ||
        deviceId.isEmpty ||
        transportPeerId == null ||
        transportPeerId.isEmpty ||
        signingPublicKey == null ||
        signingPublicKey.isEmpty) {
      return null;
    }

    return GroupMemberDeviceIdentity(
      deviceId: deviceId,
      transportPeerId: transportPeerId,
      deviceSigningPublicKey: signingPublicKey,
      mlKemPublicKey: _readString(value, 'mlKemPublicKey'),
      keyPackageId:
          _readString(value, 'keyPackageId') ??
          _readString(value, 'keyPackageHash'),
      keyPackagePublicMaterial:
          _readString(value, 'keyPackagePublicMaterial') ??
          _readString(value, 'keyPackagePublicKey'),
      status: GroupMemberDeviceStatus.fromValue(_readString(value, 'status')),
      revokedAt: _parseOptionalDateTime(_readString(value, 'revokedAt')),
    );
  }

  static List<GroupMemberDeviceIdentity> listFromJson(Object? value) {
    if (value is! List) {
      return const <GroupMemberDeviceIdentity>[];
    }
    return value
        .map(GroupMemberDeviceIdentity.fromJson)
        .whereType<GroupMemberDeviceIdentity>()
        .toList(growable: false);
  }

  static List<GroupMemberDeviceIdentity> listFromJsonString(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const <GroupMemberDeviceIdentity>[];
    }
    try {
      return listFromJson(jsonDecode(value));
    } catch (_) {
      return const <GroupMemberDeviceIdentity>[];
    }
  }

  static String? listToJsonString(List<GroupMemberDeviceIdentity> devices) {
    if (devices.isEmpty) {
      return null;
    }
    return jsonEncode(devices.map((device) => device.toJson()).toList());
  }

  GroupMemberDeviceIdentity copyWith({
    String? deviceId,
    String? transportPeerId,
    String? deviceSigningPublicKey,
    String? mlKemPublicKey,
    String? keyPackageId,
    String? keyPackagePublicMaterial,
    GroupMemberDeviceStatus? status,
    DateTime? revokedAt,
    bool clearRevokedAt = false,
  }) {
    return GroupMemberDeviceIdentity(
      deviceId: deviceId ?? this.deviceId,
      transportPeerId: transportPeerId ?? this.transportPeerId,
      deviceSigningPublicKey:
          deviceSigningPublicKey ?? this.deviceSigningPublicKey,
      mlKemPublicKey: mlKemPublicKey ?? this.mlKemPublicKey,
      keyPackageId: keyPackageId ?? this.keyPackageId,
      keyPackagePublicMaterial:
          keyPackagePublicMaterial ?? this.keyPackagePublicMaterial,
      status: status ?? this.status,
      revokedAt: clearRevokedAt ? null : revokedAt ?? this.revokedAt,
    );
  }

  static String? _readString(Map<dynamic, dynamic> value, String key) {
    final raw = value[key];
    if (raw is! String) {
      return null;
    }
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _parseOptionalDateTime(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }
}

class GroupMemberPermissions {
  final bool? inviteMembers;
  final bool? removeMembers;
  final bool? manageRoles;
  final bool? rotateKeys;
  final bool? editMetadata;
  final bool? pinMessages;
  final bool? deleteMessages;

  const GroupMemberPermissions({
    this.inviteMembers,
    this.removeMembers,
    this.manageRoles,
    this.rotateKeys,
    this.editMetadata,
    this.pinMessages,
    this.deleteMessages,
  });

  static const empty = GroupMemberPermissions();

  bool get hasOverrides =>
      inviteMembers != null ||
      removeMembers != null ||
      manageRoles != null ||
      rotateKeys != null ||
      editMetadata != null ||
      pinMessages != null ||
      deleteMessages != null;

  bool allows(GroupMemberPermission permission, MemberRole role) {
    final override = switch (permission) {
      GroupMemberPermission.inviteMembers => inviteMembers,
      GroupMemberPermission.removeMembers => removeMembers,
      GroupMemberPermission.manageRoles => manageRoles,
      GroupMemberPermission.rotateKeys => rotateKeys,
      GroupMemberPermission.editMetadata => editMetadata,
      GroupMemberPermission.pinMessages => pinMessages,
      GroupMemberPermission.deleteMessages => deleteMessages,
    };
    return override ?? _defaultForRole(permission, role);
  }

  Map<String, dynamic> toJson() {
    return {
      if (inviteMembers != null)
        GroupMemberPermission.inviteMembers.wireName: inviteMembers,
      if (removeMembers != null)
        GroupMemberPermission.removeMembers.wireName: removeMembers,
      if (manageRoles != null)
        GroupMemberPermission.manageRoles.wireName: manageRoles,
      if (rotateKeys != null)
        GroupMemberPermission.rotateKeys.wireName: rotateKeys,
      if (editMetadata != null)
        GroupMemberPermission.editMetadata.wireName: editMetadata,
      if (pinMessages != null)
        GroupMemberPermission.pinMessages.wireName: pinMessages,
      if (deleteMessages != null)
        GroupMemberPermission.deleteMessages.wireName: deleteMessages,
    };
  }

  String? toJsonString() => hasOverrides ? jsonEncode(toJson()) : null;

  static GroupMemberPermissions fromJsonString(String? value) {
    if (value == null || value.trim().isEmpty) {
      return empty;
    }
    try {
      final decoded = jsonDecode(value);
      return fromJson(decoded);
    } catch (_) {
      return empty;
    }
  }

  static GroupMemberPermissions fromJson(Object? value) {
    if (value is! Map) {
      return empty;
    }
    bool? readBool(GroupMemberPermission permission) {
      final raw = value[permission.wireName];
      return raw is bool ? raw : null;
    }

    return GroupMemberPermissions(
      inviteMembers: readBool(GroupMemberPermission.inviteMembers),
      removeMembers: readBool(GroupMemberPermission.removeMembers),
      manageRoles: readBool(GroupMemberPermission.manageRoles),
      rotateKeys: readBool(GroupMemberPermission.rotateKeys),
      editMetadata: readBool(GroupMemberPermission.editMetadata),
      pinMessages: readBool(GroupMemberPermission.pinMessages),
      deleteMessages: readBool(GroupMemberPermission.deleteMessages),
    );
  }

  static bool _defaultForRole(
    GroupMemberPermission permission,
    MemberRole role,
  ) {
    switch (permission) {
      case GroupMemberPermission.inviteMembers:
      case GroupMemberPermission.removeMembers:
      case GroupMemberPermission.manageRoles:
      case GroupMemberPermission.rotateKeys:
      case GroupMemberPermission.editMetadata:
      case GroupMemberPermission.pinMessages:
      case GroupMemberPermission.deleteMessages:
        return role == MemberRole.admin;
    }
  }
}

/// Model representing a member of a group.
///
/// Maps to the `group_members` database table.
class GroupMember {
  /// The group this member belongs to.
  final String groupId;

  /// The peer ID of the member.
  final String peerId;

  /// The display name of the member.
  final String? username;

  /// The member's role in the group.
  final MemberRole role;

  /// Explicit permission overrides. Missing flags fall back to [role].
  final GroupMemberPermissions permissions;

  /// Base64-encoded Ed25519 public key of the member.
  final String? publicKey;

  /// Base64-encoded ML-KEM-768 public key of the member.
  final String? mlKemPublicKey;

  /// First-class registered devices for this member.
  final List<GroupMemberDeviceIdentity> devices;

  /// When this member joined the group.
  final DateTime joinedAt;

  const GroupMember({
    required this.groupId,
    required this.peerId,
    this.username,
    required this.role,
    this.permissions = GroupMemberPermissions.empty,
    this.publicKey,
    this.mlKemPublicKey,
    this.devices = const <GroupMemberDeviceIdentity>[],
    required this.joinedAt,
  });

  List<GroupMemberDeviceIdentity> get activeDevices =>
      devices.where((device) => device.isActive).toList(growable: false);

  GroupMemberDeviceIdentity? get legacyDeviceIdentity {
    final publicKey = this.publicKey?.trim();
    final mlKemKey = mlKemPublicKey?.trim();
    if ((publicKey == null || publicKey.isEmpty) &&
        (mlKemKey == null || mlKemKey.isEmpty)) {
      return null;
    }
    return GroupMemberDeviceIdentity(
      deviceId: peerId,
      transportPeerId: peerId,
      deviceSigningPublicKey: publicKey ?? '',
      mlKemPublicKey: mlKemKey,
      keyPackagePublicMaterial: mlKemKey,
    );
  }

  List<GroupMemberDeviceIdentity> activeDevicesWithLegacyFallback() {
    final active = activeDevices;
    if (active.isNotEmpty) {
      return active;
    }
    final legacy = legacyDeviceIdentity;
    return legacy == null
        ? const <GroupMemberDeviceIdentity>[]
        : <GroupMemberDeviceIdentity>[legacy];
  }

  GroupMemberDeviceIdentity? findDeviceById(
    String? deviceId, {
    bool activeOnly = true,
    bool allowLegacyFallback = false,
  }) {
    final normalized = deviceId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final device in devices) {
      if (device.deviceId == normalized && (!activeOnly || device.isActive)) {
        return device;
      }
    }
    if (allowLegacyFallback) {
      final legacy = legacyDeviceIdentity;
      if (legacy != null && legacy.deviceId == normalized) {
        return legacy;
      }
    }
    return null;
  }

  GroupMemberDeviceIdentity? findDeviceByTransportPeerId(
    String? transportPeerId, {
    bool activeOnly = true,
    bool allowLegacyFallback = false,
  }) {
    final normalized = transportPeerId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final device in devices) {
      if (device.transportPeerId == normalized &&
          (!activeOnly || device.isActive)) {
        return device;
      }
    }
    if (allowLegacyFallback) {
      final legacy = legacyDeviceIdentity;
      if (legacy != null && legacy.transportPeerId == normalized) {
        return legacy;
      }
    }
    return null;
  }

  GroupMemberDeviceIdentity? firstActiveDeviceForSigningKey(
    String? signingPublicKey, {
    bool allowLegacyFallback = false,
  }) {
    final normalized = signingPublicKey?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final device in activeDevices) {
      if (device.deviceSigningPublicKey == normalized) {
        return device;
      }
    }
    if (allowLegacyFallback) {
      final legacy = legacyDeviceIdentity;
      if (legacy?.deviceSigningPublicKey == normalized) {
        return legacy;
      }
    }
    return null;
  }

  /// Creates a GroupMember from a database row map.
  factory GroupMember.fromMap(Map<String, dynamic> map) {
    return GroupMember(
      groupId: map['group_id'] as String,
      peerId: map['peer_id'] as String,
      username: map['username'] as String?,
      role: MemberRole.fromValue(map['role'] as String),
      permissions: GroupMemberPermissions.fromJsonString(
        map['permissions_json'] as String?,
      ),
      publicKey: map['public_key'] as String?,
      mlKemPublicKey: map['ml_kem_public_key'] as String?,
      devices: GroupMemberDeviceIdentity.listFromJsonString(
        map['devices_json'] as String?,
      ),
      joinedAt: DateTime.parse(map['joined_at'] as String),
    );
  }

  factory GroupMember.fromConfigMap({
    required String groupId,
    required Map<String, dynamic> map,
    GroupMember? existing,
    DateTime? joinedAt,
    bool preserveMissingPermissions = true,
  }) {
    final peerId = map['peerId'] as String? ?? existing?.peerId ?? '';
    final configJoinedAt = DateTime.tryParse(
      map['joinedAt'] as String? ?? '',
    )?.toUtc();
    return GroupMember(
      groupId: groupId,
      peerId: peerId,
      username: map['username'] as String? ?? existing?.username,
      role: MemberRole.fromValue(map['role'] as String? ?? 'writer'),
      permissions: map.containsKey('permissions')
          ? GroupMemberPermissions.fromJson(map['permissions'])
          : preserveMissingPermissions
          ? existing?.permissions ?? GroupMemberPermissions.empty
          : GroupMemberPermissions.empty,
      publicKey: map['publicKey'] as String? ?? existing?.publicKey,
      mlKemPublicKey:
          map['mlKemPublicKey'] as String? ?? existing?.mlKemPublicKey,
      devices: map.containsKey('devices')
          ? GroupMemberDeviceIdentity.listFromJson(map['devices'])
          : existing?.devices ?? const <GroupMemberDeviceIdentity>[],
      joinedAt:
          existing?.joinedAt ??
          configJoinedAt ??
          joinedAt ??
          DateTime.now().toUtc(),
    );
  }

  /// Converts the model to a database row map.
  Map<String, dynamic> toMap() {
    return {
      'group_id': groupId,
      'peer_id': peerId,
      'username': username,
      'role': role.toValue(),
      'permissions_json': permissions.toJsonString(),
      'public_key': publicKey,
      'ml_kem_public_key': mlKemPublicKey,
      'devices_json': GroupMemberDeviceIdentity.listToJsonString(devices),
      'joined_at': joinedAt.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toConfigJson() {
    return {
      'peerId': peerId,
      'username': username,
      'role': role.toValue(),
      'joinedAt': joinedAt.toUtc().toIso8601String(),
      if (permissions.hasOverrides) 'permissions': permissions.toJson(),
      'publicKey': publicKey,
      if (mlKemPublicKey != null) 'mlKemPublicKey': mlKemPublicKey,
      if (devices.isNotEmpty)
        'devices': devices.map((device) => device.toJson()).toList(),
    };
  }

  GroupMember copyWith({
    String? groupId,
    String? peerId,
    String? username,
    MemberRole? role,
    GroupMemberPermissions? permissions,
    String? publicKey,
    String? mlKemPublicKey,
    List<GroupMemberDeviceIdentity>? devices,
    DateTime? joinedAt,
  }) {
    return GroupMember(
      groupId: groupId ?? this.groupId,
      peerId: peerId ?? this.peerId,
      username: username ?? this.username,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
      publicKey: publicKey ?? this.publicKey,
      mlKemPublicKey: mlKemPublicKey ?? this.mlKemPublicKey,
      devices: devices ?? this.devices,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroupMember &&
        other.groupId == groupId &&
        other.peerId == peerId;
  }

  @override
  int get hashCode => Object.hash(groupId, peerId);

  @override
  String toString() {
    return 'GroupMember(groupId: $groupId, peerId: $peerId, role: ${role.toValue()})';
  }
}

String? groupMemberKeyMaterialRejectReason(GroupMember member) {
  return groupMemberConfigKeyMaterialRejectReason(member.toConfigJson());
}

String? groupConfigMemberKeyMaterialRejectReason(
  Map<dynamic, dynamic> groupConfig,
) {
  final members = groupConfig['members'];
  if (members == null) {
    return null;
  }
  if (members is! List) {
    return 'invalid_members';
  }
  for (final rawMember in members) {
    if (rawMember is! Map) {
      return 'invalid_member';
    }
    final reason = groupMemberConfigKeyMaterialRejectReason(rawMember);
    if (reason != null) {
      final peerId = rawMember['peerId'];
      return peerId is String && peerId.trim().isNotEmpty
          ? '$reason:${peerId.trim()}'
          : reason;
    }
  }
  return null;
}

String? groupMemberConfigKeyMaterialRejectReason(Map<dynamic, dynamic> member) {
  return _optionalKeyMaterialRejectReason(
        member,
        'publicKey',
        'invalid_public_key',
      ) ??
      _optionalKeyMaterialRejectReason(
        member,
        'mlKemPublicKey',
        'invalid_ml_kem_public_key',
      ) ??
      _deviceKeyMaterialRejectReason(member['devices']);
}

String? _deviceKeyMaterialRejectReason(Object? rawDevices) {
  if (rawDevices == null) {
    return null;
  }
  if (rawDevices is! List) {
    return 'invalid_devices';
  }
  for (final rawDevice in rawDevices) {
    if (rawDevice is! Map) {
      return 'invalid_device';
    }
    final deviceSigningReason = _requiredKeyMaterialRejectReason(
      rawDevice,
      'deviceSigningPublicKey',
      'invalid_device_signing_public_key',
    );
    if (deviceSigningReason != null) {
      return deviceSigningReason;
    }
    final optionalReason =
        _optionalKeyMaterialRejectReason(
          rawDevice,
          'mlKemPublicKey',
          'invalid_device_ml_kem_public_key',
        ) ??
        _optionalKeyMaterialRejectReason(
          rawDevice,
          'keyPackagePublicMaterial',
          'invalid_key_package_public_material',
        );
    if (optionalReason != null) {
      return optionalReason;
    }
  }
  return null;
}

String? _requiredKeyMaterialRejectReason(
  Map<dynamic, dynamic> value,
  String key,
  String reason,
) {
  final raw = value[key];
  if (raw is! String || _isMalformedKeyMaterial(raw)) {
    return reason;
  }
  return null;
}

String? _optionalKeyMaterialRejectReason(
  Map<dynamic, dynamic> value,
  String key,
  String reason,
) {
  if (!value.containsKey(key)) {
    return null;
  }
  final raw = value[key];
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    return '${reason}_type';
  }
  return _isMalformedKeyMaterial(raw) ? reason : null;
}

bool _isMalformedKeyMaterial(String value) {
  if (value.trim().isEmpty || value.trim() != value) {
    return true;
  }
  return value.runes.any((rune) => rune <= 0x20 || rune == 0x7f);
}
