import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';

/// 197 — Builds the Orbit inner-circle ring set from active friends + active
/// groups, interleaved into one most-recent-activity ordering (most recent
/// first).
///
/// Reuses the shipped [OrbitItem] union and its [OrbitItem.sortKey] so the rings
/// inherit the exact interleave the all-chats list already uses (friend
/// `lastMessageTimestamp` and group `lastActivityTimestamp` are both ISO-8601
/// UTC strings, so they compare lexically as chronological order).
///
/// Blocked friends are dropped — they are never seated on the rings, mirroring
/// the inner-circle surface's prior `where(!isBlocked)` guard. Archived groups
/// are excluded upstream at the `_activeGroups` source (this helper trusts its
/// [groups] input is already the active set).
List<OrbitItem> mergeInnerCircleItems({
  required List<OrbitFriend> friends,
  required List<OrbitGroup> groups,
}) {
  final items = <OrbitItem>[
    for (final friend in friends)
      if (!friend.isBlocked) OrbitFriendItem(friend),
    for (final group in groups) OrbitGroupItem(group),
  ]..sort((a, b) => b.sortKey.compareTo(a.sortKey));
  return items;
}
