import 'dart:math' as math;
import 'dart:ui';

const orbitThoughtTailSize = 11.0;
const orbitThoughtBadgeSize = 18.0;
const _maxPreviews = 4;
const _attachmentGap = 4.0;
const _maxAttachmentGap = 48.0;
const _previewClearance = 3.0;
const _roundingTolerance = 0.000001;

enum OrbitThoughtSide { above, below, right, left }

typedef OrbitThoughtSizes = ({Size full, Size compact});
typedef OrbitThoughtPlacement = ({
  Rect rect,
  OrbitThoughtSide? side,
  bool compact,
});

/// Places previews in priority order against the fixed avatar tap targets.
/// Sizes describe the bodies. Each candidate also reserves room for its tail.
Map<int, OrbitThoughtPlacement> layoutOrbitThoughts({
  required Rect canvas,
  required Map<int, Rect> avatars,
  required Map<int, OrbitThoughtSizes> previews,
  required bool mirrored,
  Iterable<Rect> otherObstacles = const [],
}) {
  final occupied = [...avatars.values, ...otherObstacles];
  final result = <int, OrbitThoughtPlacement>{};
  final sides = [
    OrbitThoughtSide.above,
    OrbitThoughtSide.below,
    if (mirrored) OrbitThoughtSide.left else OrbitThoughtSide.right,
    if (mirrored) OrbitThoughtSide.right else OrbitThoughtSide.left,
  ];
  var previewCount = 0;
  for (final entry in previews.entries) {
    final avatar = avatars[entry.key]!;
    OrbitThoughtPlacement? placement;
    if (previewCount < _maxPreviews) {
      for (final compact in [false, true]) {
        final body = compact ? entry.value.compact : entry.value.full;
        for (final side in sides) {
          final rect = _findPosition(
            canvas,
            occupied,
            avatar,
            body,
            side,
            mirrored,
          );
          if (rect == null) continue;
          placement = (rect: rect, side: side, compact: compact);
          occupied.add(rect.inflate(_previewClearance));
          previewCount++;
          break;
        }
        if (placement != null) break;
      }
    }

    result[entry.key] =
        placement ??
        (
          rect: orbitThoughtBadgeRect(canvas, avatar, mirrored),
          side: null,
          compact: false,
        );
  }
  return result;
}

Rect orbitThoughtBadgeRect(Rect canvas, Rect avatar, bool mirrored) {
  final left = mirrored
      ? avatar.left + 4
      : avatar.right - orbitThoughtBadgeSize - 4;
  final lastLeft = math.max(canvas.left, canvas.right - orbitThoughtBadgeSize);
  final lastTop = math.max(canvas.top, canvas.bottom - orbitThoughtBadgeSize);
  return Rect.fromLTWH(
    left.clamp(canvas.left, lastLeft).toDouble(),
    (avatar.top + 3).clamp(canvas.top, lastTop).toDouble(),
    orbitThoughtBadgeSize,
    orbitThoughtBadgeSize,
  );
}

Rect? _findPosition(
  Rect canvas,
  List<Rect> obstacles,
  Rect avatar,
  Size body,
  OrbitThoughtSide side,
  bool mirrored,
) {
  final vertical =
      side == OrbitThoughtSide.above || side == OrbitThoughtSide.below;
  final width = body.width + (vertical ? 0 : orbitThoughtTailSize);
  final height = body.height + (vertical ? orbitThoughtTailSize : 0);
  final crossLimit =
      (vertical ? avatar.width : avatar.height) / 2 + _attachmentGap;
  // A closest fit lies at the centered attachment or at a canvas/obstacle
  // edge. Trying those edges lets a preview slide around a neighboring face.
  final lefts = {
    avatar.center.dx - width / 2,
    avatar.left - _attachmentGap - width,
    avatar.right + _attachmentGap,
    canvas.left,
    canvas.right - width,
    for (final obstacle in obstacles) ...[
      obstacle.left - width,
      obstacle.right,
    ],
  }.toList()..sort((a, b) => mirrored ? b.compareTo(a) : a.compareTo(b));
  final tops = {
    avatar.center.dy - height / 2,
    avatar.top - _attachmentGap - height,
    avatar.bottom + _attachmentGap,
    canvas.top,
    canvas.bottom - height,
    for (final obstacle in obstacles) ...[
      obstacle.top - height,
      obstacle.bottom,
    ],
  };

  Rect? best;
  var bestDistance = double.infinity;
  var bestShift = double.infinity;
  for (final left in lefts) {
    if (left < canvas.left ||
        left + width > canvas.right + _roundingTolerance) {
      continue;
    }
    for (final top in tops) {
      if (top < canvas.top ||
          top + height > canvas.bottom + _roundingTolerance) {
        continue;
      }
      final rect = Rect.fromLTWH(left, top, width, height);
      final gap = switch (side) {
        OrbitThoughtSide.above => avatar.top - rect.bottom,
        OrbitThoughtSide.below => rect.top - avatar.bottom,
        OrbitThoughtSide.right => rect.left - avatar.right,
        OrbitThoughtSide.left => avatar.left - rect.right,
      };
      if (gap < _attachmentGap - _roundingTolerance ||
          gap > _maxAttachmentGap) {
        continue;
      }
      final crossGap = vertical
          ? _outside(avatar.center.dx, rect.left, rect.right)
          : _outside(avatar.center.dy, rect.top, rect.bottom);
      if (crossGap > crossLimit) continue;
      final distance = gap * gap + crossGap * crossGap;
      final shift = vertical
          ? (avatar.center.dx - rect.center.dx).abs()
          : (avatar.center.dy - rect.center.dy).abs();
      if (distance > bestDistance + _roundingTolerance ||
          ((distance - bestDistance).abs() < _roundingTolerance &&
              shift >= bestShift - _roundingTolerance) ||
          obstacles.any((obstacle) => _overlaps(rect, obstacle))) {
        continue;
      }
      best = rect;
      bestDistance = distance;
      bestShift = shift;
    }
  }
  return best;
}

double _outside(double p, double start, double end) =>
    math.max(0, math.max(start - p, p - end));

bool _overlaps(Rect a, Rect b) =>
    a.left < b.right - _roundingTolerance &&
    a.right > b.left + _roundingTolerance &&
    a.top < b.bottom - _roundingTolerance &&
    a.bottom > b.top + _roundingTolerance;
