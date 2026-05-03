class GroupInboxCursor {
  final String groupId;
  final String cursor;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GroupInboxCursor({
    required this.groupId,
    required this.cursor,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GroupInboxCursor.fromMap(Map<String, Object?> map) {
    return GroupInboxCursor(
      groupId: map['group_id'] as String,
      cursor: map['cursor'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'group_id': groupId,
      'cursor': cursor,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}
