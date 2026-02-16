import 'dart:ui';
import 'package:flutter/material.dart';

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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Opacity(
            opacity: _animation.value,
            child: child,
          ),
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
              color: const Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
              border: Border.all(
                color: const Color(0x33FFFFFF), // rgba(255,255,255,0.2)
                width: 1,
                style: BorderStyle.none, // We'll use dashed via paint
              ),
            ),
            child: CustomPaint(
              painter: _DashedBorderPainter(),
              child: Center(
                child: Text(
                  '+${widget.count}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0x80FFFFFF), // rgba(255,255,255,0.5)
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
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x33FFFFFF)
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
