/// Model representing a group encryption key.
///
/// Maps to the `group_keys` database table.
class GroupKeyInfo {
  /// The group this key belongs to.
  final String groupId;

  /// The generation (version) of this key.
  final int keyGeneration;

  /// The encrypted key material (base64-encoded).
  final String encryptedKey;

  /// When this key was created.
  final DateTime createdAt;

  const GroupKeyInfo({
    required this.groupId,
    required this.keyGeneration,
    required this.encryptedKey,
    required this.createdAt,
  });

  /// Creates a GroupKeyInfo from a database row map.
  factory GroupKeyInfo.fromMap(Map<String, dynamic> map) {
    return GroupKeyInfo(
      groupId: map['group_id'] as String,
      keyGeneration: map['key_generation'] as int,
      encryptedKey: map['encrypted_key'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Converts the model to a database row map.
  Map<String, dynamic> toMap() {
    return {
      'group_id': groupId,
      'key_generation': keyGeneration,
      'encrypted_key': encryptedKey,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroupKeyInfo &&
        other.groupId == groupId &&
        other.keyGeneration == keyGeneration;
  }

  @override
  int get hashCode => Object.hash(groupId, keyGeneration);

  @override
  String toString() {
    return 'GroupKeyInfo(groupId: $groupId, keyGeneration: $keyGeneration)';
  }
}
