import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

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
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulsing circles
        SizedBox(
          width: 140,
          height: 140,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: _DashedCirclesPainter(
                  animation: _controller.value,
                ),
                child: Center(
                  child: _buildCenterIcon(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Main text
        const Text(
          'Your circle is waiting to be filled',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        // Secondary text
        const Text(
          'Scan a friend\'s code or share yours to connect',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCenterIcon() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryAccent.withValues(alpha: 0.1),
      ),
      child: CustomPaint(
        painter: _ConstellationDotsPainter(),
      ),
    );
  }
}

class _DashedCirclesPainter extends CustomPainter {
  final double animation;

  _DashedCirclesPainter({required this.animation});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radii = [28.0, 45.0, 63.0];
    final phases = [0.0, 0.33, 0.66]; // Staggered animation phases

    for (var i = 0; i < radii.length; i++) {
      final phase = phases[i];
      final animPhase = (animation + phase) % 1.0;
      // Scale pulses between 0.95 and 1.05
      final scale = 1.0 + 0.05 * math.sin(animPhase * 2 * math.pi);
      final opacity = 0.3 + 0.2 * math.sin(animPhase * 2 * math.pi);

      final paint = Paint()
        ..color = AppColors.textMuted.withValues(alpha: opacity)
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
    return oldDelegate.animation != animation;
  }
}

class _ConstellationDotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primaryAccent
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final positions = [
      center,
      center + const Offset(-6, -6),
      center + const Offset(7, -4),
      center + const Offset(-4, 7),
      center + const Offset(6, 6),
    ];

    for (final pos in positions) {
      canvas.drawCircle(pos, 2.5, paint);
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
