import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart';

/// A note remains attached to the top of its owner's face throughout the swim.
Rect orbitThoughtNoteRect(Offset face, double faceSize, Size noteSize) =>
    Rect.fromLTWH(
      face.dx - noteSize.width / 2,
      face.dy - faceSize / 2 - noteSize.height,
      noteSize.width,
      noteSize.height,
    );

/// Session-local spring positions; the original seat engine remains unchanged.
///
/// The final projection separates the painted rectangles (including note tails),
/// rather than relying on a repulsion force that can settle with an overlap.
class OrbitThoughtSwim {
  final Map<int, Offset> _positions = {};
  final Map<int, Offset> _velocities = {};
  double? _lastSeconds;

  void clear() {
    _positions.clear();
    _velocities.clear();
    _lastSeconds = null;
  }

  Map<int, Offset> resolve({
    required List<OrbitSeat> seats,
    required Map<int, Size> noteSizes,
    required double availableWidth,
    required double seconds,
    required bool motionEnabled,
  }) {
    final rings = seats
        .where((seat) => seat.kind != OrbitSeatKind.arc)
        .toList();
    final byIndex = {for (final seat in rings) seat.index: seat};
    _positions.removeWhere((index, _) => !byIndex.containsKey(index));
    _velocities.removeWhere((index, _) => !byIndex.containsKey(index));
    final dt = _lastSeconds == null
        ? 1 / 60
        : (seconds - _lastSeconds!).clamp(0.0, 1 / 30).toDouble();
    _lastSeconds = seconds;
    for (final seat in rings) {
      final home = Offset(seat.dx, seat.dy) * 1.1;
      final drift = motionEnabled
          ? Offset(
              math.sin(seconds * 0.55 + seat.index * 1.7) * 4,
              math.cos(seconds * 0.45 + seat.index * 2.3) * 4,
            )
          : Offset.zero;
      final target = home + drift;
      if (!motionEnabled || !_positions.containsKey(seat.index)) {
        _positions[seat.index] = target;
        _velocities[seat.index] = Offset.zero;
      } else {
        final velocity =
            (_velocities[seat.index]! +
                (target - _positions[seat.index]!) * (14 * dt)) *
            math.exp(-5 * dt);
        _velocities[seat.index] = velocity;
        _positions[seat.index] = _positions[seat.index]! + velocity * dt;
      }
    }

    // Horizontal bounds follow the real canvas. Vertical space can grow, which
    // is necessary when a large text scaler makes all thirteen notes taller.
    final halfWidth = math.max(64.0, availableWidth / 2 - 6);
    Rect face(int index) => Rect.fromCenter(
      center: _positions[index]!,
      width: byIndex[index]!.avatarSize,
      height: byIndex[index]!.avatarSize,
    );
    Rect note(int index) => orbitThoughtNoteRect(
      _positions[index]!,
      byIndex[index]!.avatarSize,
      noteSizes[index]!,
    );
    void move(int index, Offset delta) {
      _positions[index] = _positions[index]! + delta;
    }

    Offset separation(Rect a, Rect b, int first, int second) {
      final overlap = a.inflate(3).intersect(b.inflate(3));
      if (overlap.width <= 0 || overlap.height <= 0) return Offset.zero;
      final horizontal = overlap.width < overlap.height;
      if (horizontal) {
        final sign = a.center.dx == b.center.dx
            ? (first < second ? -1.0 : 1.0)
            : (a.center.dx < b.center.dx ? -1.0 : 1.0);
        final dx = sign * (overlap.width + 0.1);
        // Prefer vertical separation if horizontal movement would be pinned at
        // the canvas edge. This also keeps long notes fully tappable.
        if ((a.center.dx + dx).abs() + a.width / 2 < halfWidth) {
          return Offset(dx, 0);
        }
      }
      final sign = a.center.dy == b.center.dy
          ? (first < second ? -1.0 : 1.0)
          : (a.center.dy < b.center.dy ? -1.0 : 1.0);
      return Offset(0, sign * (overlap.height + 0.1));
    }

    final self = Rect.fromCenter(center: Offset.zero, width: 48, height: 48);
    // Projection is deterministic under Reduce Motion; it does not depend on
    // ticker history and never schedules an animation.
    for (var iteration = 0; iteration < 160; iteration++) {
      var moved = false;
      for (final a in rings) {
        final index = a.index;
        final ownHalf =
            math.max(a.avatarSize, noteSizes[index]?.width ?? 0) / 2;
        final x = _positions[index]!.dx.clamp(
          -halfWidth + ownHalf,
          halfWidth - ownHalf,
        );
        _positions[index] = Offset(x.toDouble(), _positions[index]!.dy);
        var delta = separation(face(index), self, index, -1);
        if (delta != Offset.zero) {
          move(index, delta);
          moved = true;
        }
        if (noteSizes.containsKey(index)) {
          delta = separation(note(index), self, index, -1);
          if (delta != Offset.zero) {
            move(index, delta);
            moved = true;
          }
        }
        for (final b in rings) {
          if (b.index <= index) continue;
          delta = separation(face(index), face(b.index), index, b.index);
          if (delta != Offset.zero) {
            move(index, delta / 2);
            move(b.index, -delta / 2);
            moved = true;
          }
        }
        if (!noteSizes.containsKey(index)) continue;
        for (final b in rings) {
          if (b.index == index) continue;
          delta = separation(note(index), face(b.index), index, b.index);
          if (delta != Offset.zero) {
            move(index, delta / 2);
            move(b.index, -delta / 2);
            moved = true;
          }
          if (b.index > index && noteSizes.containsKey(b.index)) {
            delta = separation(note(index), note(b.index), index, b.index);
            if (delta != Offset.zero) {
              move(index, delta / 2);
              move(b.index, -delta / 2);
              moved = true;
            }
          }
        }
      }
      if (!moved) break;
    }
    return Map<int, Offset>.unmodifiable(_positions);
  }
}
