import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart';
import 'package:flutter_app/features/orbit/domain/orbit_thought_layout.dart';
import 'package:flutter_test/flutter_test.dart';

const _canvas = Rect.fromLTWH(-195, -195, 390, 390);
const _avatar = Rect.fromLTWH(-24, -24, 48, 48);
const _long = (full: Size(150, 41), compact: Size(85, 26));

void main() {
  test('tries above, below, then a side that mirrors in RTL', () {
    OrbitThoughtPlacement place(List<Rect> obstacles, {bool rtl = false}) =>
        layoutOrbitThoughts(
          canvas: _canvas,
          avatars: {0: _avatar},
          previews: {0: _long},
          mirrored: rtl,
          otherObstacles: obstacles,
        )[0]!;

    const above = Rect.fromLTRB(-195, -195, 195, -24);
    const below = Rect.fromLTRB(-195, 24, 195, 195);
    expect(place([]).side, OrbitThoughtSide.above);
    expect(place([above]).side, OrbitThoughtSide.below);
    // Leave the side corridors wide enough for the full preview.
    const top = Rect.fromLTRB(-100, -195, 100, -24);
    const bottom = Rect.fromLTRB(-100, 24, 100, 195);
    const wide = Rect.fromLTWH(-250, -195, 500, 390);
    OrbitThoughtPlacement beside(bool rtl) => layoutOrbitThoughts(
      canvas: wide,
      avatars: {0: _avatar},
      previews: {0: _long},
      mirrored: rtl,
      otherObstacles: [top, bottom],
    )[0]!;
    expect(beside(false).side, OrbitThoughtSide.right);
    expect(beside(true).side, OrbitThoughtSide.left);
    expect(beside(false).rect.center.dx, -beside(true).rect.center.dx);
    expect(place([above, below]).side, OrbitThoughtSide.right);
  });

  test('mirrors equal sideways shifts around a centered obstacle', () {
    OrbitThoughtPlacement place(bool mirrored) => layoutOrbitThoughts(
      canvas: _canvas,
      avatars: {0: _avatar},
      previews: {0: _long},
      mirrored: mirrored,
      otherObstacles: [const Rect.fromLTRB(-10, -52, 10, -40)],
    )[0]!;
    final ltr = place(false);
    final rtl = place(true);
    expect(ltr.side, OrbitThoughtSide.above);
    expect(rtl.side, OrbitThoughtSide.above);
    expect(ltr.rect.center.dx.abs(), greaterThan(1));
    expect(ltr.rect.left, -rtl.rect.right);
    expect(ltr.rect.top, rtl.rect.top);
  });

  test(
    'fits a compact preview up to 96 points before using an 18 point badge',
    () {
      OrbitThoughtPlacement place(Rect canvas) => layoutOrbitThoughts(
        canvas: canvas,
        avatars: {0: _avatar},
        previews: {0: _long},
        mirrored: false,
      )[0]!;
      final compact = place(const Rect.fromLTRB(-48, -105, 48, 49));
      expect(compact.side, OrbitThoughtSide.above);
      expect(compact.compact, isTrue);
      expect(compact.rect.width, lessThanOrEqualTo(96));
      final badge = place(const Rect.fromLTRB(-30, -30, 30, 30));
      expect(badge.side, isNull);
      expect(badge.rect.size, const Size.square(18));
      expect(_avatar.contains(badge.rect.center), isTrue);
    },
  );

  test('keeps four fitting previews in priority order even with more room', () {
    const canvas = Rect.fromLTWH(-400, -120, 800, 240);
    final avatars = {
      for (var i = 0; i < 6; i++) i: _avatar.shift(Offset(-300 + 120.0 * i, 0)),
    };
    final result = layoutOrbitThoughts(
      canvas: canvas,
      avatars: avatars,
      previews: {
        for (final index in [4, 2, 0, 3, 5, 1])
          index: (full: const Size(50, 25), compact: const Size(40, 25)),
      },
      mirrored: false,
    );
    expect(
      [
        for (final entry in result.entries)
          if (entry.value.side != null) entry.key,
      ],
      [4, 2, 0, 3],
    );
    expect(result[5]!.rect.size, const Size.square(18));
    expect(result[1]!.rect.size, const Size.square(18));
  });

  for (final count in [0, 3, 8, 12, 13, 15]) {
    for (final width in [320.0, 390.0, 430.0]) {
      for (final mirrored in [false, true]) {
        test(
          'bounded non-overlapping previews for $count seats, $width wide, RTL $mirrored',
          () {
            final layout = computeOrbitLayout(
              memberCount: count,
              geometry: OrbitGeometryPrefs.defaults,
              mirrored: mirrored,
            );
            final avatars = {
              -1: _avatar,
              for (final seat in layout.seats.where(
                (s) => s.kind != OrbitSeatKind.arc,
              ))
                seat.index: Rect.fromCenter(
                  center: Offset(seat.dx, seat.dy),
                  width: math.max(48, seat.avatarSize),
                  height: math.max(48, seat.avatarSize),
                ),
            };
            final canvas = Rect.fromLTWH(-width / 2, -185, width, 370);
            final obstacles = [
              if (layout.badge case final badge?)
                Rect.fromCenter(
                  center: Offset(badge.dx, badge.dy),
                  width: 44,
                  height: 44,
                ),
            ];
            Map<int, OrbitThoughtPlacement> place() => layoutOrbitThoughts(
              canvas: canvas,
              avatars: Map.of(avatars),
              previews: {for (final index in avatars.keys) index: _long},
              mirrored: mirrored,
              otherObstacles: obstacles,
            );
            final result = place();
            expect(place(), result);
            expect(result.keys, avatars.keys);
            final rendered = <Rect>[];
            for (final entry in result.entries) {
              final placement = entry.value;
              final rect = placement.rect;
              expect(rect.top, greaterThanOrEqualTo(canvas.top));
              expect(rect.bottom, lessThanOrEqualTo(canvas.bottom + 0.001));
              expect(rect.left, greaterThanOrEqualTo(canvas.left));
              expect(rect.right, lessThanOrEqualTo(canvas.right + 0.001));
              if (placement.side == null) {
                expect(avatars[entry.key]!.contains(rect.center), isTrue);
                continue;
              }
              if (placement.compact) {
                expect(rect.width, lessThanOrEqualTo(96.001));
              }
              for (final obstacle in [
                ...avatars.values,
                ...obstacles,
                ...rendered,
              ]) {
                expect(rect.deflate(0.001).overlaps(obstacle), isFalse);
              }
              rendered.add(rect);
            }
            expect(rendered.length, lessThanOrEqualTo(4));
          },
        );
      }
    }
  }
}
