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

/// Stable collision anchors with bounded drift; the seat engine is unchanged.
///
/// The final projection separates the painted rectangles (including note tails),
/// rather than relying on a repulsion force that can settle with an overlap.
/// The self face and the user's own note ([selfNoteSize]) never move; ring
/// faces and notes are projected clear of both.
class OrbitThoughtSwim {
  final Map<int, Offset> _positions = {};
  final Map<int, Offset> _velocities = {};
  double? _lastSeconds;
  List<double>? _layoutInputs;
  final Map<int, Offset> _anchors = {};
  final Map<int, Offset> _motionOrigins = {};
  final Map<int, Rect> _translationBounds = {};

  void clear() {
    _positions.clear();
    _velocities.clear();
    _lastSeconds = null;
    _layoutInputs = null;
    _anchors.clear();
    _motionOrigins.clear();
    _translationBounds.clear();
  }

  Map<int, Offset> resolve({
    required List<OrbitSeat> seats,
    required Map<int, Size> noteSizes,
    Size? selfNoteSize,
    required double availableWidth,
    required double seconds,
    required bool motionEnabled,
  }) {
    final rings = seats
        .where((seat) => seat.kind != OrbitSeatKind.arc)
        .toList();
    final byIndex = {for (final seat in rings) seat.index: seat};
    final inputs = <double>[
      availableWidth,
      motionEnabled ? 1 : 0,
      selfNoteSize?.width ?? -1,
      selfNoteSize?.height ?? -1,
      for (final seat in rings) ...[
        seat.index.toDouble(),
        seat.kind.index.toDouble(),
        seat.dx,
        seat.dy,
        seat.avatarSize,
        noteSizes[seat.index]?.width ?? -1,
        noteSizes[seat.index]?.height ?? -1,
      ],
    ];
    final sameLayout = _sameLayout(inputs);
    if (!sameLayout) clear();
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

    // Animation ticks must not choose a new discrete collision gap. Resolve
    // the existing layout only when its geometric inputs actually change.
    if (sameLayout) return _animatedPositions();
    final projectedPositions = Map<int, Offset>.of(_positions);
    // Horizontal bounds follow the real canvas. Vertical space can grow, which
    // is necessary when a large text scaler makes all thirteen notes taller.
    final halfWidth = math.max(64.0, availableWidth / 2 - 6);
    Rect face(int index) => Rect.fromCenter(
      center: projectedPositions[index]!,
      width: byIndex[index]!.avatarSize,
      height: byIndex[index]!.avatarSize,
    );
    Rect note(int index) => orbitThoughtNoteRect(
      projectedPositions[index]!,
      byIndex[index]!.avatarSize,
      noteSizes[index]!,
    );
    void move(int index, Offset delta) {
      projectedPositions[index] = projectedPositions[index]! + delta;
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
    final centre = <Rect>[
      self,
      if (selfNoteSize != null)
        orbitThoughtNoteRect(Offset.zero, self.width, selfNoteSize),
    ];
    // Projection is deterministic under Reduce Motion; it does not depend on
    // ticker history and never schedules an animation.
    for (var iteration = 0; iteration < 160; iteration++) {
      var moved = false;
      for (final a in rings) {
        final index = a.index;
        final ownHalf =
            math.max(a.avatarSize, noteSizes[index]?.width ?? 0) / 2;
        final x = projectedPositions[index]!.dx.clamp(
          -halfWidth + ownHalf,
          halfWidth - ownHalf,
        );
        projectedPositions[index] = Offset(
          x.toDouble(),
          projectedPositions[index]!.dy,
        );
        Offset delta;
        for (final obstacle in centre) {
          delta = separation(face(index), obstacle, index, -1);
          if (delta != Offset.zero) {
            move(index, delta);
            moved = true;
          }
          if (noteSizes.containsKey(index)) {
            delta = separation(note(index), obstacle, index, -1);
            if (delta != Offset.zero) {
              move(index, delta);
              moved = true;
            }
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

    // Pair corrections can reintroduce a collision with a previously visited
    // neighbour, especially at a horizontal bound. Finish in seat order and
    // choose the nearest clear vertical position against the already fixed
    // shapes. Candidate boundaries include a position above/below every shape,
    // so this also resolves dense layouts without an iteration-count guess.
    final fixed = <Rect>[...centre];
    for (final seat in rings) {
      final index = seat.index;
      final ownHalf =
          math.max(seat.avatarSize, noteSizes[index]?.width ?? 0) / 2;
      final position = projectedPositions[index]!;
      final x = position.dx
          .clamp(-halfWidth + ownHalf, halfWidth - ownHalf)
          .toDouble();
      final shapes = <Rect>[
        Rect.fromCenter(
          center: Offset.zero,
          width: seat.avatarSize,
          height: seat.avatarSize,
        ),
        if (noteSizes.containsKey(index))
          orbitThoughtNoteRect(Offset.zero, seat.avatarSize, noteSizes[index]!),
      ];
      final candidates = <double>{position.dy};
      for (final obstacle in fixed) {
        for (final shape in shapes) {
          candidates.add(obstacle.top - shape.bottom - 6.1);
          candidates.add(obstacle.bottom - shape.top + 6.1);
        }
      }
      final ordered = candidates.toList()
        ..sort((a, b) {
          final distance = (a - position.dy).abs().compareTo(
            (b - position.dy).abs(),
          );
          return distance == 0 ? a.compareTo(b) : distance;
        });
      final y = ordered.firstWhere((candidate) {
        final offset = Offset(x, candidate);
        return shapes.every(
          (shape) => fixed.every(
            (obstacle) =>
                !shape.shift(offset).inflate(3).overlaps(obstacle.inflate(3)),
          ),
        );
      });
      projectedPositions[index] = Offset(x, y);
      fixed.addAll(
        shapes.map((shape) => shape.shift(projectedPositions[index]!)),
      );
    }
    _anchors.addAll(projectedPositions);
    _motionOrigins.addAll(_positions);
    _translationBounds.addAll(
      _boundsFor(rings, noteSizes, selfNoteSize, availableWidth),
    );
    _layoutInputs = inputs;
    return _animatedPositions();
  }

  bool _sameLayout(List<double> inputs) {
    final previous = _layoutInputs;
    if (previous == null || previous.length != inputs.length) return false;
    for (var index = 0; index < inputs.length; index++) {
      if (previous[index] != inputs[index]) return false;
    }
    return true;
  }

  Map<int, Offset> _animatedPositions() => Map<int, Offset>.unmodifiable({
    for (final entry in _anchors.entries)
      entry.key: entry.value + _boundedTranslation(entry.key),
  });

  Offset _boundedTranslation(int index) {
    final delta = _positions[index]! - _motionOrigins[index]!;
    final bounds = _translationBounds[index]!;
    return Offset(
      delta.dx.clamp(bounds.left, bounds.right).toDouble(),
      delta.dy.clamp(bounds.top, bounds.bottom).toDouble(),
    );
  }

  Map<int, Rect> _boundsFor(
    List<OrbitSeat> seats,
    Map<int, Size> noteSizes,
    Size? selfNoteSize,
    double availableWidth,
  ) {
    const infinity = double.infinity;
    final halfWidth = math.max(64.0, availableWidth / 2 - 6);
    final bounds = <int, Rect>{
      for (final seat in seats)
        seat.index: Rect.fromLTRB(
          -halfWidth +
              math.max(seat.avatarSize, noteSizes[seat.index]?.width ?? 0) / 2 -
              _anchors[seat.index]!.dx,
          -infinity,
          halfWidth -
              math.max(seat.avatarSize, noteSizes[seat.index]?.width ?? 0) / 2 -
              _anchors[seat.index]!.dx,
          infinity,
        ),
    };
    final self = Rect.fromCenter(center: Offset.zero, width: 48, height: 48);
    final shapes = <int, List<Rect>>{
      -1: [
        self.inflate(3),
        if (selfNoteSize != null)
          orbitThoughtNoteRect(
            Offset.zero,
            self.width,
            selfNoteSize,
          ).inflate(3),
      ],
      for (final seat in seats)
        seat.index: [
          Rect.fromCenter(
            center: _anchors[seat.index]!,
            width: seat.avatarSize,
            height: seat.avatarSize,
          ).inflate(3),
          if (noteSizes.containsKey(seat.index))
            orbitThoughtNoteRect(
              _anchors[seat.index]!,
              seat.avatarSize,
              noteSizes[seat.index]!,
            ).inflate(3),
        ],
    };
    void limitX(int index, double lower, double upper) {
      final current = bounds[index];
      if (current == null) return; // The self face/note never moves.
      bounds[index] = Rect.fromLTRB(
        math.max(current.left, lower),
        current.top,
        math.min(current.right, upper),
        current.bottom,
      );
    }

    void limitY(int index, double lower, double upper) {
      final current = bounds[index];
      if (current == null) return;
      bounds[index] = Rect.fromLTRB(
        current.left,
        math.max(current.top, lower),
        current.right,
        math.min(current.bottom, upper),
      );
    }

    final owners = shapes.entries.toList();
    for (var first = 0; first < owners.length; first++) {
      for (var second = first + 1; second < owners.length; second++) {
        final aOwner = owners[first], bOwner = owners[second];
        for (final a in aOwner.value) {
          for (final b in bOwner.value) {
            final leftGap = b.left - a.right;
            final rightGap = a.left - b.right;
            final topGap = b.top - a.bottom;
            final bottomGap = a.top - b.bottom;
            final horizontalGap = math.max(leftGap, rightGap);
            final verticalGap = math.max(topGap, bottomGap);
            final share = aOwner.key == -1 || bOwner.key == -1 ? 1.0 : 0.5;
            // Keep one separating axis fixed for the lifetime of this layout.
            // Both moving owners share its spare clearance; using the full gap
            // for each would permit their face/note rectangles to collide.
            if (horizontalGap >= verticalGap) {
              final allowance = math.max(0.0, horizontalGap) * share;
              if (leftGap >= rightGap) {
                limitX(aOwner.key, -infinity, allowance);
                limitX(bOwner.key, -allowance, infinity);
              } else {
                limitX(aOwner.key, -allowance, infinity);
                limitX(bOwner.key, -infinity, allowance);
              }
            } else {
              final allowance = math.max(0.0, verticalGap) * share;
              if (topGap >= bottomGap) {
                limitY(aOwner.key, -infinity, allowance);
                limitY(bOwner.key, -allowance, infinity);
              } else {
                limitY(aOwner.key, -allowance, infinity);
                limitY(bOwner.key, -infinity, allowance);
              }
            }
          }
        }
      }
    }
    return bounds;
  }
}
