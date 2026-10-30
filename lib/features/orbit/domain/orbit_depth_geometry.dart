import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

enum OrbitDepthLayer { flat, inner }

enum OrbitDepthAnchor { top, bottom }

enum OrbitDepthGesture { idle, vertical, turn, pinch }

/// A friend on the ring, with the live thought that seats them there.
typedef OrbitDepthSeat = ({OrbitFriend friend, PostModel thought});

/// Only friends with a live thought are seated, in the order [items] already
/// has: the friend the user chatted with last comes first.
List<OrbitDepthSeat> orbitDepthQueue(
  List<OrbitItem> items,
  Map<String, PostModel> thoughts,
  DateTime now,
) => [
  for (final item in items)
    if (item is OrbitFriendItem)
      if (liveOrbitDepthThought(thoughts[item.friend.peerId], now)
          case final thought?)
        (friend: item.friend, thought: thought),
];

PostModel? liveOrbitDepthThought(PostModel? thought, DateTime now) {
  final expiry = DateTime.tryParse(thought?.expiresAt ?? '')?.toUtc();
  return expiry != null && expiry.isAfter(now.toUtc()) ? thought : null;
}

/// Logical px on a 390 px wide screen; every length scales by width / 390.
const orbitCenterTilt = 55 * math.pi / 180;
const orbitCenterCamera = 4.0;
const orbitCenterRadius = 146 * .78;
const orbitCenterDiameter = 72.0;
const orbitCenterRingFace = 40 * .8;
const _soft = .75;
const _dim = .3;

/// [value] wrapped into (-count / 2, count / 2]: the seat straight behind
/// the center belongs to a friend still to come, not one already shown.
double orbitCenterWrap(double value, int count) {
  final wrapped = (count / 2 - value) % count;
  return count / 2 - (wrapped < 0 ? wrapped + count : wrapped);
}

/// As on the canvas's "One ring, 78% size": a face fades out only within
/// 0.35 rad of the far back, where it hands its seat to the next friend in
/// line, so at rest the back seat is empty.
double _backFade(double angle) {
  final fromBack = (angle - 3 * math.pi / 2) % (2 * math.pi);
  return (math.min(fromBack, 2 * math.pi - fromBack) / .35).clamp(0.0, 1.0);
}

/// A seat at ring angle [angle]: π/2 is the front, nearest the viewer and
/// lowest on screen. Returns the offset from the ring center and `near`.
(Offset, double) projectOrbitCenter(double angle, double radius, double tilt) {
  final near =
      orbitCenterCamera /
      (orbitCenterCamera - math.sin(angle) * math.sin(tilt));
  return (
    Offset(
      radius * math.cos(angle) * near,
      radius * math.sin(angle) * math.cos(tilt) * near,
    ),
    near,
  );
}

/// The back (far) and front (near) extents of the ring below and above its
/// center, as positive distances.
({double far, double near}) orbitCenterRingExtent(double scale, double tilt) {
  final radius = orbitCenterRadius * scale;
  final sin = math.sin(tilt);
  return (
    far:
        radius * math.cos(tilt) * orbitCenterCamera / (orbitCenterCamera + sin),
    near:
        radius * math.cos(tilt) * orbitCenterCamera / (orbitCenterCamera - sin),
  );
}

typedef OrbitCenterFace = ({
  int index,
  Offset offset,
  double diameter,
  double opacity,
  double darken,
  double lift,
});

/// Every visible face for [count] friends at turn position [pos], back to
/// front. Friend `index` sits `p = index - pos` seats from the center; the one
/// at `p ≈ 0` is lifted off the ring into the center. The next friend waits on
/// the left, or on the right with [nextOnRight].
List<OrbitCenterFace> orbitCenterFaces({
  required int count,
  required double pos,
  required double scale,
  double tilt = orbitCenterTilt,
  bool nextOnRight = false,
}) {
  if (count == 0) return const [];
  final seats = math.min(count, 6);
  final faces = <(double, OrbitCenterFace)>[];
  for (var index = 0; index < count; index++) {
    final p = orbitCenterWrap(index - pos, count);
    // One lap of six seats: a friend past the far back is the next lap's.
    if (seats == 6 && (p <= -3 || p > 3)) continue;
    final angle = math.pi / 2 + p * 2 * math.pi / seats;
    final opacity = count >= 6 ? _backFade(angle) : 1.0;
    if (opacity == 0) continue;
    final (offset, near) = projectOrbitCenter(
      angle,
      orbitCenterRadius * scale,
      tilt,
    );
    final ring = orbitCenterRingFace * scale * math.pow(near, _soft);
    final k = (1 - p.abs() / .6).clamp(0.0, 1.0);
    final lift = k * k * (3 - 2 * k);
    faces.add((
      lift > .5 ? double.infinity : near,
      (
        index: index,
        offset:
            Offset(nextOnRight ? -offset.dx : offset.dx, offset.dy) *
            (1 - lift),
        diameter: ring + (orbitCenterDiameter * scale - ring) * lift,
        opacity: opacity,
        darken: _dim * (1 - math.sin(angle)) / 2 * (1 - lift),
        lift: lift,
      ),
    ));
  }
  faces.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, face) in faces) face];
}
