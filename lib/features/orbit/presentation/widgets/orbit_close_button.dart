import 'dart:ui';
import 'package:flutter/material.dart';

/// 36x36 glass circle X button for closing the Orbit screen.
class OrbitCloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const OrbitCloseButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x1AFFFFFF), // rgba(255,255,255,0.1)
              border: Border.all(
                color: const Color(0x1FFFFFFF), // rgba(255,255,255,0.12)
              ),
            ),
            child: CustomPaint(
              size: const Size(16, 16),
              painter: _XPainter(),
            ),
          ),
        ),
      ),
    );
  }
}

class _XPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xCCFFFFFF) // rgba(255,255,255,0.8)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Center the X in the 36x36 container
    const inset = 10.0;
    const containerSize = 36.0;
    canvas.drawLine(
      const Offset(inset, inset),
      const Offset(containerSize - inset, containerSize - inset),
      paint,
    );
    canvas.drawLine(
      const Offset(containerSize - inset, inset),
      const Offset(inset, containerSize - inset),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
