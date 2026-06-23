import 'dart:math';

/// The geometry of one Orbit3 "One Circle" render: how many members sit on each
/// VISIBLE concentric ring, the ring radii, and the per-ring avatar sizes.
///
/// Pure data — no Flutter dependency — so the packing math is unit-testable
/// independently of the widget that draws it.
class Orbit3RingLayout {
  /// Members assigned to each VISIBLE ring, inner → outer (sequential fill).
  final List<int> counts;

  /// Radius of each visible ring (ascending), same length as [counts].
  final List<double> radii;

  /// Avatar diameter for each visible ring (Orbit parity: 38, 30, then 26).
  final List<double> avatarSizes;

  /// Diameter of the centre "You" avatar.
  final double centerSize;

  /// The intrinsic box this layout draws into. Stays at the Orbit-parity 320 for
  /// the collapsed two-ring view and grows outward as more rings are revealed.
  final double boxSize;

  /// Members not shown in the current (collapsed) view — drives the expand arrow.
  /// Always 0 when [expanded] was true.
  final int hiddenCount;

  /// How many rings it takes to seat EVERY member (≥ visible ring count).
  final int totalRings;

  const Orbit3RingLayout({
    required this.counts,
    required this.radii,
    required this.avatarSizes,
    required this.centerSize,
    required this.boxSize,
    required this.hiddenCount,
    required this.totalRings,
  });

  bool get hasHidden => hiddenCount > 0;
}

// === Orbit-parity fixed geometry (matches lib/features/orbit OrbitalVisualization) ===
const double kOrbit3CenterSize = 48;
const double kOrbit3BaseBox = 320;
const int kOrbit3CollapsedRings = 2;
const double _kRing0Radius = 62;
const double _kRingGap = 46; // Orbit's ring2(108) − ring1(62)
const double _kRing0Avatar = 38;
const double _kRing1Avatar = 30;
const double _kOuterAvatar = 26;
const double _kBoxMargin = 8;

/// Capacity of ring [k] (0-indexed): 5, 8, 11, 14, … (Orbit's 5/8, then +3 each).
int orbit3RingCapacity(int k) => 5 + 3 * k;

/// Fixed radius of ring [k]: 62, 108, 154, … (Orbit's 62/108, then +46 each).
double orbit3RingRadius(int k) => _kRing0Radius + _kRingGap * k;

/// Fixed avatar diameter of ring [k]: 38, 30, then 26 (Orbit's 38/30).
double orbit3RingAvatar(int k) =>
    k == 0 ? _kRing0Avatar : (k == 1 ? _kRing1Avatar : _kOuterAvatar);

/// Lays members into fixed Orbit-parity concentric rings, filled SEQUENTIALLY:
/// ring 0 fills to capacity, then ring 1, then ring 2, … When [expanded] is
/// false only the inner [kOrbit3CollapsedRings] rings are shown and the rest
/// become [hiddenCount] (the expand-arrow overflow). When true, every member is
/// seated and the box grows to fit the outermost ring.
Orbit3RingLayout computeOrbit3RingLayout({
  required int count,
  required bool expanded,
}) {
  final n = count < 0 ? 0 : count;

  // Sequential fill: pour members into ring 0, then 1, then 2, … to capacity.
  final fills = <int>[];
  var remaining = n;
  var k = 0;
  while (remaining > 0) {
    final c = min(orbit3RingCapacity(k), remaining);
    fills.add(c);
    remaining -= c;
    k++;
  }
  if (fills.isEmpty) fills.add(0); // always one (possibly empty) inner ring

  final totalRings = fills.length;
  final visibleRings =
      expanded ? totalRings : min(totalRings, kOrbit3CollapsedRings);

  final counts = fills.take(visibleRings).toList();
  final radii = [for (var i = 0; i < visibleRings; i++) orbit3RingRadius(i)];
  final avatarSizes =
      [for (var i = 0; i < visibleRings; i++) orbit3RingAvatar(i)];
  final shown = counts.fold<int>(0, (a, b) => a + b);
  final hiddenCount = n - shown;

  final outerR = radii.isNotEmpty ? radii.last : 0.0;
  final outerAv = avatarSizes.isNotEmpty ? avatarSizes.last : 0.0;
  final boxSize = max(kOrbit3BaseBox, 2 * (outerR + outerAv / 2 + _kBoxMargin));

  return Orbit3RingLayout(
    counts: counts,
    radii: radii,
    avatarSizes: avatarSizes,
    centerSize: kOrbit3CenterSize,
    boxSize: boxSize,
    hiddenCount: hiddenCount,
    totalRings: totalRings,
  );
}
