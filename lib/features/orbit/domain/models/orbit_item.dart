import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';

/// Union type for items displayed in the Orbit list.
///
/// Each item has a [sortKey] used to order friends and groups together
/// by last activity (most recent first).
sealed class OrbitItem {
  /// Sort key for ordering: most recent activity first.
  /// Uses ISO-8601 timestamp string for consistent comparison.
  String get sortKey;
}

/// An orbit item representing a 1:1 friend.
class OrbitFriendItem extends OrbitItem {
  final OrbitFriend friend;

  OrbitFriendItem(this.friend);

  @override
  String get sortKey => friend.lastMessageTimestamp ?? '';
}

/// An orbit item representing a group.
class OrbitGroupItem extends OrbitItem {
  final OrbitGroup group;

  OrbitGroupItem(this.group);

  @override
  String get sortKey =>
      group.lastActivityTimestamp?.toUtc().toIso8601String() ?? '';
}
