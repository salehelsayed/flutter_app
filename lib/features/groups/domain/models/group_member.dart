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
