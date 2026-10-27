import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

enum OrbitDepthLayer { flat, inner, outer }

enum OrbitDepthAnchor { top, bottom }

enum OrbitDepthGesture { idle, vertical, turn, pinch }

class OrbitDepthSeat {
  const OrbitDepthSeat(this.friend, this.placement, this.thought);
  final OrbitFriend friend;
  final OrbitSeat placement;
  final PostModel? thought;
  OrbitDepthLayer get layer => placement.kind == OrbitSeatKind.ring1
      ? OrbitDepthLayer.inner
      : OrbitDepthLayer.outer;
}

class OrbitDepthLayout {
  const OrbitDepthLayout(this.seats, this.overflow);
  final List<OrbitDepthSeat> seats;
  final OrbitBadgeSlot? overflow;

  /// Friends with a live thought take the first seats, side by side: the
  /// inner ring fills first and only then the next one. Everyone else follows
  /// in their usual order, so no thought sits between empty seats.
  factory OrbitDepthLayout.fromItems(
    List<OrbitItem> items,
    Map<String, PostModel> thoughts,
    DateTime now, {
    bool mirrored = false,
  }) {
    bool hasThought(OrbitItem item) =>
        item is OrbitFriendItem &&
        liveOrbitDepthThought(thoughts[item.friend.peerId], now) != null;
    final seated = [
      ...items.where(hasThought),
      ...items.where((item) => !hasThought(item)),
    ];
    final layout = computeOrbitLayout(
      memberCount: seated.length,
      geometry: OrbitGeometryPrefs.defaults,
      mirrored: mirrored,
    );
    return OrbitDepthLayout([
      for (final placement in layout.seats)
        if (placement.kind != OrbitSeatKind.arc)
          if (seated[placement.index] case final OrbitFriendItem item)
            OrbitDepthSeat(
              item.friend,
              placement,
              liveOrbitDepthThought(thoughts[item.friend.peerId], now),
            ),
    ], layout.badge);
  }

  List<OrbitDepthSeat> inLayer(OrbitDepthLayer layer) =>
      seats.where((seat) => seat.layer == layer).toList(growable: false);

  /// The same seats with today's friends and thoughts. A friend who left takes
  /// the seat along; everyone else stays where they were seated.
  OrbitDepthLayout reseated(
    Map<String, OrbitFriend> friends,
    Map<String, PostModel> thoughts,
    DateTime now,
  ) => OrbitDepthLayout([
    for (final seat in seats)
      if (friends[seat.friend.peerId] case final friend?)
        OrbitDepthSeat(
          friend,
          seat.placement,
          liveOrbitDepthThought(thoughts[friend.peerId], now),
        ),
  ], overflow);
}

PostModel? liveOrbitDepthThought(PostModel? thought, DateTime now) {
  final expiry = DateTime.tryParse(thought?.expiresAt ?? '')?.toUtc();
  return expiry != null && expiry.isAfter(now.toUtc()) ? thought : null;
}

double orbitDepthDelta(double angle) =>
    (angle + math.pi) % (2 * math.pi) - math.pi;

double orbitDepthRotationFor(OrbitDepthSeat seat, double current) =>
    current + orbitDepthDelta(math.pi / 2 - seat.placement.angle - current);

OrbitDepthSeat? orbitDepthNearest(List<OrbitDepthSeat> seats, double rotation) {
  final live = seats.where((seat) => seat.thought != null).toList();
  if (live.isEmpty) return null;
  live.sort(
    (a, b) => orbitDepthDelta(a.placement.angle + rotation - math.pi / 2)
        .abs()
        .compareTo(
          orbitDepthDelta(b.placement.angle + rotation - math.pi / 2).abs(),
        ),
  );
  return live.first;
}

OrbitDepthSeat? orbitDepthArrival(
  List<OrbitDepthSeat> seats,
  double rotation,
) =>
    seats
        .where((seat) => seat.thought != null && !seat.thought!.isRead)
        .firstOrNull ??
    orbitDepthNearest(seats, rotation);

/// The dial and faces share this perspective, so their edges cannot drift.
(Offset, double) projectOrbitDepth(double angle, double radius, double tilt) {
  final near = 3 / (3 - math.sin(angle) * math.sin(tilt));
  return (
    Offset(
      radius * math.cos(angle) * near,
      radius * math.sin(angle) * math.cos(tilt) * near,
    ),
    near,
  );
}
