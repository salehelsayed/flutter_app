import 'package:flutter_app/features/groups/domain/models/group_model.dart';

/// Composite model combining a group with its conversation activity data.
///
/// Used by the Orbit screen to display group rows alongside friend rows,
/// sorted by last activity.
class OrbitGroup {
  final GroupModel group;
  final String? latestMessageSenderUsername;
  final String? latestMessageText;
  final String? latestMessage;
  final int unreadCount;
  final DateTime? lastActivityTimestamp;

  const OrbitGroup({
    required this.group,
    this.latestMessageSenderUsername,
    this.latestMessageText,
    this.latestMessage,
    this.unreadCount = 0,
    this.lastActivityTimestamp,
  });

  String get groupId => group.id;
  String get name => group.name;
  GroupType get type => group.type;
}
