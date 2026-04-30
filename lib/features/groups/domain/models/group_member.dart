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
    required this.joinedAt,
  });

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
      joinedAt: DateTime.parse(map['joined_at'] as String),
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
      'joined_at': joinedAt.toUtc().toIso8601String(),
    };
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
