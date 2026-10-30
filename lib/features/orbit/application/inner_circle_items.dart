import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';

/// Builds the circle from active friends and groups, newest received message
/// first. Empty conversations follow by added/created time. Stable item kind
/// and identity break ties, independently of conversation-list activity.
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
  ]..sort(_compareCircleItems);
  return items;
}

int _compareCircleItems(OrbitItem a, OrbitItem b) {
  final aIncoming = _incomingAt(a);
  final bIncoming = _incomingAt(b);
  if ((aIncoming != null) != (bIncoming != null)) {
    return aIncoming != null ? -1 : 1;
  }
  final aTime = aIncoming ?? _addedAt(a);
  final bTime = bIncoming ?? _addedAt(b);
  final timeOrder = aTime == null
      ? (bTime == null ? 0 : 1)
      : (bTime == null ? -1 : bTime.compareTo(aTime));
  return timeOrder != 0 ? timeOrder : _identity(a).compareTo(_identity(b));
}

DateTime? _incomingAt(OrbitItem item) => switch (item) {
  OrbitFriendItem(:final friend) => friend.lastIncomingAt,
  OrbitGroupItem(:final group) => group.lastIncomingAt,
};

DateTime? _addedAt(OrbitItem item) => switch (item) {
  OrbitFriendItem(:final friend) => DateTime.tryParse(friend.scannedAt),
  OrbitGroupItem(:final group) => group.group.createdAt,
};

String _identity(OrbitItem item) => switch (item) {
  OrbitFriendItem(:final friend) => 'friend:${friend.peerId}',
  OrbitGroupItem(:final group) => 'group:${group.groupId}',
};
