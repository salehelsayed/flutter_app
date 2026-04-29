import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';

/// Empty state with pulsing concentric dashed circles.
class EmptyCircleState extends StatefulWidget {
  const EmptyCircleState({super.key});

  @override
  State<EmptyCircleState> createState() => _EmptyCircleStateState();
}

class _EmptyCircleStateState extends State<EmptyCircleState>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
      value: 0.22,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final screenHeight = MediaQuery.of(context).size.height;
    // Continuous scaling: 0.0 at 650pt, 1.0 at 900pt
    final t = ((screenHeight - 650) / 250).clamp(0.0, 1.0);
    final circleSize = lerpDouble(80, 140, t)!;
    final painterScale = lerpDouble(0.57, 1.0, t)!;
    final gap = lerpDouble(4, 12, t)!;
    final mainFontSize = lerpDouble(13, 15, t)!;
    final subGap = lerpDouble(2, 4, t)!;
    final subFontSize = lerpDouble(11, 13, t)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulsing circles
        SizedBox(
          width: circleSize,
          height: circleSize,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: _DashedCirclesPainter(
                  animation: _controller.value,
                  scale: painterScale,
                  color: readableColors.iconMuted,
                ),
                child: Center(child: _buildCenterIcon(scaleFactor: t)),
              );
            },
          ),
        ),
        SizedBox(height: gap),
        // Main text
        Text(
          'Your circle is waiting to be filled',
          style: TextStyle(
            color: readableColors.textPrimary,
            fontSize: mainFontSize,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: subGap),
        // Secondary text
        Text(
          'Scan a friend\'s code or share yours to connect',
          style: TextStyle(
            color: readableColors.textSecondary,
            fontSize: subFontSize,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildCenterIcon({required double scaleFactor}) {
    final size = lerpDouble(24, 36, scaleFactor)!;
    final dotScale = lerpDouble(0.68, 1.0, scaleFactor)!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryAccent.withValues(alpha: 0.1),
      ),
      child: CustomPaint(painter: _ConstellationDotsPainter(scale: dotScale)),
    );
  }
}

class _DashedCirclesPainter extends CustomPainter {
  final double animation;
  final double scale;
  final Color color;

  _DashedCirclesPainter({
    required this.animation,
    required this.color,
    this.scale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radii = [28.0 * scale, 45.0 * scale, 63.0 * scale];
    final phases = [0.0, 0.33, 0.66]; // Staggered animation phases

    for (var i = 0; i < radii.length; i++) {
      final phase = phases[i];
      final animPhase = (animation + phase) % 1.0;
      // Scale pulses between 0.95 and 1.05
      final scale = 1.0 + 0.05 * math.sin(animPhase * 2 * math.pi);
      final opacity = 0.3 + 0.2 * math.sin(animPhase * 2 * math.pi);

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      _drawDashedCircle(
        canvas,
        center,
        radii[i] * scale,
        paint,
        dashLength: 8,
        gapLength: 6,
      );
    }
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    final circumference = 2 * math.pi * radius;
    final dashCount = (circumference / (dashLength + gapLength)).floor();
    final actualDashLength = circumference / dashCount - gapLength;
    final dashAngle = actualDashLength / radius;
    final gapAngle = gapLength / radius;

    for (var i = 0; i < dashCount; i++) {
      final startAngle = i * (dashAngle + gapAngle);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclesPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.scale != scale ||
        oldDelegate.color != color;
  }
}

class _ConstellationDotsPainter extends CustomPainter {
  final double scale;

  _ConstellationDotsPainter({this.scale = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primaryAccent
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final positions = [
      center,
      center + Offset(-6 * scale, -6 * scale),
      center + Offset(7 * scale, -4 * scale),
      center + Offset(-4 * scale, 7 * scale),
      center + Offset(6 * scale, 6 * scale),
    ];

    for (final pos in positions) {
      canvas.drawCircle(pos, 2.5 * scale, paint);
    }

    // Draw connecting lines
    final linePaint = Paint()
      ..color = AppColors.primaryAccent.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawLine(positions[0], positions[1], linePaint);
    canvas.drawLine(positions[0], positions[2], linePaint);
    canvas.drawLine(positions[0], positions[3], linePaint);
    canvas.drawLine(positions[0], positions[4], linePaint);
  }

  @override
  bool shouldRepaint(covariant _ConstellationDotsPainter oldDelegate) =>
      oldDelegate.scale != scale;
}
