import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/ring_avatar_generator.dart';
import 'package:flutter_app/core/utils/ring_avatar_spec.dart';

/// CustomPainter that renders a ring avatar from [RingAvatarData].
class RingAvatarPainter extends CustomPainter {
  final RingAvatarData data;

  RingAvatarPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Draw rings from inner to outer (so outer rings are on top)
    for (final ring in data.rings) {
      _drawRing(canvas, center, ring);
    }

    // Draw center glow
    _drawCenterGlow(canvas, center, data.glow);
  }

  void _drawRing(Canvas canvas, Offset center, RingData ring) {
    final paint = Paint()
      ..color = ring.color.withValues(alpha: ring.opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ring.strokeWidth
      ..strokeCap = StrokeCap.round;

    if (ring.isDashed) {
      _drawDashedRing(canvas, center, ring, paint);
    } else {
      canvas.drawCircle(center, ring.radius, paint);
    }
  }

  void _drawDashedRing(
      Canvas canvas, Offset center, RingData ring, Paint paint) {
    final circumference = 2 * math.pi * ring.radius;
    final dashCount =
        (circumference / (ring.dashLength + ring.dashGap)).floor();

    if (dashCount <= 0) {
      // Fallback to solid ring if too small
      canvas.drawCircle(center, ring.radius, paint);
      return;
    }

    final actualDashLength = ring.dashLength;
    final actualGap = ring.dashGap;
    final totalDashUnit = actualDashLength + actualGap;
    final anglePerUnit = totalDashUnit / ring.radius;

    // Apply rotation offset
    final rotationRadians = ring.rotationDegrees * math.pi / 180;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotationRadians);

    final rect = Rect.fromCircle(center: Offset.zero, radius: ring.radius);

    double currentAngle = 0;
    while (currentAngle < 2 * math.pi) {
      final sweepAngle = actualDashLength / ring.radius;

      canvas.drawArc(
        rect,
        currentAngle,
        sweepAngle,
        false,
        paint,
      );

      currentAngle += anglePerUnit;
    }

    canvas.restore();
  }

  void _drawCenterGlow(Canvas canvas, Offset center, GlowData glow) {
    // Outer glow layer (largest, most transparent)
    final outerPaint = Paint()
      ..color =
          glow.color.withValues(alpha: RingAvatarConstants.glowOuterOpacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, glow.outerRadius, outerPaint);

    // Middle glow layer
    final middlePaint = Paint()
      ..color =
          glow.color.withValues(alpha: RingAvatarConstants.glowMiddleOpacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(center, glow.middleRadius, middlePaint);

    // Inner glow layer (smallest, fully opaque)
    final innerPaint = Paint()
      ..color =
          glow.color.withValues(alpha: RingAvatarConstants.glowInnerOpacity);
    canvas.drawCircle(center, glow.innerRadius, innerPaint);
  }

  @override
  bool shouldRepaint(covariant RingAvatarPainter oldDelegate) {
    // Since data is derived from peerId, we only repaint if data changes
    return oldDelegate.data != data;
  }
}
