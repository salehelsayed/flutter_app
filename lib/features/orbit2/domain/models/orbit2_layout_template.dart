import 'dart:math';

import 'package:flutter/widgets.dart';

import 'avatar_tier.dart';

/// Default arrangements for the floating avatar canvas. The user can drag freely
/// afterwards; this is only the template they begin in (and can switch between).
///
/// [unifiedCircle] is special: it has NO floating canvas at all — every contact
/// (inner circle + the would-be floating friends & groups) collapses into a
/// single Inner Circle. The canvas renders that directly and never calls
/// [layoutPositions] for it.
enum Orbit2LayoutTemplate {
  innerGravity,
  nebulaScatter,
  looseHoneycomb,
  tieredBands,
  unifiedCircle,
}

/// Minimum gap added on top of the two avatars' radii when spacing them apart.
const double _kPairGap = 12;

/// Centre-to-centre spacing when name labels are shown (so the labels under
/// adjacent avatars get breathing room) vs hidden (avatar-only).
const double kNamedSpacing = 76;
const double kBareSpacing = 54;

/// Magnet repulsion: pushes [home] out of the circular exclusion zone of
/// [radius] around [center] (the Inner Circle). Outside the zone the point is
/// unchanged; inside it is snapped to the zone boundary; a point exactly at the
/// centre is pushed straight down by [radius]. Deterministic.
Offset repel(Offset home, Offset center, double radius) {
  final v = home - center;
  final d = v.distance;
  if (d >= radius) return home;
  if (d < 0.0001) return center + Offset(0, radius);
  return center + (v / d) * radius;
}

/// Returns one [Offset] per [tiers] entry — the avatar CENTERS in canvas
/// coordinates — for the given [template]. Deterministic (no `Random`): same
/// inputs always yield identical output. A relaxation pass guarantees no two
/// avatars overlap (center distance >= rᵢ+rⱼ+12, i.e. >= 56px even for two
/// Size-B) and that every center stays inside [canvas] inset by [margin].
List<Offset> layoutPositions(
  Orbit2LayoutTemplate template, {
  required Size canvas,
  required List<AvatarTier> tiers,
  double margin = 44,
  Offset? exclusionCenter,
  double exclusionRadius = 0,
  double minSpacing = 0,
}) {
  final n = tiers.length;
  if (n == 0) return const <Offset>[];

  final w = canvas.width;
  final h = canvas.height;
  final left = margin;
  final right = max(margin + 1, w - margin);
  final top = margin;
  final bottom = max(top + 1, h - margin);
  final usableW = right - left;
  final usableH = bottom - top;
  final cx = w / 2;

  final aIdx = <int>[];
  final bIdx = <int>[];
  for (var i = 0; i < n; i++) {
    (tiers[i] == AvatarTier.sizeA ? aIdx : bIdx).add(i);
  }

  final seed = List<Offset>.filled(n, Offset.zero);

  switch (template) {
    case Orbit2LayoutTemplate.innerGravity:
      // Size-A clustered high-center (hugging the Inner Circle); Size-B on a
      // wide ring around the canvas centre, so A is clearly closer to centre.
      final clusterCenter = Offset(cx, top + usableH * 0.40);
      for (var k = 0; k < aIdx.length; k++) {
        final r = 14.0 + 26.0 * sqrt(k / max(1, aIdx.length));
        final a = k * 2.399963; // golden angle
        seed[aIdx[k]] = clusterCenter + Offset(cos(a) * r, sin(a) * r * 0.9);
      }
      final ringCenter = Offset(cx, top + usableH * 0.5);
      for (var k = 0; k < bIdx.length; k++) {
        final a = (k / max(1, bIdx.length)) * 2 * pi - pi / 2;
        seed[bIdx[k]] =
            ringCenter + Offset(cos(a) * usableW * 0.44, sin(a) * usableH * 0.40);
      }
      break;

    case Orbit2LayoutTemplate.tieredBands:
      for (var k = 0; k < aIdx.length; k++) {
        final x = left + usableW * ((k + 0.5) / max(1, aIdx.length));
        seed[aIdx[k]] = Offset(x, top + usableH * 0.22);
      }
      final cols = max(1, (usableW / 64).floor());
      for (var k = 0; k < bIdx.length; k++) {
        final row = k ~/ cols;
        final col = k % cols;
        final x = left + usableW * ((col + 0.5) / cols);
        final y = top + usableH * (0.64 + row * 0.16);
        seed[bIdx[k]] = Offset(x, min(bottom, y));
      }
      break;

    case Orbit2LayoutTemplate.looseHoneycomb:
      final cols = max(1, (usableW / 64).floor());
      for (var i = 0; i < n; i++) {
        final row = i ~/ cols;
        final col = i % cols;
        final stagger = row.isEven ? 0.0 : 0.5;
        final x = left + usableW * ((col + stagger + 0.5) / (cols + 1));
        final y = top + (row + 0.6) * 64;
        seed[i] = Offset(x, min(bottom, y));
      }
      break;

    case Orbit2LayoutTemplate.nebulaScatter:
    // [unifiedCircle] never reaches here (the canvas renders one Inner Circle
    // instead of a floating layout); the shared body just keeps the switch
    // exhaustive with a deterministic fallback.
    case Orbit2LayoutTemplate.unifiedCircle:
      // Deterministic low-discrepancy scatter (golden-ratio sequences).
      for (var i = 0; i < n; i++) {
        final fx = (i * 0.6180339887498949) % 1.0;
        final fy = (i * 0.7548776662466927 + 0.13) % 1.0;
        seed[i] = Offset(left + fx * usableW, top + fy * usableH);
      }
      break;
  }

  return _relax(
    seed,
    tiers: tiers,
    left: left,
    right: right,
    top: top,
    bottom: bottom,
    bandLock: template == Orbit2LayoutTemplate.tieredBands,
    exclusionCenter: exclusionCenter,
    exclusionRadius: exclusionRadius,
    minSpacing: minSpacing,
  );
}

List<Offset> _relax(
  List<Offset> input, {
  required List<AvatarTier> tiers,
  required double left,
  required double right,
  required double top,
  required double bottom,
  required bool bandLock,
  Offset? exclusionCenter,
  double exclusionRadius = 0,
  double minSpacing = 0,
}) {
  final n = input.length;
  final pos = List<Offset>.of(input);
  final usableH = bottom - top;
  final hasExclusion = exclusionCenter != null && exclusionRadius > 0;

  for (var iter = 0; iter < 460; iter++) {
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final minSep =
            max(tiers[i].radius + tiers[j].radius + _kPairGap, minSpacing);
        var d = pos[j] - pos[i];
        var dist = d.distance;
        if (dist < 0.0001) {
          // Deterministic nudge for coincident points.
          d = Offset(0.5 + (i % 3) * 0.1, 0.4 + (j % 3) * 0.1);
          dist = d.distance;
        }
        if (dist < minSep) {
          final push = (minSep - dist) / 2;
          final dir = d / dist;
          pos[i] -= dir * push;
          pos[j] += dir * push;
        }
      }
    }
    for (var i = 0; i < n; i++) {
      // Keep clear of the Inner Circle's exclusion zone (push to its boundary,
      // leaving room for the avatar's own radius).
      if (hasExclusion) {
        pos[i] = repel(pos[i], exclusionCenter, exclusionRadius + tiers[i].radius);
      }
      var y = pos[i].dy;
      if (bandLock) {
        if (tiers[i] == AvatarTier.sizeA) {
          y = y.clamp(top, top + usableH * 0.42);
        } else {
          y = y.clamp(top + usableH * 0.52, bottom);
        }
      } else {
        y = y.clamp(top, bottom);
      }
      pos[i] = Offset(pos[i].dx.clamp(left, right), y);
    }
  }
  return pos;
}
