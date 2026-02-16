import 'dart:math';
import 'package:flutter/material.dart';

/// CustomPainter that draws two dashed concentric circles.
///
/// Ring 1 (inner): teal tint, Ring 2 (outer): purple tint.
class OrbitalRingPainter extends CustomPainter {
  static const double ring1Radius = 62;
  static const double ring2Radius = 108;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Ring 1: teal dashed
    _drawDashedCircle(
      canvas,
      center,
      ring1Radius,
      const Color(0x1F81E6D9), // rgba(129,230,217,0.12)
      const Color(0x0881E6D9), // rgba(129,230,217,0.03) glow
      1.0,
    );

    // Ring 2: purple dashed
    _drawDashedCircle(
      canvas,
      center,
      ring2Radius,
      const Color(0x1AA78BFA), // rgba(167,139,250,0.10)
      const Color(0x0881E6D9), // rgba(129,230,217,0.03) glow
      1.0,
    );
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    Color glowColor,
    double strokeWidth,
  ) {
    // Draw glow
    final glowPaint = Paint()
      ..color = glowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, radius, glowPaint);

    // Draw dashed ring
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    const dashLength = 6.0;
    const gapLength = 4.0;
    final circumference = 2 * pi * radius;
    final totalDashes = (circumference / (dashLength + gapLength)).floor();

    for (var i = 0; i < totalDashes; i++) {
      final startAngle =
          (i * (dashLength + gapLength) / circumference) * 2 * pi;
      final sweepAngle = (dashLength / circumference) * 2 * pi;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
