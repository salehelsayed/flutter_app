import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_connection_profile.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_constellation_geometry.dart';

/// Shared paint helpers for the three constellation painters.
///
/// Members are drawn here as STARS (a soft colored halo, a bright near-white
/// core, a temperature ring, and a sparkle for the brightest) — so the picture
/// reads like a night sky / zodiac figure rather than a cluster of avatar discs.
/// The avatar photo only blooms in (as a widget, above the paint) when a star is
/// selected or you zoom in close. The connecting lines per mode draw the figure.

double _twinkle(String id, double recencyT, double t, bool motion) {
  if (!motion) return 1.0;
  final phase = orbit3Hash01(id, 8) * 2 * pi;
  final speed = 0.6 + 1.4 * recencyT;
  return 0.7 + 0.3 * sin(t * 2 * pi * speed + phase);
}

void _glow(Canvas canvas, Offset c, double radius, Color color, double alpha,
    double blur) {
  if (alpha <= 0 || radius <= 0) return;
  final p = Paint()
    ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
  canvas.drawCircle(c, radius, p);
}

/// A deep-sky backdrop drawn first in every mode: a faint always-on starfield.
/// The "milky way" is simply MORE faint white stars appearing as you zoom in —
/// no coloured nebula clouds, which only muddied the picture. Just clean points
/// of light on the dark backdrop.
void _drawNightSky(
    Canvas canvas, Size size, double zoom, double t, bool motion) {
  final mw = ((zoom - 1.0) / 1.3).clamp(0.0, 1.0); // zoom reveal
  final reach = 0.12 + 0.88 * mw; // a faint sky always; denser as you zoom in
  final count = 150 + (120 * mw).round();
  for (var i = 0; i < count; i++) {
    final key = 'sky$i';
    final p = Offset(orbit3Hash01(key, 1) * size.width,
        orbit3Hash01(key, 2) * size.height);
    final b = orbit3Hash01(key, 3);
    final tw =
        motion ? 0.55 + 0.45 * sin(t * 2 * pi * (0.35 + b) + b * 6.28) : 1.0;
    final a = (0.05 + 0.42 * b) * reach * tw;
    canvas.drawCircle(p, 0.3 + b * 1.3,
        Paint()..color = Colors.white.withValues(alpha: a.clamp(0.0, 1.0)));
  }
}

/// Draws every member as a star: colored halo + bright core + temperature ring
/// + a sparkle for the brightest.
void _drawStars(Canvas canvas, Offset center,
    Orbit3ConstellationGeometry geo, double t, bool motion) {
  for (final pl in geo.placements) {
    final pos = center + pl.pos;
    final m = pl.driver.magnitude;
    final tw = _twinkle(pl.id, pl.driver.recencyT, t, motion);
    final hue = pl.hue;
    final a = pl.opacity * tw;

    // A TIGHT, subtle glow so a star reads as luminous without bleeding into a
    // muddy cloud where stars cluster.
    _glow(canvas, pos, 5 + 7 * m, hue, (0.16 + 0.16 * m) * a, 3.5);
    // Bright near-white core — the star itself.
    final coreR = 1.6 + 3.0 * m;
    final coreColor = Color.lerp(hue, Colors.white, 0.8)!;
    canvas.drawCircle(pos, coreR,
        Paint()..color = coreColor.withValues(alpha: (0.95 * a).clamp(0.0, 1.0)));
    // A thin crisp reciprocity ring — the teal↔coral colour cue, no haze.
    canvas.drawCircle(
        pos,
        coreR + 2.0,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = hue.withValues(alpha: (0.8 * a).clamp(0.0, 1.0)));
    // 4-point sparkle for the brighter stars.
    if (m > 0.35) {
      final len = coreR * 2.6 + 5 * m;
      final sp = Paint()
        ..color = coreColor.withValues(alpha: (0.5 * a).clamp(0.0, 1.0))
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(pos + Offset(-len, 0), pos + Offset(len, 0), sp);
      canvas.drawLine(pos + Offset(0, -len), pos + Offset(0, len), sp);
    }
  }
}

Path _bowedPath(Offset from, Offset to, Offset center, double bow) {
  final mid = (from + to) / 2;
  var dir = mid - center;
  final len = dir.distance;
  if (len > 0.001) dir = dir / len;
  final ctrl = mid + dir * bow;
  return Path()
    ..moveTo(from.dx, from.dy)
    ..quadraticBezierTo(ctrl.dx, ctrl.dy, to.dx, to.dy);
}

// ============================ ZODIAC ============================
class Orbit3ZodiacPainter extends CustomPainter {
  final Orbit3ConstellationGeometry geo;
  final double t;
  final bool motion;
  final Color lineColor;
  final Color coronaColor;
  final double zoom;

  const Orbit3ZodiacPainter({
    required this.geo,
    required this.t,
    required this.motion,
    required this.lineColor,
    required this.coronaColor,
    this.zoom = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rMax = size.width / 2 - 26;

    _drawNightSky(canvas, size, zoom, t, motion);

    // Faint horoscope skeleton: 12 house wedges + zodiac bands + rim ticks.
    final wedge = Paint()
      ..color = lineColor.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    for (var k = 0; k < 12; k++) {
      final ang = (-90 + 30.0 * k) * pi / 180;
      canvas.drawLine(
          center, center + Offset(cos(ang), sin(ang)) * rMax, wedge);
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = lineColor.withValues(alpha: 0.05);
    for (final f in [1.0, 0.7, 0.42]) {
      canvas.drawCircle(center, rMax * f, ring);
    }
    final tick = Paint()
      ..color = lineColor.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var d = 0; d < 60; d++) {
      final ang = d * 6.0 * pi / 180;
      final dir = Offset(cos(ang), sin(ang));
      canvas.drawLine(center + dir * rMax, center + dir * (rMax - 5), tick);
    }

    // A gold pointer at 12 o'clock marks the OLDEST friend; the thread winds
    // oldest → newest so the meeting-order ("how it's ordered") is literally drawn.
    const gold = Color(0xFFFFE08A);
    canvas.drawCircle(center + Offset(0, -rMax), 3.2,
        Paint()..color = gold.withValues(alpha: 0.9));
    if (geo.placements.length > 1) {
      final thread = Path()
        ..moveTo(center.dx + geo.placements.first.pos.dx,
            center.dy + geo.placements.first.pos.dy);
      for (final pl in geo.placements.skip(1)) {
        thread.lineTo(center.dx + pl.pos.dx, center.dy + pl.pos.dy);
      }
      canvas.drawPath(
          thread,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = gold.withValues(alpha: 0.20)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    }

    // Intro lineage arcs (under the stars).
    for (final c in geo.connectors) {
      final from = center + c.from;
      final to = center + c.to;
      canvas.drawPath(
          _bowedPath(from, to, center, 22),
          Paint()
            ..color = c.color.withValues(alpha: c.alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1);
    }

    _glow(canvas, center, 16, coronaColor, 0.22, 9); // subtle "You" corona
    _drawStars(canvas, center, geo, t, motion);
  }

  @override
  bool shouldRepaint(covariant Orbit3ZodiacPainter old) =>
      !identical(old.geo, geo) ||
      old.t != t ||
      old.motion != motion ||
      old.zoom != zoom;
}

// ============================ GALAXY ============================
class Orbit3GalaxyArmPainter extends CustomPainter {
  final Orbit3ConstellationGeometry geo;
  final double t;
  final bool motion;
  final Color lineColor;
  final Color coronaColor;
  final double zoom;

  const Orbit3GalaxyArmPainter({
    required this.geo,
    required this.t,
    required this.motion,
    required this.lineColor,
    required this.coronaColor,
    this.zoom = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    _drawNightSky(canvas, size, zoom, t, motion);

    // A small, subtle galactic core glow (kept tight so it doesn't haze).
    _glow(canvas, center, size.width * 0.06, coronaColor, 0.20, 12);

    // The spiral arm GUIDE — strokes the timeline even where stars are sparse.
    final guide = orbit3GalaxyGuide(size.width);
    final guidePath = Path()
      ..moveTo(center.dx + guide.first.dx, center.dy + guide.first.dy);
    for (final g in guide.skip(1)) {
      guidePath.lineTo(center.dx + g.dx, center.dy + g.dy);
    }
    canvas.drawPath(
        guidePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..color = coronaColor.withValues(alpha: 0.07)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
    canvas.drawPath(
        guidePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = lineColor.withValues(alpha: 0.16));

    // Intro connector hairlines, bowed slightly toward the core.
    for (final c in geo.connectors) {
      final from = center + c.from;
      final to = center + c.to;
      canvas.drawPath(
          _bowedPath(from, to, center, -14),
          Paint()
            ..color = c.color.withValues(alpha: c.alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }

    _drawStars(canvas, center, geo, t, motion);
  }

  @override
  bool shouldRepaint(covariant Orbit3GalaxyArmPainter old) =>
      !identical(old.geo, geo) ||
      old.t != t ||
      old.motion != motion ||
      old.zoom != zoom;
}

// ============================ GRAVITY ============================
class Orbit3GravityFieldPainter extends CustomPainter {
  final Orbit3ConstellationGeometry geo;
  final double t;
  final bool motion;
  final Color lineColor;
  final Color coronaColor;
  final double zoom;

  const Orbit3GravityFieldPainter({
    required this.geo,
    required this.t,
    required this.motion,
    required this.lineColor,
    required this.coronaColor,
    this.zoom = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rMax = size.width * 0.46;

    _drawNightSky(canvas, size, zoom, t, motion);

    // Depth guide rings, fading outward to sell distance.
    for (final f in [0.30, 0.55, 0.80, 1.0]) {
      canvas.drawCircle(
          center,
          rMax * f,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = lineColor.withValues(alpha: 0.06 * (1.05 - f)));
    }

    _glow(canvas, center, size.width * 0.06, coronaColor, 0.22, 12); // subtle sun

    // Gravity tethers: each captured moon → its introducer planet.
    for (final c in geo.connectors) {
      final from = center + c.from;
      final to = center + c.to;
      canvas.drawPath(
          _bowedPath(from, to, center, 8),
          Paint()
            ..color = c.color.withValues(alpha: c.alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }

    _drawStars(canvas, center, geo, t, motion);
  }

  @override
  bool shouldRepaint(covariant Orbit3GravityFieldPainter old) =>
      !identical(old.geo, geo) ||
      old.t != t ||
      old.motion != motion ||
      old.zoom != zoom;
}
