/// Enum representing the type of group.
enum GroupType {
  chat,
  announcement,
  qa;

  /// Converts to a database/wire string value.
  String toValue() => name;

  /// Parses from a database/wire string value.
  static GroupType fromValue(String value) {
    switch (value) {
      case 'chat':
        return GroupType.chat;
      case 'announcement':
        return GroupType.announcement;
      case 'qa':
        return GroupType.qa;
      default:
        throw ArgumentError('Unknown GroupType: $value');
    }
  }
}

/// Enum representing the local user's role in the group.
enum GroupRole {
  admin,
  member;

  /// Converts to a database/wire string value.
  String toValue() => name;

  /// Parses from a database/wire string value.
  static GroupRole fromValue(String value) {
    switch (value) {
      case 'admin':
        return GroupRole.admin;
      case 'member':
        return GroupRole.member;
      default:
        throw ArgumentError('Unknown GroupRole: $value');
    }
  }
}

/// Model representing a group.
///
/// Maps to the `groups` database table.
class GroupModel {
  /// Unique group ID.
  final String id;

  /// Display name of the group.
  final String name;

  /// The type of group (chat, announcement, qa).
  final GroupType type;

  /// The pubsub topic name for this group.
  final String topicName;

  /// Optional description of the group.
  final String? description;

  /// When the group was created.
  final DateTime createdAt;

  /// Peer ID of the group creator.
  final String createdBy;

  /// The local user's role in this group.
  final GroupRole myRole;

  /// Whether the group is archived.
  final bool isArchived;

  /// When the group was archived (null if not archived).
  final DateTime? archivedAt;

  /// Latest applied membership-event timestamp for stale-event rejection.
  final DateTime? lastMembershipEventAt;

  const GroupModel({
    required this.id,
    required this.name,
    required this.type,
    required this.topicName,
    this.description,
    required this.createdAt,
    required this.createdBy,
    required this.myRole,
    this.isArchived = false,
    this.archivedAt,
    this.lastMembershipEventAt,
  });

  /// Creates a GroupModel from a database row map.
  factory GroupModel.fromMap(Map<String, dynamic> map) {
    return GroupModel(
      id: map['id'] as String,
      name: map['name'] as String,
      type: GroupType.fromValue(map['type'] as String),
      topicName: map['topic_name'] as String,
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      createdBy: map['created_by'] as String,
      myRole: GroupRole.fromValue(map['my_role'] as String),
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      archivedAt: map['archived_at'] != null
          ? DateTime.parse(map['archived_at'] as String)
          : null,
      lastMembershipEventAt: map['last_membership_event_at'] != null
          ? DateTime.parse(map['last_membership_event_at'] as String)
          : null,
    );
  }

  /// Converts the model to a database row map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.toValue(),
      'topic_name': topicName,
      'description': description,
      'created_at': createdAt.toUtc().toIso8601String(),
      'created_by': createdBy,
      'my_role': myRole.toValue(),
      'is_archived': isArchived ? 1 : 0,
      'archived_at': archivedAt?.toUtc().toIso8601String(),
      'last_membership_event_at':
          lastMembershipEventAt?.toUtc().toIso8601String(),
    };
  }

  /// Creates a copy with updated fields.
  GroupModel copyWith({
    String? id,
    String? name,
    GroupType? type,
    String? topicName,
    Object? description = _sentinel,
    DateTime? createdAt,
    String? createdBy,
    GroupRole? myRole,
    bool? isArchived,
    Object? archivedAt = _sentinel,
    Object? lastMembershipEventAt = _sentinel,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      topicName: topicName ?? this.topicName,
      description: description == _sentinel
          ? this.description
          : description as String?,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      myRole: myRole ?? this.myRole,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt == _sentinel
          ? this.archivedAt
          : archivedAt as DateTime?,
      lastMembershipEventAt: lastMembershipEventAt == _sentinel
          ? this.lastMembershipEventAt
          : lastMembershipEventAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroupModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'GroupModel(id: $id, name: $name, type: ${type.toValue()})';
  }
}

const _sentinel = Object();
