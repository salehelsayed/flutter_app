import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';

import 'orbit2_group.dart';

/// A member of the Orbit2 inner circle — either a single friend or a whole
/// group ("orbit"). Identity is the underlying id, so [==]/[hashCode] make
/// `contains`/`removeWhere`/dedup work regardless of the variant.
class Orbit2InnerItem {
  final OrbitFriend? friend;
  final Orbit2Group? group;

  const Orbit2InnerItem.friend(OrbitFriend this.friend) : group = null;
  const Orbit2InnerItem.group(Orbit2Group this.group) : friend = null;

  bool get isGroup => group != null;

  /// Stable id: the friend's peerId or the group's id.
  String get id => isGroup ? group!.id : friend!.peerId;

  /// Name shown under the avatar / in search.
  String get displayName => isGroup ? group!.name : friend!.username;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Orbit2InnerItem && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
