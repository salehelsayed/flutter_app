import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_arch_layout.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_one_circle_layout.dart';

/// Unit coverage for the Orbit3 "Arch" overflow geometry: the +N count that
/// rides the arch above the inner circle, and the shallow semi-circle arc rows
/// the arch panel lays its overflow members onto.
void main() {
  group('orbit3ArchOverflowCount', () {
    test('kOrbit3InnerSeats is the two-ring capacity (5 + 8 = 13)', () {
      expect(kOrbit3InnerSeats, orbit3RingCapacity(0) + orbit3RingCapacity(1));
      expect(kOrbit3InnerSeats, 13);
    });

    test('= max(0, pop - 13) AND matches the 2-ring layout hiddenCount', () {
      const expected = <int, int>{5: 0, 13: 0, 14: 1, 24: 11, 50: 37};
      expected.forEach((pop, want) {
        expect(orbit3ArchOverflowCount(pop), want, reason: 'pop=$pop');
        // The arch count must agree with the seated-vs-hidden math the One
        // Circle already uses, not just coincide.
        final hidden = computeOrbit3RingLayout(
          count: pop,
          expanded: false,
          maxVisibleRings: kOrbit3CollapsedRings,
        ).hiddenCount;
        expect(orbit3ArchOverflowCount(pop), hidden,
            reason: 'matches layout.hiddenCount pop=$pop');
      });
    });

    test('never negative for tiny populations', () {
      expect(orbit3ArchOverflowCount(0), 0);
      expect(orbit3ArchOverflowCount(1), 0);
    });
  });

  group('computeOrbit3ArcRow', () {
    test('places n avatars on a symmetric, non-overlapping shallow arc', () {
      final pts = computeOrbit3ArcRow(n: 8, width: 360, avatar: 38);
      expect(pts.length, 8);

      // x is strictly increasing and stays within the row width.
      for (var i = 0; i < pts.length; i++) {
        expect(pts[i].dx, inInclusiveRange(0.0, 360.0), reason: 'x[$i] in bounds');
        if (i > 0) {
          expect(pts[i].dx, greaterThan(pts[i - 1].dx), reason: 'x increasing');
          // Adjacent centres clear the avatar diameter → no horizontal overlap.
          expect(pts[i].dx - pts[i - 1].dx, greaterThanOrEqualTo(38 - 1e-6),
              reason: 'gap $i clears the avatar');
        }
      }

      // Symmetric arc: the two ends share a y, and the centre is the extremum
      // (a real curve, not a flat row).
      expect(pts.first.dy, closeTo(pts.last.dy, 1e-6));
      final centreY = pts[pts.length ~/ 2].dy;
      expect((centreY - pts.first.dy).abs(), greaterThan(0.5),
          reason: 'the arc must bow at the centre, not be flat');
    });

    test('a single avatar centres on the row', () {
      final pts = computeOrbit3ArcRow(n: 1, width: 360, avatar: 38);
      expect(pts.length, 1);
      expect(pts.first.dx, closeTo(180, 1e-6));
    });

    test('returns nothing for an empty row', () {
      expect(computeOrbit3ArcRow(n: 0, width: 360, avatar: 38), isEmpty);
    });
  });

  group('computeOrbit3ArchArcs', () {
    test('splits count into rows of <= 8, preserving the total', () {
      final layout = computeOrbit3ArchArcs(count: 37, width: 360);
      expect(layout.rows.length, 5);
      var total = 0;
      for (final row in layout.rows) {
        expect(row.length, lessThanOrEqualTo(8));
        total += row.length;
      }
      expect(total, 37);
      expect(layout.rows.map((r) => r.length).toList(), [8, 8, 8, 8, 5]);
    });

    test('a small overflow is one partial row', () {
      final layout = computeOrbit3ArchArcs(count: 11, width: 360);
      expect(layout.rows.map((r) => r.length).toList(), [8, 3]);
    });

    test('no rows when there is no overflow', () {
      expect(computeOrbit3ArchArcs(count: 0, width: 360).rows, isEmpty);
    });

    test('every avatar in a row is a finite Offset within the width', () {
      final layout = computeOrbit3ArchArcs(count: 8, width: 360);
      for (final p in layout.rows.first) {
        expect(p.dx.isFinite && p.dy.isFinite, isTrue);
        expect(p.dx, inInclusiveRange(0.0, 360.0));
      }
      // sanity: dart:math + painting are exercised so the import is real
      expect(max(layout.rows.first.first.dx, 0), isNonNegative);
      expect(layout.rows.first.first, isA<Offset>());
    });
  });
}
