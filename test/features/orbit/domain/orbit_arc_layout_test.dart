import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart';

OrbitGeometryPrefs _g({
  double av = 1,
  double sp = 1,
  double cv = 1,
  int pr = 9,
  double og = 1,
}) =>
    OrbitGeometryPrefs(
      avatarScale: av,
      spacingScale: sp,
      arcWrap: cv,
      maxPerArc: pr,
      orbitGap: og,
    );

void main() {
  group('orbit_arc_layout pure math (198 F1)', () {
    // TC-198-32 — og scales ONLY the ring2→arc0 gap; arc-to-arc stays 46·sp.
    test('arc radius formula: og isolates the first gap; sp scales all', () {
      expect(orbitArcRadius(_g(), 0), closeTo(154, 1e-9));
      expect(orbitArcRadius(_g(), 1), closeTo(200, 1e-9));
      expect(orbitArcRadius(_g(), 1) - orbitArcRadius(_g(), 0),
          closeTo(kOrbitArcRingGap, 1e-9));

      // og widens the first gap to 46·og but leaves arc-to-arc at 46.
      expect(orbitArcRadius(_g(og: 2.5), 0), closeTo(223, 1e-9));
      expect(orbitArcRadius(_g(og: 2.5), 1) - orbitArcRadius(_g(og: 2.5), 0),
          closeTo(46, 1e-9));

      // sp scales every radius (and the gap) uniformly.
      expect(orbitArcRadius(_g(sp: 1.5), 0), closeTo(231, 1e-9));
      expect(orbitArcRadius(_g(sp: 1.5), 1) - orbitArcRadius(_g(sp: 1.5), 0),
          closeTo(69, 1e-9));
    });

    // TC-198-28 math — avPx = clamp(34·av, 20, 52).
    test('arc avatar size clamps to [20,52]', () {
      expect(orbitArcAvatarSize(_g()), closeTo(34, 1e-9));
      expect(orbitArcAvatarSize(_g(av: 1.4)), closeTo(47.6, 1e-9));
      expect(orbitArcAvatarSize(_g(av: 0.5)), closeTo(20, 1e-9)); // min clamp
      expect(orbitArcAvatarSize(_g(av: 2.0)), closeTo(52, 1e-9)); // max clamp
    });

    // TC-198-30 — phi pinch/release with the 1.6 / 2.5 boundaries; never meets.
    test('arcPhi: base below 170, pinch-then-release above, never reaches pi', () {
      // r ≤ 170 → base = min(2.9, 1.25·cv).
      expect(orbitArcPhi(154, 1), closeTo(1.25, 1e-9));
      expect(orbitArcPhi(154, 1.6), closeTo(2.0, 1e-9));

      // r > 170, cv = 1.6 → release is exactly 0, so phi == the pinch.
      expect(orbitArcPhi(200, 1.6), closeTo(math.asin(0.85), 1e-9));

      // cv = 2.5 → release is 1, phi opens fully to PHI_FULL.
      expect(orbitArcPhi(200, 2.5), closeTo(kOrbitPhiFull, 1e-9));

      // PHI_FULL stays short of pi so the two arc ends never meet at the bottom.
      expect(kOrbitPhiFull, lessThan(math.pi));
      for (final cv in [0.5, 1.0, 1.6, 2.0, 2.5]) {
        for (final r in [120.0, 170.0, 250.0, 400.0]) {
          expect(orbitArcPhi(r, cv), lessThanOrEqualTo(kOrbitPhiFull + 1e-9));
        }
      }
    });

    // TC-198-30 containment — at cv ≤ 1.6 every seat stays inside a 390px box.
    test('cv ≤ 1.6: no seat exceeds 170px horizontal from centre (390px safe)', () {
      final layout = computeOrbitLayout(memberCount: 50, geometry: _g(cv: 1.6));
      for (final s in layout.seats) {
        expect(s.dx.abs(), lessThanOrEqualTo(170.5),
            reason: 'seat ${s.index} dx=${s.dx}');
      }
    });

    // TC-198-31 — capacity = max(4, min(⌊2φr/(av+10)⌋, round(pr))).
    test('capacity: default arc0 auto-fits to 8; pr caps every arc', () {
      expect(orbitArcCapacity(_g(), 0), 8);
      // pr lowers the cap; auto-fit can only reduce further, never exceed pr.
      expect(orbitArcCapacity(_g(pr: 4), 0), 4);
      expect(orbitArcCapacity(_g(pr: 4), 1), 4);
      // the max(4, …) floor holds.
      for (var a = 0; a < kOrbitMaxArcs; a++) {
        expect(orbitArcCapacity(_g(pr: 4), a), greaterThanOrEqualTo(4));
      }
    });

    // TC-198-06 — 24 members: [8,3] across two arcs, partial arc centred, none culled.
    test('24 members distribute [8,3], nothing culled, partial arc centred', () {
      final layout = computeOrbitLayout(memberCount: 24, geometry: _g());
      // nothing culled — every member is seated.
      expect(layout.seats.length, 24);

      final arc0 = layout.seats.where((s) => s.arcIndex == 0).toList();
      final arc1 = layout.seats.where((s) => s.arcIndex == 1).toList();
      expect(arc0.length, 8);
      expect(arc1.length, 3);

      // arc0 is full → symmetric about 12 o'clock (first dx == −last dx).
      expect(arc0.first.dx, closeTo(-arc0.last.dx, 1e-6));
      expect(arc0.first.dy, closeTo(arc0.last.dy, 1e-6));

      // arc1 is partial (3 of 9) → centred: the middle seat sits straight up.
      final middle = arc1[1];
      expect(middle.dx, closeTo(0, 1e-6));
      expect(middle.dy, closeTo(-orbitArcRadius(_g(), 1), 1e-6));
    });

    // TC-198-07 math — 50 members spread over 4+ arcs, nothing culled.
    test('50 members: 4+ arcs, nothing culled', () {
      final layout = computeOrbitLayout(memberCount: 50, geometry: _g());
      expect(layout.seats.length, 50);
      final arcs =
          layout.seats.where((s) => s.arcIndex != null).map((s) => s.arcIndex!);
      expect(arcs.toSet().length, greaterThanOrEqualTo(4));
    });

    // TC-198-13 — overflow seats fill in merged-recency (list) order.
    test('overflow fills arcs in member order; seat 14 is the first arc seat', () {
      final layout = computeOrbitLayout(memberCount: 24, geometry: _g());
      // member 13 (the 14th, most-recent overflow item) → arc 0, first seat.
      expect(layout.seats[13].arcIndex, 0);
      // arc 0 holds members 13..20, arc 1 holds 21..23 — strictly in order.
      for (var i = 13; i <= 20; i++) {
        expect(layout.seats[i].arcIndex, 0);
      }
      for (var i = 21; i <= 23; i++) {
        expect(layout.seats[i].arcIndex, 1);
      }
    });

    // TC-198-58 math — RTL mirrors the fill horizontally.
    test('RTL mirrors every seat and the badge across the vertical axis', () {
      final ltr = computeOrbitLayout(memberCount: 24, geometry: _g());
      final rtl =
          computeOrbitLayout(memberCount: 24, geometry: _g(), mirrored: true);
      for (var i = 0; i < ltr.seats.length; i++) {
        expect(rtl.seats[i].dx, closeTo(-ltr.seats[i].dx, 1e-9));
        expect(rtl.seats[i].dy, closeTo(ltr.seats[i].dy, 1e-9));
      }
      expect(rtl.badge!.dx, closeTo(-ltr.badge!.dx, 1e-9));
    });

    // TC-198-72 math — overhang (planted-circle delta).
    test('overhang: 0 without overflow, grows with the outermost arc', () {
      expect(
          orbitArcOverhang(
              memberCount: 13, geometry: _g(), centerY: 195),
          0);
      expect(
          orbitArcOverhang(
              memberCount: 14, geometry: _g(), centerY: 195),
          closeTo(22, 1e-9));
      expect(
          orbitArcOverhang(
              memberCount: 50, geometry: _g(), centerY: 195),
          closeTo(206, 1e-9));
    });

    // TC-198-09 non-motion half — entrance delays are arcI·60 + seat·5 ms.
    test('entrance delays: rings instant, arcs staggered arcI·60 + j·5', () {
      final layout = computeOrbitLayout(memberCount: 24, geometry: _g());
      expect(layout.seats[0].entranceDelayMs, 0); // ring node — instant
      expect(layout.seats[13].entranceDelayMs, 0); // arc0 j0
      expect(layout.seats[14].entranceDelayMs, 5); // arc0 j1
      expect(layout.seats[21].entranceDelayMs, 60); // arc1 j0
      expect(layout.seats[22].entranceDelayMs, 65); // arc1 j1
    });

    // Provenance mapping (drives find chips), incl. real arc index past ring 2.
    test('provenance: ring 1 (<5), ring 2 (5..12), real arc index (13+)', () {
      expect(orbitProvenanceOf(_g(), 4), const OrbitProvenance.ring(1));
      expect(orbitProvenanceOf(_g(), 5), const OrbitProvenance.ring(2));
      expect(orbitProvenanceOf(_g(), 12), const OrbitProvenance.ring(2));
      expect(orbitProvenanceOf(_g(), 13), const OrbitProvenance.arc(1));
      expect(orbitProvenanceOf(_g(), 21), const OrbitProvenance.arc(2));
    });

    // TC-198-03 math — 9-slot badge re-spread on overflow; 8 slots otherwise.
    test('badge re-spread: overflow re-spreads ring 2 to 9 slots, badge at 245°', () {
      // Angles are stored as atan2(dy,dx) (mirror-safe), so compare direction.
      void expectSameDir(double a, double b) {
        expect(math.cos(a), closeTo(math.cos(b), 1e-9));
        expect(math.sin(a), closeTo(math.sin(b), 1e-9));
      }

      // seat-angle primitives (12 o'clock start, +15°/ring).
      expect(orbitSeatAngle(0, 5, 0), closeTo(-math.pi / 2, 1e-9));
      expect(orbitSeatAngle(8, 9, 1), closeTo(245 * math.pi / 180, 1e-9));

      // No overflow (13): ring 2 uses 8 slots, no badge.
      final full = computeOrbitLayout(memberCount: 13, geometry: _g());
      expect(full.badge, isNull);
      expectSameDir(full.seats[5].angle, orbitSeatAngle(0, 8, 1));

      // Overflow (14): ring 2 re-spreads to 9 slots; badge occupies slot 8 (245°).
      final over = computeOrbitLayout(memberCount: 14, geometry: _g());
      expect(over.badge, isNotNull);
      expect(over.badge!.overflowCount, 1);
      expectSameDir(over.badge!.angle, orbitSeatAngle(8, 9, 1));
      expectSameDir(over.seats[5].angle, orbitSeatAngle(0, 9, 1));
      // The re-spread actually moved the interior seats (slot 1 = member 6);
      // slot 0 (member 5) is invariant to slot count so it does not move.
      expectSameDir(over.seats[6].angle, orbitSeatAngle(1, 9, 1));
      expect(over.seats[6].angle, isNot(closeTo(full.seats[6].angle, 1e-6)));
    });

    // A partial ring spreads over its ACTUAL seat count (HEAD parity), not a
    // fixed 5/8 — the pure prerequisite for TC-198-62.
    test('partial rings spread over their actual seat count, no badge', () {
      final ten = computeOrbitLayout(memberCount: 10, geometry: _g());
      expect(ten.badge, isNull);
      void expectSameDir(double a, double b) {
        expect(math.cos(a), closeTo(math.cos(b), 1e-9));
        expect(math.sin(a), closeTo(math.sin(b), 1e-9));
      }

      // ring 1 = 5 seats over 5; ring 2 = 5 seats over 5.
      expectSameDir(ten.seats[0].angle, orbitSeatAngle(0, 5, 0));
      expectSameDir(ten.seats[5].angle, orbitSeatAngle(0, 5, 1));
      expectSameDir(ten.seats[9].angle, orbitSeatAngle(4, 5, 1));
    });

    // Ring radii + avatar sizes scale with sp / av (INV-6 default parity lives
    // in the widget suite; this locks the pure inputs it depends on).
    test('ring radii scale with sp; avatar sizes match ring/arc species', () {
      final d = computeOrbitLayout(memberCount: 14, geometry: _g());
      expect(d.ring1Radius, closeTo(62, 1e-9));
      expect(d.ring2Radius, closeTo(108, 1e-9));
      expect(d.seats[0].avatarSize, closeTo(38, 1e-9)); // ring1 species
      expect(d.seats[5].avatarSize, closeTo(30, 1e-9)); // ring2 species
      expect(d.seats[13].avatarSize, closeTo(34, 1e-9)); // arc species

      final scaled = computeOrbitLayout(memberCount: 14, geometry: _g(sp: 1.5));
      expect(scaled.ring1Radius, closeTo(93, 1e-9));
      expect(scaled.ring2Radius, closeTo(162, 1e-9));
    });
  });

  group('198 fidelity — drag-mapping helpers (rows 21/22)', () {
    // M8 — og drag sensitivity scales with the spacing knob: −dy/(46·sp), so a
    // spaced-out orbit needs the same FINGER travel per visual gap change.
    test('og drag sensitivity scales with spacing (÷46·sp)', () {
      expect(orbitGapDragDelta(-46, 1.0), closeTo(1.0, 1e-9));
      expect(orbitGapDragDelta(-46, 1.5), closeTo(1.0 / 1.5, 1e-9));
      expect(orbitGapDragDelta(46, 1.0), closeTo(-1.0, 1e-9));
      // Same dy, sp 1.5 → delta ÷1.5 (the wired twin drags the real handle).
      expect(orbitGapDragDelta(-23, 1.0) / orbitGapDragDelta(-23, 1.5),
          closeTo(1.5, 1e-9));
    });

    // M7 — cv pointer-angle mapping: the wrap follows the finger's ANGLE around
    // the circle centre: cv = clamp(|atan2(px−cx, cy−py)|/1.25, 0.5, 2.5).
    test('cv pointer-angle mapping: |atan2|/1.25 clamped to [0.5, 2.5]', () {
      const centre = Offset(160, 217);
      // Pointer straight above the centre → angle 0 → clamps at min 0.5.
      expect(orbitArcWrapFromPointer(centre, const Offset(160, 100)), 0.5);
      // Pointer due right → π/2 / 1.25.
      expect(orbitArcWrapFromPointer(centre, const Offset(300, 217)),
          closeTo(math.pi / 2 / 1.25, 1e-9));
      // Pointer due left mirrors through |atan2| — same wrap (RTL-safe).
      expect(orbitArcWrapFromPointer(centre, const Offset(20, 217)),
          closeTo(math.pi / 2 / 1.25, 1e-9));
      // Pointer (almost) straight below → angle → π → clamps at max 2.5.
      expect(orbitArcWrapFromPointer(centre, const Offset(161, 400)), 2.5);
      // A mid-quadrant point matches the formula exactly.
      expect(orbitArcWrapFromPointer(centre, const Offset(260, 159)),
          closeTo(math.atan2(100, 58).abs() / 1.25, 1e-9));
    });
  });
}
