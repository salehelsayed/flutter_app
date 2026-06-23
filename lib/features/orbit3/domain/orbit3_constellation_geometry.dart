import 'dart:math';

import 'package:flutter/material.dart' show Color, Offset;

import 'orbit3_connection_profile.dart';

/// The three deterministic constellation modes — same data, three distinct
/// organizing metaphors:
///   * [zodiac]  — a fixed horoscope dial: angle = when you met, radius = closeness.
///   * [galaxy]  — an Archimedean spiral timeline; reciprocity bulges the arm.
///   * [gravity] — a nested solar system; intro-members orbit their introducer.
enum Orbit3ConstellationMode { zodiac, galaxy, gravity }

/// The intrinsic square the constellation paints into (FittedBox scales it to
/// any screen, mirroring the One Circle's fixed-box approach).
const double kOrbit3ConstellationBox = 360;

// --- Galaxy spiral constants (the painter redraws the guide arm from these) ---
const double kGalaxyTurns = 2.0;
const double kGalaxyTheta0 = -pi / 2;
const double kGalaxyRCore = 0.12; // × box
const double kGalaxyRRim = 0.45; // × box
const double kGalaxyBulge = 0.05; // × box

/// One placed member: its [pos] is relative to the box CENTER (add center to get
/// canvas coords). The widget reads [avDiam] to size the avatar; the painter
/// reads [glowRadius]/[glowAlpha]/[hue]/[opacity] for the star glow.
class Orbit3Placement {
  final Orbit3Drivers driver;
  final Offset pos; // relative to center
  final double avDiam; // avatar widget diameter
  final double glowRadius; // painted glow disc radius
  final double glowAlpha; // base glow alpha (twinkle multiplies this)
  final Color hue;
  final double opacity; // overall member opacity (galaxy recency dim)

  const Orbit3Placement({
    required this.driver,
    required this.pos,
    required this.avDiam,
    required this.glowRadius,
    required this.glowAlpha,
    required this.hue,
    required this.opacity,
  });

  String get id => driver.id;
}

/// A drawn edge between two placements (both center-relative). [isIntro] picks
/// the visual: a personal spoke from You, or an intro arc/tether to an
/// introducer.
class Orbit3Connector {
  final Offset from;
  final Offset to;
  final bool isIntro;
  final Color color;
  final double alpha;

  const Orbit3Connector({
    required this.from,
    required this.to,
    required this.isIntro,
    required this.color,
    required this.alpha,
  });
}

/// The fully-computed constellation for one population + mode. Both the widget
/// (avatars) and the painter (glow/connectors) consume this same object.
class Orbit3ConstellationGeometry {
  final double box;
  final Orbit3ConstellationMode mode;
  final List<Orbit3Placement> placements; // render order (acquaintance order)
  final Map<String, Orbit3Placement> byId;
  final List<Orbit3Connector> connectors;

  const Orbit3ConstellationGeometry({
    required this.box,
    required this.mode,
    required this.placements,
    required this.byId,
    required this.connectors,
  });
}

/// Pure: maps a normalized driver set to drawable geometry for [mode]. A
/// per-user rotation seed ([userSeed], typically the viewer's own peerId) gives
/// two users with the same archetype a subtly different fingerprint without
/// disturbing the macro structure.
Orbit3ConstellationGeometry computeOrbit3Constellation({
  required Orbit3DriverSet set,
  required Orbit3ConstellationMode mode,
  double box = kOrbit3ConstellationBox,
  String? userSeed,
}) {
  final userRot =
      userSeed == null ? 0.0 : (orbit3Hash01(userSeed, 99) - 0.5) * 0.5;
  switch (mode) {
    case Orbit3ConstellationMode.zodiac:
      return _zodiac(set, box, userSeed, userRot);
    case Orbit3ConstellationMode.galaxy:
      return _galaxy(set, box, userSeed, userRot);
    case Orbit3ConstellationMode.gravity:
      return _gravity(set, box, userSeed, userRot);
  }
}

int _salt(String? userSeed, int base) =>
    userSeed == null ? base : base + (orbit3Hash(userSeed, 1) & 0xffff);

// ============================ ZODIAC ============================
// Angle = meeting-order rank around a clock (oldest at 12 o'clock, clockwise);
// radius = closeness inverted (chatty+recent sit inward near You).
Orbit3ConstellationGeometry _zodiac(
    Orbit3DriverSet set, double box, String? userSeed, double userRot) {
  final rMax = box / 2 - 26;
  final n = set.n;
  final placements = <Orbit3Placement>[];
  final byId = <String, Orbit3Placement>{};
  final connectors = <Orbit3Connector>[];
  final jitterSalt = _salt(userSeed, 7);

  // Min-max normalize closeness so the radial axis ALWAYS uses its full range —
  // otherwise a tightly-clustered population collapses into a single ring (the
  // "it's just one ring" problem). The closest friend lands inner, the most
  // distant on the rim, with everyone spread between.
  var cMin = 1.0;
  var cMax = 0.0;
  for (final d in set.drivers) {
    cMin = min(cMin, d.closeness);
    cMax = max(cMax, d.closeness);
  }
  final cSpan = (cMax - cMin) < 1e-6 ? 1.0 : (cMax - cMin);

  for (final d in set.drivers) {
    final order = d.profile.acquaintanceOrder;
    final frac = n <= 0 ? 0.0 : (order - 1) / n; // /n avoids first/last overlap
    final jitterDeg = ((orbit3Hash(d.id, jitterSalt) % 400) / 100.0) - 2.0;
    final theta = (-90.0 + 360.0 * frac + jitterDeg) * pi / 180.0;
    final cn = ((d.closeness - cMin) / cSpan).clamp(0.0, 1.0); // 1 = closest
    // A little hash jitter gives equal-closeness members ring thickness instead
    // of perfectly overlapping.
    final rJit = (orbit3Hash01(d.id, 23) - 0.5) * 0.06;
    final r = rMax * (0.30 + 0.60 * (1.0 - cn) + rJit).clamp(0.26, 0.96);
    final pos = Offset(cos(theta) * r, sin(theta) * r);
    // Smaller avatars so the concentric depth reads instead of merging.
    final avDiam = (18.0 + 16.0 * d.magnitude).clamp(18.0, 34.0);

    final pl = Orbit3Placement(
      driver: d,
      pos: pos,
      avDiam: avDiam,
      glowRadius: avDiam * 0.5 + 4 + 8 * d.magnitude,
      glowAlpha: 0.18 + 0.55 * cn, // closer = brighter
      hue: d.reciprocityHue,
      opacity: 1.0,
    );
    placements.add(pl);
    byId[d.id] = pl;

    // Intro lineage only: personal-add stars sit on the timeline thread with no
    // spoke (the sunburst of spokes was adding to the "blob" look).
    final p = d.profile;
    if (p.origin == Orbit3Origin.intro &&
        p.introducerId != null &&
        byId.containsKey(p.introducerId)) {
      connectors.add(Orbit3Connector(
          from: byId[p.introducerId]!.pos,
          to: pos,
          isIntro: true,
          color: d.reciprocityHue,
          alpha: 0.18));
    }
  }
  return Orbit3ConstellationGeometry(
      box: box,
      mode: Orbit3ConstellationMode.zodiac,
      placements: placements,
      byId: byId,
      connectors: connectors);
}

// ============================ GALAXY ============================
// Archimedean spiral by acquaintance order; reciprocity offsets each star
// perpendicular to the arm (talkers bulge one flank, listeners the other).
Orbit3ConstellationGeometry _galaxy(
    Orbit3DriverSet set, double box, String? userSeed, double userRot) {
  final placements = <Orbit3Placement>[];
  final byId = <String, Orbit3Placement>{};
  final connectors = <Orbit3Connector>[];
  final jitterSalt = _salt(userSeed, 5);

  for (final d in set.drivers) {
    final t = d.orderT;
    final theta = kGalaxyTheta0 +
        2 * pi * kGalaxyTurns * t +
        (orbit3Hash01(d.id, jitterSalt) - 0.5) * 0.08 +
        userRot;
    final rArm = (kGalaxyRCore + (kGalaxyRRim - kGalaxyRCore) * t) * box;
    final signed = (d.reciprocity - 0.5) * 2.0;
    final off = signed * kGalaxyBulge * box;
    final perp = theta + pi / 2;
    final pos = Offset(
      cos(theta) * rArm + cos(perp) * off,
      sin(theta) * rArm + sin(perp) * off,
    );
    final avDiam = 13.0 + 17.0 * d.magnitude; // smaller so the arm reads through
    final opacity = 0.45 + 0.55 * d.recencyT; // fresh = bright, stale = dim

    final pl = Orbit3Placement(
      driver: d,
      pos: pos,
      avDiam: avDiam,
      glowRadius: avDiam * 0.5 + 4 + 10 * d.magnitude,
      glowAlpha: 0.20 + 0.55 * d.closeness,
      hue: d.reciprocityHue,
      opacity: opacity,
    );
    placements.add(pl);
    byId[d.id] = pl;

    final p = d.profile;
    if (p.origin == Orbit3Origin.intro &&
        p.introducerId != null &&
        byId.containsKey(p.introducerId)) {
      connectors.add(Orbit3Connector(
          from: pos,
          to: byId[p.introducerId]!.pos,
          isIntro: true,
          color: d.reciprocityHue,
          alpha: 0.22));
    }
  }
  return Orbit3ConstellationGeometry(
      box: box,
      mode: Orbit3ConstellationMode.galaxy,
      placements: placements,
      byId: byId,
      connectors: connectors);
}

/// The smooth spiral guide arm (center-relative), sampled finely so the painter
/// can stroke the timeline even where stars are sparse. Uses the same constants
/// as [_galaxy] so guide and stars share one arm.
List<Offset> orbit3GalaxyGuide(double box, {int steps = 180}) {
  final out = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final theta = kGalaxyTheta0 + 2 * pi * kGalaxyTurns * t;
    final rArm = (kGalaxyRCore + (kGalaxyRRim - kGalaxyRCore) * t) * box;
    out.add(Offset(cos(theta) * rArm, sin(theta) * rArm));
  }
  return out;
}

// ============================ GRAVITY ============================
// "You" is the sun; radius = closeness inverted; intro-members are captured
// MOONS orbiting their introducer planet rather than the sun.
Orbit3ConstellationGeometry _gravity(
    Orbit3DriverSet set, double box, String? userSeed, double userRot) {
  final rMin = box * 0.17;
  final rMax = box * 0.46;
  final placements = <Orbit3Placement>[];
  final byId = <String, Orbit3Placement>{};
  final connectors = <Orbit3Connector>[];
  final scatterSalt = _salt(userSeed, 17);

  // First pass: how many moons each introducer captures, so siblings can fan
  // evenly around the parent instead of colliding.
  final moonsPerParent = <String, int>{};
  for (final d in set.drivers) {
    final p = d.profile;
    if (p.origin == Orbit3Origin.intro && p.introducerId != null) {
      moonsPerParent.update(p.introducerId!, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  final moonAssigned = <String, int>{};

  for (final d in set.drivers) {
    final p = d.profile;
    final baseSize = 18.0 + sqrt(d.magnitude) * (46.0 - 18.0);
    final isMoon = p.origin == Orbit3Origin.intro &&
        p.introducerId != null &&
        byId.containsKey(p.introducerId);

    if (!isMoon) {
      // A planet orbiting the sun. Angle is a deterministic hash scatter
      // (semantically empty — just spreads planets evenly).
      final thetaDeg = (orbit3Hash(d.id, scatterSalt) % 3600) / 10.0;
      final theta = (thetaDeg - 90.0) * pi / 180.0 + userRot;
      final radius = rMin + (1.0 - d.closeness) * (rMax - rMin);
      final pos = Offset(cos(theta) * radius, sin(theta) * radius);
      final size = baseSize.clamp(18.0, 46.0);
      final pl = Orbit3Placement(
        driver: d,
        pos: pos,
        avDiam: size,
        glowRadius: size * 0.6 + d.magnitude * 8,
        glowAlpha: 0.25 + 0.55 * d.magnitude,
        hue: d.reciprocityHue,
        opacity: 1.0,
      );
      placements.add(pl);
      byId[d.id] = pl;
    } else {
      final introId = p.introducerId!;
      final parent = byId[introId]!;
      final cnt = moonsPerParent[introId] ?? 1;
      final idx = moonAssigned[introId] ?? 0;
      moonAssigned[introId] = idx + 1;
      final moonSize = (baseSize * 0.7).clamp(14.0, 40.0);
      // Ring the moons around the parent; widen the ring when many siblings.
      final ringBase = 16 + parent.avDiam / 2 + moonSize / 2;
      final crowd = (cnt * moonSize * 0.55) / (2 * pi);
      final moonR = max(ringBase, crowd);
      final moonTheta =
          2 * pi * idx / cnt + orbit3Hash01(d.id, 0x9E37) * 0.5;
      final pos = parent.pos + Offset(cos(moonTheta), sin(moonTheta)) * moonR;
      final pl = Orbit3Placement(
        driver: d,
        pos: pos,
        avDiam: moonSize,
        glowRadius: moonSize * 0.6 + d.magnitude * 6,
        glowAlpha: 0.25 + 0.55 * d.magnitude,
        hue: d.reciprocityHue,
        opacity: 1.0,
      );
      placements.add(pl);
      byId[d.id] = pl;
      connectors.add(Orbit3Connector(
          from: pos, to: parent.pos, isIntro: true, color: parent.hue, alpha: 0.32));
    }
  }
  return Orbit3ConstellationGeometry(
      box: box,
      mode: Orbit3ConstellationMode.gravity,
      placements: placements,
      byId: byId,
      connectors: connectors);
}
