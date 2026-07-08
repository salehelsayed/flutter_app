import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';

/// 198 "Sculpt & Summon" — pure geometry engine for the Orbit inner-circle.
///
/// Normative source: `198-orbit-arch-overflow-edit-find-mockups.html` (the
/// mockup JS is authoritative where the spec table under-specifies). This
/// module owns every seat position, the badge re-spread, the concentric-arc
/// overflow layout, capacity/wrap math, overhang, entrance delays and seat
/// provenance — all as knob-parameterized pure functions so the widget layer
/// stays a thin renderer and the math is unit-testable in isolation.
///
/// Coordinates are offsets from the shared circle centre ([dx] right, [dy]
/// down). The rings and every arc share that one centre; the widget adds the
/// canvas origin / scroll offset.

// ---- Canvas constants (the viz canvas box; hoisted so the surface's handle
// anchors and the widget share one source of truth). ----
const double kOrbitCanvasSize = 320.0;
const double kOrbitCanvasCenter = kOrbitCanvasSize / 2;

// ---- Base geometry constants (pre-198 production values). ----
const double kOrbitRing1Radius = 62.0;
const double kOrbitRing2Radius = 108.0;
const int kOrbitRing1Count = 5;
const int kOrbitRing2Count = 8;
const double kOrbitRing1AvatarSize = 38.0;
const double kOrbitRing2AvatarSize = 30.0;
const double kOrbitMinTapTarget = 48.0;

// ---- Arc constants (mockup). ----
const double kOrbitArcRingGap = 46.0;
const double kOrbitArcAvatarBase = 34.0;
const double kOrbitArcAvatarMin = 20.0;
const double kOrbitArcAvatarMax = 52.0;
const double kOrbitArcAvatarPitchPad = 10.0;
const double kOrbitPhiFull = 2.9;
const double kOrbitPinchHalfWidth = 170.0;
const int kOrbitMaxArcs = 12;
const double kOrbitOverhangMargin = 30.0;

/// Which surface a seat sits on.
enum OrbitSeatKind { ring1, ring2, arc }

/// Where a member ended up — used to build the localized find-chip provenance.
class OrbitProvenance {
  /// 1 or 2 for the inner rings; null when the member is on an arc.
  final int? ringNumber;

  /// 1-based arc number (arc 1 is the first overflow arc); null on the rings.
  final int? arcNumber;

  const OrbitProvenance.ring(this.ringNumber) : arcNumber = null;
  const OrbitProvenance.arc(this.arcNumber) : ringNumber = null;

  bool get isArc => arcNumber != null;

  @override
  bool operator ==(Object other) =>
      other is OrbitProvenance &&
      other.ringNumber == ringNumber &&
      other.arcNumber == arcNumber;

  @override
  int get hashCode => Object.hash(ringNumber, arcNumber);

  @override
  String toString() => isArc ? 'arc $arcNumber' : 'ring $ringNumber';
}

/// A single seated member's placement.
class OrbitSeat {
  /// Index into the merged inner-circle item list (0-based, merged-recency).
  final int index;
  final double dx;
  final double dy;
  final double radius;
  final double angle;

  /// Visual avatar diameter (px). The interactive tap target is separately
  /// floored to [kOrbitMinTapTarget] by the renderer.
  final double avatarSize;
  final OrbitSeatKind kind;

  /// 0-based arc index when [kind] is [OrbitSeatKind.arc]; null otherwise.
  final int? arcIndex;
  final int entranceDelayMs;

  /// Alternating (0/1) label stagger — `j%2` within an arc so adjacent arc
  /// labels don't collide. Always 0 for ring seats (rings never stagger labels).
  final int staggerParity;

  const OrbitSeat({
    required this.index,
    required this.dx,
    required this.dy,
    required this.radius,
    required this.angle,
    required this.avatarSize,
    required this.kind,
    required this.arcIndex,
    required this.entranceDelayMs,
    this.staggerParity = 0,
  });

  OrbitProvenance get provenance => switch (kind) {
    OrbitSeatKind.ring1 => const OrbitProvenance.ring(1),
    OrbitSeatKind.ring2 => const OrbitProvenance.ring(2),
    OrbitSeatKind.arc => OrbitProvenance.arc((arcIndex ?? 0) + 1),
  };
}

/// The overflow badge's placement (the notional 9th ring-2 slot).
class OrbitBadgeSlot {
  final double dx;
  final double dy;
  final double radius;
  final double angle;

  /// Members beyond the 13 inner-circle seats.
  final int overflowCount;

  const OrbitBadgeSlot({
    required this.dx,
    required this.dy,
    required this.radius,
    required this.angle,
    required this.overflowCount,
  });
}

/// The full inner-circle layout for a population under a geometry.
class OrbitLayout {
  final List<OrbitSeat> seats;
  final OrbitBadgeSlot? badge;
  final double ring1Radius;
  final double ring2Radius;
  final int memberCount;
  final bool mirrored;

  const OrbitLayout({
    required this.seats,
    required this.badge,
    required this.ring1Radius,
    required this.ring2Radius,
    required this.memberCount,
    required this.mirrored,
  });

  bool get hasOverflow => memberCount > (kOrbitRing1Count + kOrbitRing2Count);
}

const int _kInnerCircleSeats = kOrbitRing1Count + kOrbitRing2Count; // 13

double _angleOf(double dx, double dy) => math.atan2(dy, dx);

/// Seat 12-o'clock polar angle for slot [i] of [n] on ring [ring] (0 or 1).
/// Ring 0 starts at 12 o'clock; each ring is offset a further +15°.
double orbitSeatAngle(int i, int n, int ring) =>
    ((i * 360 / n) + ring * 15 - 90) * math.pi / 180;

/// Arc avatar diameter: clamp(34·av, 20, 52). Follows ONLY the avatar knob (like
/// the inner rings) so the spacing knob visibly moves arcs apart.
double orbitArcAvatarSize(OrbitGeometryPrefs geometry) =>
    (kOrbitArcAvatarBase * geometry.avatarScale)
        .clamp(kOrbitArcAvatarMin, kOrbitArcAvatarMax)
        .toDouble();

/// Radius of arc [arcIndex] (0-based): (108 + 46·og + 46·arcIndex)·sp. og scales
/// ONLY the circle→first-arc gap; arc-to-arc spacing stays 46·sp.
double orbitArcRadius(OrbitGeometryPrefs geometry, int arcIndex) =>
    (kOrbitRing2Radius +
        kOrbitArcRingGap * geometry.orbitGap +
        kOrbitArcRingGap * arcIndex) *
    geometry.spacingScale;

/// Radians of arc half-span per unit of the wrap knob (mockup 1.25) — shared
/// by [orbitArcPhi] and the [orbitArcWrapFromPointer] inverse mapping.
const double kOrbitPhiPerWrap = 1.25;

/// Half-span (radians) of an arc at [radius] under wrap knob [arcWrap]. Below
/// the 170px pinch width the span is `min(2.9, 1.25·cv)`; past it the span is
/// pinched to keep the arc inside the bezel until cv releases it back to 2.9.
double orbitArcPhi(double radius, double arcWrap) {
  final base = math.min(kOrbitPhiFull, kOrbitPhiPerWrap * arcWrap);
  if (radius <= kOrbitPinchHalfWidth) return base;
  final pinch = math.asin(math.min(1.0, kOrbitPinchHalfWidth / radius));
  final release = ((arcWrap - 1.6) / 0.9).clamp(0.0, 1.0);
  return math.min(base, pinch + (kOrbitPhiFull - pinch) * release);
}

/// Max seats on arc [arcIndex]: max(4, min(⌊2φr/(av+10)⌋, round(pr))). The knob
/// can only LOWER the auto-fit; auto-fit already keeps ≥44pt targets.
int orbitArcCapacity(OrbitGeometryPrefs geometry, int arcIndex) {
  final r = orbitArcRadius(geometry, arcIndex);
  final phi = orbitArcPhi(r, geometry.arcWrap);
  final av = orbitArcAvatarSize(geometry);
  final fit = (2 * phi * r / (av + kOrbitArcAvatarPitchPad)).floor();
  return math.max(4, math.min(fit, geometry.maxPerArc));
}

/// The capacity of each of the [kOrbitMaxArcs] arcs.
List<int> orbitArcCaps(OrbitGeometryPrefs geometry) => [
  for (var a = 0; a < kOrbitMaxArcs; a++) orbitArcCapacity(geometry, a),
];

/// Provenance of member [index] under [geometry]. Past the 12-arc envelope the
/// real (extrapolated) arc index is returned — nothing is culled, so every seat
/// has a number.
OrbitProvenance orbitProvenanceOf(OrbitGeometryPrefs geometry, int index) {
  if (index < kOrbitRing1Count) return const OrbitProvenance.ring(1);
  if (index < _kInnerCircleSeats) return const OrbitProvenance.ring(2);
  var o = index - _kInnerCircleSeats;
  final caps = orbitArcCaps(geometry);
  for (var a = 0; a < caps.length; a++) {
    if (o < caps[a]) return OrbitProvenance.arc(a + 1);
    o -= caps[a];
  }
  final lastCap = caps.isNotEmpty && caps.last > 0 ? caps.last : 4;
  return OrbitProvenance.arc(caps.length + (o ~/ lastCap) + 1);
}

/// Pixels the arc stack pokes past [topMargin] above the chrome (given the
/// circle centre at [centerY]) — the circle slides down by this and the canvas
/// grows; nothing is ever culled.
double orbitArcOverhang({
  required int memberCount,
  required OrbitGeometryPrefs geometry,
  required double centerY,
  double topMargin = kOrbitOverhangMargin,
}) {
  final overflow = memberCount - _kInnerCircleSeats;
  if (overflow <= 0) return 0.0;
  final caps = orbitArcCaps(geometry);
  var idx = 0, a = 0;
  while (idx < overflow && a < caps.length) {
    idx += caps[a];
    a++;
  }
  final maxR = orbitArcRadius(geometry, a - 1);
  final av = orbitArcAvatarSize(geometry);
  final topY = centerY - maxR - av / 2 - 16;
  return math.max(0.0, (topMargin - topY).ceilToDouble());
}

/// Pixels the lowest seat tap target pokes below the base canvas bottom.
///
/// This scans every computed seat because high spacing can make ring-2 tap
/// boxes poke below the canvas, while high wrap can make arc tips droop lower.
double orbitArcBottomOverhang({
  required int memberCount,
  required OrbitGeometryPrefs geometry,
  required double centerY,
}) {
  final layout = computeOrbitLayout(
    memberCount: memberCount,
    geometry: geometry,
  );
  var bottom = 0.0;
  for (final seat in layout.seats) {
    final tapTarget = math.max(seat.avatarSize, kOrbitMinTapTarget);
    bottom = math.max(bottom, seat.dy + tapTarget / 2);
  }
  return math.max(0.0, bottom - centerY);
}

/// Full inner-circle layout for [memberCount] members under [geometry].
OrbitLayout computeOrbitLayout({
  required int memberCount,
  required OrbitGeometryPrefs geometry,
  bool mirrored = false,
}) {
  final sp = geometry.spacingScale;
  final av = geometry.avatarScale;
  final r1 = kOrbitRing1Radius * sp;
  final r2 = kOrbitRing2Radius * sp;
  final ring1Avatar = kOrbitRing1AvatarSize * av;
  final ring2Avatar = kOrbitRing2AvatarSize * av;
  final over = memberCount > _kInnerCircleSeats;
  final sign = mirrored ? -1.0 : 1.0;
  final seats = <OrbitSeat>[];

  // Ring 1 — members 0..4. A partial ring spreads over its actual seat count
  // (HEAD parity, INV-6); the full ring is 5.
  final ring1End = math.min(kOrbitRing1Count, memberCount);
  for (var i = 0; i < ring1End; i++) {
    final a = orbitSeatAngle(i, ring1End, 0);
    final dx = sign * math.cos(a) * r1;
    final dy = math.sin(a) * r1;
    seats.add(
      OrbitSeat(
        index: i,
        dx: dx,
        dy: dy,
        radius: r1,
        angle: _angleOf(dx, dy),
        avatarSize: ring1Avatar,
        kind: OrbitSeatKind.ring1,
        arcIndex: null,
        entranceDelayMs: 0,
      ),
    );
  }

  // Ring 2 — members 5..12. A partial ring spreads over its actual seat count
  // (HEAD parity); a FULL ring re-spreads to 9 slots when overflowing so the
  // badge can take the 9th slot.
  final ring2End = math.min(_kInnerCircleSeats, memberCount);
  final ring2Count = ring2End - kOrbitRing1Count;
  final ring2Slots = over ? 9 : ring2Count;
  for (var i = kOrbitRing1Count; i < ring2End; i++) {
    final a = orbitSeatAngle(i - kOrbitRing1Count, ring2Slots, 1);
    final dx = sign * math.cos(a) * r2;
    final dy = math.sin(a) * r2;
    seats.add(
      OrbitSeat(
        index: i,
        dx: dx,
        dy: dy,
        radius: r2,
        angle: _angleOf(dx, dy),
        avatarSize: ring2Avatar,
        kind: OrbitSeatKind.ring2,
        arcIndex: null,
        entranceDelayMs: 0,
      ),
    );
  }

  // Badge — the notional 9th ring-2 slot.
  OrbitBadgeSlot? badge;
  if (over) {
    final a = orbitSeatAngle(8, 9, 1);
    final dx = sign * math.cos(a) * r2;
    final dy = math.sin(a) * r2;
    badge = OrbitBadgeSlot(
      dx: dx,
      dy: dy,
      radius: r2,
      angle: _angleOf(dx, dy),
      overflowCount: memberCount - _kInnerCircleSeats,
    );
  }

  // Arcs — members 13.. onto concentric arcs; nothing is culled.
  final avPx = orbitArcAvatarSize(geometry);
  var idx = _kInnerCircleSeats;
  var arcI = 0;
  while (idx < memberCount && arcI < kOrbitMaxArcs) {
    final r = orbitArcRadius(geometry, arcI);
    final phiMax = orbitArcPhi(r, geometry.arcWrap);
    final cap = orbitArcCapacity(geometry, arcI);
    final seatCount = math.min(cap, memberCount - idx);
    final pitch = cap > 1 ? (2 * phiMax) / (cap - 1) : 0.0;
    // A full arc uses the full span; a partial last arc is centred at 12 o'clock.
    final start = seatCount == cap ? -phiMax : -pitch * (seatCount - 1) / 2;
    for (var j = 0; j < seatCount; j++) {
      final phi = start + j * pitch;
      final dx = sign * r * math.sin(phi);
      final dy = -r * math.cos(phi);
      seats.add(
        OrbitSeat(
          index: idx + j,
          dx: dx,
          dy: dy,
          radius: r,
          angle: _angleOf(dx, dy),
          avatarSize: avPx,
          kind: OrbitSeatKind.arc,
          arcIndex: arcI,
          entranceDelayMs: arcI * 60 + j * 5,
          staggerParity: j % 2,
        ),
      );
    }
    idx +=
        cap; // advance by full cap (mockup); overshoot past the end is harmless
    arcI++;
  }

  return OrbitLayout(
    seats: seats,
    badge: badge,
    ring1Radius: r1,
    ring2Radius: r2,
    memberCount: memberCount,
    mirrored: mirrored,
  );
}

/// 198 fidelity — centre-local anchor of [knob]'s geometry handle (spec :23):
/// sp rides ring 2's 6 o'clock, av ring 1's 12 o'clock, og the first arc's
/// apex, cv the first arc's +φ tip, pr its −φ twin. Anchors sit on the PAINTED
/// geometry, not on seats (ring-2 seats are offset +15°). [mirrored] flips the
/// tip x like [computeOrbitLayout] does under RTL — the renderer must place
/// these with a physical `Positioned(left:)` (never PositionedDirectional) or
/// the tips double-flip.
Offset orbitHandleAnchor(
  OrbitKnob knob,
  OrbitGeometryPrefs geometry, {
  bool mirrored = false,
}) {
  final sp = geometry.spacingScale;
  final r0 = orbitArcRadius(geometry, 0);
  final phi0 = orbitArcPhi(r0, geometry.arcWrap);
  final sign = mirrored ? -1.0 : 1.0;
  return switch (knob) {
    OrbitKnob.spacingScale => Offset(0, kOrbitRing2Radius * sp),
    OrbitKnob.avatarScale => Offset(0, -kOrbitRing1Radius * sp),
    OrbitKnob.orbitGap => Offset(0, -r0),
    OrbitKnob.arcWrap => Offset(
      sign * r0 * math.sin(phi0),
      -r0 * math.cos(phi0),
    ),
    OrbitKnob.maxPerArc => Offset(
      -sign * r0 * math.sin(phi0),
      -r0 * math.cos(phi0),
    ),
  };
}

/// 198 fidelity (M8) — og knob delta for a drag of [dy] pixels: −dy/(46·sp),
/// with sp snapshotted at drag START so the mapping is stable mid-gesture.
/// The ÷sp keeps the same finger travel per VISUAL gap change at any spacing.
double orbitGapDragDelta(double dy, double spAtDragStart) =>
    -dy / (kOrbitArcRingGap * spAtDragStart);

/// 198 fidelity (M7) — cv follows the pointer's ANGLE around the circle
/// [centre]: cv = clamp(|atan2(px−cx, cy−py)| / 1.25, 0.5, 2.5). |atan2| makes
/// the mapping mirror-symmetric, so it needs no RTL special-casing.
double orbitArcWrapFromPointer(Offset centre, Offset pointer) {
  final angle = math
      .atan2(pointer.dx - centre.dx, centre.dy - pointer.dy)
      .abs();
  return (angle / kOrbitPhiPerWrap).clamp(
    OrbitGeometryPrefs.minArcWrap,
    OrbitGeometryPrefs.maxArcWrap,
  );
}
