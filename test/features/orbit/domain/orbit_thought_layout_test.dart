import 'dart:ui';

import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart';
import 'package:flutter_app/features/orbit/domain/orbit_thought_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 390.0, 430.0]) {
    for (final noteHeight in [51.0, 90.0]) {
      test(
        '13 notes clear every face/self/note at width $width height $noteHeight',
        () {
          final seats = computeOrbitLayout(
            memberCount: 13,
            geometry: OrbitGeometryPrefs.defaults,
          ).seats;
          final sizes = {
            for (final seat in seats) seat.index: Size(150, noteHeight),
          };
          final positions = OrbitThoughtSwim().resolve(
            seats: seats,
            noteSizes: sizes,
            availableWidth: width,
            seconds: 0,
            motionEnabled: false,
          );
          final faces = {
            for (final seat in seats)
              seat.index: Rect.fromCenter(
                center: positions[seat.index]!,
                width: seat.avatarSize,
                height: seat.avatarSize,
              ),
          };
          final notes = {
            for (final seat in seats)
              seat.index: orbitThoughtNoteRect(
                positions[seat.index]!,
                seat.avatarSize,
                sizes[seat.index]!,
              ),
          };
          final self = Rect.fromCenter(
            center: Offset.zero,
            width: 48,
            height: 48,
          );
          for (final seat in seats) {
            final id = seat.index;
            expect(notes[id]!.overlaps(self), isFalse, reason: 'note $id/self');
            expect(faces[id]!.overlaps(self), isFalse, reason: 'face $id/self');
            expect(notes[id]!.left, greaterThanOrEqualTo(-width / 2 + 5.9));
            expect(notes[id]!.right, lessThanOrEqualTo(width / 2 - 5.9));
            for (final other in seats) {
              if (other.index == id) continue;
              expect(
                notes[id]!.overlaps(faces[other.index]!),
                isFalse,
                reason: 'note $id/face ${other.index}',
              );
              expect(
                notes[id]!.overlaps(notes[other.index]!),
                isFalse,
                reason: 'note $id/note ${other.index}',
              );
              expect(
                faces[id]!.overlaps(faces[other.index]!),
                isFalse,
                reason: 'face $id/face ${other.index}',
              );
            }
          }
        },
      );
    }
  }

  test(
    'Reduce Motion has no time/history dependence and never moves arc seats',
    () {
      final seats = computeOrbitLayout(
        memberCount: 20,
        geometry: OrbitGeometryPrefs.defaults,
      ).seats;
      final swim = OrbitThoughtSwim();
      Map<int, Offset> resolve(double seconds) => swim.resolve(
        seats: seats,
        noteSizes: const {0: Size(96, 51)},
        availableWidth: 390,
        seconds: seconds,
        motionEnabled: false,
      );
      final first = resolve(0);
      expect(resolve(400), first);
      expect(first.keys, everyElement(lessThan(13)));
    },
  );

  test(
    'notes-away rendering can use the unchanged original seat coordinates',
    () {
      final layout = computeOrbitLayout(
        memberCount: 13,
        geometry: OrbitGeometryPrefs.defaults,
      );
      final original = [
        for (final seat in layout.seats) Offset(seat.dx, seat.dy),
      ];
      final resolved = OrbitThoughtSwim().resolve(
        seats: layout.seats,
        noteSizes: const {0: Size(96, 51)},
        availableWidth: 390,
        seconds: 0,
        motionEnabled: false,
      );
      for (final seat in layout.seats) {
        expect(
          Offset.lerp(original[seat.index], resolved[seat.index], 0),
          original[seat.index],
        );
      }
    },
  );

  test('unconstrained normal motion stays nonzero and continuous', () {
    final seats = computeOrbitLayout(
      memberCount: 3,
      geometry: OrbitGeometryPrefs.defaults,
    ).seats;
    final swim = OrbitThoughtSwim();
    Map<int, Offset> resolve(int frame) => swim.resolve(
      seats: seats,
      noteSizes: const {},
      availableWidth: 1000,
      seconds: frame / 60,
      motionEnabled: true,
    );
    final first = resolve(0);
    var previous = first;
    var maximumDisplacement = 0.0;
    for (var frame = 1; frame <= 600; frame++) {
      final positions = resolve(frame);
      for (final seat in seats) {
        final position = positions[seat.index]!;
        final step = (position - previous[seat.index]!).distance;
        expect(
          step,
          lessThanOrEqualTo(0.5),
          reason: 'Unconstrained face ${seat.index} jumps at frame $frame',
        );
        final displacement = (position - first[seat.index]!).distance;
        if (displacement > maximumDisplacement) {
          maximumDisplacement = displacement;
        }
      }
      previous = positions;
    }
    expect(
      maximumDisplacement,
      greaterThan(0.5),
      reason: 'Freezing every face must not satisfy the stability regressions.',
    );
  });

  for (final width in [320.0, 390.0, 430.0]) {
    for (final noteHeight in [51.0, 90.0]) {
      test('normal motion preserves painted collision and bounds rules '
          'at width $width height $noteHeight', () {
        final seats = computeOrbitLayout(
          memberCount: 13,
          geometry: OrbitGeometryPrefs.defaults,
        ).seats;
        final sizes = <int, Size>{
          for (final seat in seats) seat.index: Size(150, noteHeight),
        };
        final selfNoteSize = Size(150, noteHeight);
        final swim = OrbitThoughtSwim();
        for (var frame = 0; frame <= 120; frame++) {
          final positions = swim.resolve(
            seats: seats,
            noteSizes: sizes,
            selfNoteSize: selfNoteSize,
            availableWidth: width,
            seconds: frame / 60,
            motionEnabled: true,
          );
          _expectPaintedGeometryClear(
            seats: seats,
            positions: positions,
            noteSizes: sizes,
            selfNoteSize: selfNoteSize,
            width: width,
            context: 'frame $frame width $width height $noteHeight',
          );
        }
      });
    }
  }
  test('equal rebuilt inputs and a clock restart do not reanchor avatars', () {
    final seats = computeOrbitLayout(
      memberCount: 11,
      geometry: OrbitGeometryPrefs.defaults,
    ).seats;
    final sizes = {for (final seat in seats) seat.index: const Size(150, 90)};
    final swim = OrbitThoughtSwim();
    Map<int, Offset> resolve(double seconds) => swim.resolve(
      seats: List.of(seats),
      noteSizes: Map.of(sizes),
      availableWidth: 320,
      seconds: seconds,
      motionEnabled: true,
    );
    var previous = resolve(0);
    for (var frame = 1; frame <= 300; frame++) {
      previous = resolve(frame / 60);
    }
    expect(resolve(0), previous);
    for (var frame = 1; frame <= 180; frame++) {
      final current = resolve(frame / 60);
      for (final seat in seats) {
        expect(
          (current[seat.index]! - previous[seat.index]!).distance,
          lessThanOrEqualTo(0.5),
          reason: 'Clock restart must not reselect a gap for ${seat.index}',
        );
      }
      previous = current;
    }
  });
}

void _expectPaintedGeometryClear({
  required List<OrbitSeat> seats,
  required Map<int, Offset> positions,
  required Map<int, Size> noteSizes,
  required Size selfNoteSize,
  required double width,
  required String context,
}) {
  final faces = <int, Rect>{
    for (final seat in seats)
      seat.index: Rect.fromCenter(
        center: positions[seat.index]!,
        width: seat.avatarSize,
        height: seat.avatarSize,
      ),
  };
  final notes = <int, Rect>{
    for (final seat in seats)
      seat.index: orbitThoughtNoteRect(
        positions[seat.index]!,
        seat.avatarSize,
        noteSizes[seat.index]!,
      ),
  };
  final self = Rect.fromCenter(center: Offset.zero, width: 48, height: 48);
  final centre = <Rect>[
    self,
    orbitThoughtNoteRect(Offset.zero, self.width, selfNoteSize),
  ];
  for (final seat in seats) {
    final id = seat.index;
    for (var index = 0; index < centre.length; index++) {
      expect(
        faces[id]!.overlaps(centre[index]),
        isFalse,
        reason: '$context: face $id/centre $index',
      );
      expect(
        notes[id]!.overlaps(centre[index]),
        isFalse,
        reason: '$context: note $id/centre $index',
      );
    }
    for (final shape in [faces[id]!, notes[id]!]) {
      expect(
        shape.left,
        greaterThanOrEqualTo(-width / 2 + 5.9),
        reason: '$context: shape $id left canvas bound',
      );
      expect(
        shape.right,
        lessThanOrEqualTo(width / 2 - 5.9),
        reason: '$context: shape $id right canvas bound',
      );
    }
    for (final other in seats) {
      if (other.index == id) continue;
      expect(
        notes[id]!.overlaps(faces[other.index]!),
        isFalse,
        reason: '$context: note $id/face ${other.index}',
      );
      expect(
        notes[id]!.overlaps(notes[other.index]!),
        isFalse,
        reason: '$context: note $id/note ${other.index}',
      );
      expect(
        faces[id]!.overlaps(faces[other.index]!),
        isFalse,
        reason: '$context: face $id/face ${other.index}',
      );
    }
  }
}
