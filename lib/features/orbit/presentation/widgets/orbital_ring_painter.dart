import 'dart:math';
import 'package:flutter/material.dart';

/// One concentric overflow arc to paint (198): a dashed span centred at 12
/// o'clock, half-width [phiMax], at [radius]. [arcIndex] alternates the dash
/// tint (teal / purple) exactly like the two rings.
class OrbitArcRing {
  final double radius;
  final double phiMax;
  final int arcIndex;

  const OrbitArcRing({
    required this.radius,
    required this.phiMax,
    required this.arcIndex,
  });

  @override
  bool operator ==(Object other) =>
      other is OrbitArcRing &&
      other.radius == radius &&
      other.phiMax == phiMax &&
      other.arcIndex == arcIndex;

  @override
  int get hashCode => Object.hash(radius, phiMax, arcIndex);
}

/// Draws the two dashed concentric rings and (198) any expanded overflow arcs.
///
/// Ring radii are knob-scaled and passed in from a single source of truth
/// ([OrbitalVisualization]/`orbit_arc_layout`) so the painted paths track the
/// seated nodes (TC-198-29). The dash and glow colors default to the old dark
/// literals and can be injected by the active background tone.
class OrbitalRingPainter extends CustomPainter {
  /// Circle centre; when null the painter uses the canvas centre (back-compat).
  final Offset? center;
  final double ring1Radius;
  final double ring2Radius;
  final List<OrbitArcRing> arcs;
  final Color ring1Color;
  final Color ring2Color;
  final Color glowColor;

  static const Color _tealDash = Color(0x4081E6D9); // rgba(129,230,217,0.25)
  static const Color _purpleDash = Color(0x33A78BFA); // rgba(167,139,250,0.20)
  static const Color _tealGlow = Color(0x1481E6D9); // rgba(129,230,217,0.08)

  const OrbitalRingPainter({
    this.center,
    this.ring1Radius = 62,
    this.ring2Radius = 108,
    this.arcs = const [],
    this.ring1Color = _tealDash,
    this.ring2Color = _purpleDash,
    this.glowColor = _tealGlow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = center ?? Offset(size.width / 2, size.height / 2);

    // Ring 1 (teal), Ring 2 (purple) — full circles.
    _drawDashedArc(canvas, c, ring1Radius, 0, 2 * pi, ring1Color);
    _drawDashedArc(canvas, c, ring2Radius, 0, 2 * pi, ring2Color);

    // Overflow arcs — centred at 12 o'clock (-pi/2), span ±phiMax.
    for (final arc in arcs) {
      final start = -pi / 2 - arc.phiMax;
      final sweep = 2 * arc.phiMax;
      final color = arc.arcIndex.isEven ? ring1Color : ring2Color;
      _drawDashedArc(canvas, c, arc.radius, start, sweep, color);
    }
  }

  void _drawDashedArc(
    Canvas canvas,
    Offset center,
    double radius,
    double startAngle,
    double sweepAngle,
    Color color,
  ) {
    if (radius <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Blurred glow sublayer.
    final glowPaint = Paint()
      ..color = glowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);

    // Crisp alternating dash.
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const dashLength = 8.0;
    const gapLength = 4.0;
    final dashAngle = dashLength / radius;
    final gapAngle = gapLength / radius;
    final step = dashAngle + gapAngle;
    if (step <= 0) return;
    final count = (sweepAngle / step).floor();
    for (var i = 0; i < count; i++) {
      canvas.drawArc(rect, startAngle + i * step, dashAngle, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant OrbitalRingPainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.ring1Radius != ring1Radius ||
      oldDelegate.ring2Radius != ring2Radius ||
      oldDelegate.ring1Color != ring1Color ||
      oldDelegate.ring2Color != ring2Color ||
      oldDelegate.glowColor != glowColor ||
      !_listEquals(oldDelegate.arcs, arcs);

  static bool _listEquals(List<OrbitArcRing> a, List<OrbitArcRing> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
