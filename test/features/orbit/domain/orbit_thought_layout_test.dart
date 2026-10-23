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
}
