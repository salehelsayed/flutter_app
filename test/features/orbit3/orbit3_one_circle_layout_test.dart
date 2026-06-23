import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_one_circle_layout.dart';

/// Unit coverage for the Orbit3 "One Circle" sequential-fill packing math:
/// Orbit-parity fixed sizes, rings fill one-at-a-time, collapsed shows two rings
/// with an overflow (expand arrow), expanded seats everyone and grows the box.
void main() {
  group('computeOrbit3RingLayout — Orbit-parity fixed sizing', () {
    test('ring radii / avatar sizes / centre match the real Orbit screen', () {
      final l = computeOrbit3RingLayout(count: 13, expanded: false);
      expect(l.centerSize, 48);
      expect(l.radii[0], 62);
      expect(l.radii[1], 108);
      expect(l.avatarSizes[0], 38);
      expect(l.avatarSizes[1], 30);
      // The collapsed two-ring view is the Orbit 320px box.
      expect(l.boxSize, 320);
    });

    test('ring 3+ extend the pattern: r=154,200… avatars 26, caps 11,14…', () {
      expect(orbit3RingCapacity(0), 5);
      expect(orbit3RingCapacity(1), 8);
      expect(orbit3RingCapacity(2), 11);
      expect(orbit3RingCapacity(3), 14);
      expect(orbit3RingRadius(2), 154);
      expect(orbit3RingRadius(3), 200);
      expect(orbit3RingAvatar(2), 26);
      expect(orbit3RingAvatar(3), 26);
    });
  });

  group('computeOrbit3RingLayout — sequential fill', () {
    test('starts with ONE ring until it is full (count <= 5)', () {
      final l = computeOrbit3RingLayout(count: 5, expanded: false);
      expect(l.counts, [5]);
      expect(l.radii.length, 1);
      expect(l.hiddenCount, 0);
      expect(l.totalRings, 1);
    });

    test('a 2nd ring appears once the 1st is full', () {
      expect(computeOrbit3RingLayout(count: 6, expanded: false).counts, [5, 1]);
      expect(computeOrbit3RingLayout(count: 13, expanded: false).counts, [5, 8]);
    });

    test('two full rings (13) have NO overflow / no expand', () {
      final l = computeOrbit3RingLayout(count: 13, expanded: false);
      expect(l.counts, [5, 8]);
      expect(l.hiddenCount, 0);
      expect(l.totalRings, 2);
    });

    test('beyond 13 the extra members are hidden until expanded', () {
      final collapsed = computeOrbit3RingLayout(count: 14, expanded: false);
      expect(collapsed.counts, [5, 8]); // still only two rings shown
      expect(collapsed.hiddenCount, 1); // the 14th is hidden
      expect(collapsed.totalRings, 3); // a third ring is needed

      final expanded = computeOrbit3RingLayout(count: 14, expanded: true);
      expect(expanded.counts, [5, 8, 1]); // third ring revealed
      expect(expanded.hiddenCount, 0);
    });
  });

  group('computeOrbit3RingLayout — expanded seating & growth', () {
    test('seats EVERY member across rings (sum == N) when expanded, '
        'for N in {5,13,24,50}', () {
      for (final n in <int>[5, 13, 24, 50]) {
        final l = computeOrbit3RingLayout(count: n, expanded: true);
        expect(l.counts.fold<int>(0, (a, b) => a + b), n,
            reason: 'every member seated when expanded (N=$n)');
        expect(l.hiddenCount, 0);
        expect(l.radii.length, l.counts.length);
        expect(l.avatarSizes.length, l.counts.length);
      }
    });

    test('the box grows past 320 when expanded rings exceed the collapsed two',
        () {
      final collapsed = computeOrbit3RingLayout(count: 50, expanded: false);
      final expanded = computeOrbit3RingLayout(count: 50, expanded: true);
      expect(collapsed.boxSize, 320); // collapsed stays Orbit-size
      expect(expanded.boxSize, greaterThan(320)); // grows to fit outer rings
      // outermost ring + its avatars stay inside the (grown) box.
      expect(expanded.radii.last + expanded.avatarSizes.last / 2,
          lessThanOrEqualTo(expanded.boxSize / 2));
    });

    test('radii strictly ascending at N=50', () {
      final l = computeOrbit3RingLayout(count: 50, expanded: true);
      for (var k = 1; k < l.radii.length; k++) {
        expect(l.radii[k], greaterThan(l.radii[k - 1]));
      }
    });

    test('no avatar overlap at N=50 — within-ring arc AND inter-ring radial '
        'spacing each clear the avatar diameters', () {
      final l = computeOrbit3RingLayout(count: 50, expanded: true);
      // Within a ring: arc per slot >= that ring's avatar diameter.
      for (var k = 0; k < l.counts.length; k++) {
        if (l.counts[k] <= 0) continue;
        final arc = (2 * pi * l.radii[k]) / l.counts[k];
        expect(arc, greaterThanOrEqualTo(l.avatarSizes[k]),
            reason: 'ring $k arc too tight');
      }
      // Between adjacent rings: radial gap >= the mean of the two diameters.
      for (var k = 1; k < l.radii.length; k++) {
        final needed = (l.avatarSizes[k - 1] + l.avatarSizes[k]) / 2;
        expect(l.radii[k] - l.radii[k - 1], greaterThanOrEqualTo(needed),
            reason: 'rings ${k - 1}/$k too close');
      }
    });
  });
}
