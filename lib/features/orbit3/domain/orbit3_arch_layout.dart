import 'dart:math';

import 'package:flutter/painting.dart';

import 'orbit3_one_circle_layout.dart';

/// Seats held by the two inner Orbit3 orbits (ring 0 + ring 1 = 5 + 8 = 13).
/// Anyone beyond this is "overflow": they live on the ARCH above the circle and,
/// when it is tapped, in the arch panel — never on extra concentric rings.
final int kOrbit3InnerSeats =
    orbit3RingCapacity(0) + orbit3RingCapacity(1);

/// Default number of avatars laid on each arch arc row.
const int kOrbit3ArchPerRow = 8;

/// People beyond the two inner orbits — the "+N" the arch displays. Equal by
/// construction to the hidden count of a 2-ring-capped [computeOrbit3RingLayout]
/// (so the badge and the seating math can never drift apart).
int orbit3ArchOverflowCount(int population) {
  final overflow = population - kOrbit3InnerSeats;
  return overflow < 0 ? 0 : overflow;
}

/// The geometry of one arch panel render: the overflow members split into rows,
/// each laid as avatar centres on a shallow symmetric arc. Pure data — no
/// Flutter widget dependency beyond [Offset] — so the packing is unit-testable.
class Orbit3ArchArcLayout {
  /// Outer list = rows (top → bottom); inner list = avatar centres on that row.
  final List<List<Offset>> rows;
  const Orbit3ArchArcLayout({required this.rows});
}

/// Places [n] avatar centres across [width] on a shallow symmetric arc (a gentle
/// dome that bows by [dip] at the centre — the "semi-half circle" look), with
/// adjacent centres clearing [avatar] so they never overlap horizontally.
///
/// y is 0 at the two edges and −[dip] at the centre (negative = up), so the row
/// reads as an arch. x is inset by half an avatar so nothing clips the edges.
List<Offset> computeOrbit3ArcRow({
  required int n,
  required double width,
  required double avatar,
  double dip = 14,
}) {
  if (n <= 0) return const [];
  if (n == 1) return [Offset(width / 2, 0)];

  final left = avatar / 2;
  final right = width - avatar / 2;
  final step = (right - left) / (n - 1);

  final out = <Offset>[];
  for (var i = 0; i < n; i++) {
    final x = left + step * i;
    final u = (x - width / 2) / (width / 2); // −1 … 1 across the row
    final y = dip * (u * u - 1); // 0 at the edges, −dip at the centre
    out.add(Offset(x, y));
  }
  return out;
}

/// Splits [count] overflow members into rows of [perRow] and lays each on a
/// shallow arc spanning [width]. Order is preserved; the total is preserved.
Orbit3ArchArcLayout computeOrbit3ArchArcs({
  required int count,
  required double width,
  int perRow = kOrbit3ArchPerRow,
  double avatar = 38,
  double dip = 14,
}) {
  if (count <= 0) return const Orbit3ArchArcLayout(rows: []);
  final rows = <List<Offset>>[];
  var remaining = count;
  while (remaining > 0) {
    final n = min(perRow, remaining);
    rows.add(computeOrbit3ArcRow(n: n, width: width, avatar: avatar, dip: dip));
    remaining -= n;
  }
  return Orbit3ArchArcLayout(rows: rows);
}
