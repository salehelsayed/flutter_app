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

  /// Non-null when the group materialized but its topic-join has not yet
  /// succeeded (derived from the 088 group_rejoin_state table); carries the
  /// bounded retrier's attempt count so the row can show a "Joining…" /
  /// "Couldn't join" badge.
  final int? rejoinAttemptCount;

  const OrbitGroup({
    required this.group,
    this.latestMessageSenderUsername,
    this.latestMessageText,
    this.latestMessage,
    this.unreadCount = 0,
    this.lastActivityTimestamp,
    this.rejoinAttemptCount,
  });

  String get groupId => group.id;
  String get name => group.name;
  GroupType get type => group.type;

  OrbitGroup copyWith({int? rejoinAttemptCount}) {
    return OrbitGroup(
      group: group,
      latestMessageSenderUsername: latestMessageSenderUsername,
      latestMessageText: latestMessageText,
      latestMessage: latestMessage,
      unreadCount: unreadCount,
      lastActivityTimestamp: lastActivityTimestamp,
      rejoinAttemptCount: rejoinAttemptCount ?? this.rejoinAttemptCount,
    );
  }
}
