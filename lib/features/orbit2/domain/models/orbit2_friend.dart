import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';

import 'avatar_tier.dart';

/// Prototype view-model for a friend on the floating canvas: an [OrbitFriend]
/// plus its display [tier].
class Orbit2Friend {
  final OrbitFriend friend;
  final AvatarTier tier;

  const Orbit2Friend({required this.friend, required this.tier});

  String get peerId => friend.peerId;
  String get username => friend.username;
}
