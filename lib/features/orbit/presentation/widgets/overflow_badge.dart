import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';

/// "+N" circle badge shown on the outer ring when friends exceed 13.
///
/// Has a delayed entrance animation (1000ms) to appear after orbital avatars.
class OverflowBadge extends StatefulWidget {
  final int count;

  const OverflowBadge({super.key, required this.count});

  @override
  State<OverflowBadge> createState() => _OverflowBadgeState();
}

class _OverflowBadgeState extends State<OverflowBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.ease);

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final surfaceColor = readableColors.isLightSurface
        ? readableColors.surfaceSubtle.withValues(alpha: 0.82)
        : readableColors.glassSurface;
    final borderColor = readableColors.border.withValues(
      alpha: readableColors.isLightSurface ? 0.28 : 0.20,
    );

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Opacity(opacity: _animation.value, child: child),
        );
      },
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: surfaceColor,
              border: Border.all(
                color: borderColor,
                width: 1,
                style: BorderStyle.none, // We'll use dashed via paint
              ),
            ),
            child: CustomPaint(
              painter: _DashedBorderPainter(color: borderColor),
              child: Center(
                child: Text(
                  '+${widget.count}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: readableColors.textMuted,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;

  const _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const dashLength = 4.0;
    const gapLength = 3.0;
    final circumference = 2 * 3.14159 * radius;
    final totalDashes = (circumference / (dashLength + gapLength)).floor();

    for (var i = 0; i < totalDashes; i++) {
      final startAngle =
          (i * (dashLength + gapLength) / circumference) * 2 * 3.14159;
      final sweepAngle = (dashLength / circumference) * 2 * 3.14159;

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
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
