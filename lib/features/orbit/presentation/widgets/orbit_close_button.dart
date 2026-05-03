import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';

/// 24x24 glass circle X button for closing the Orbit screen.
class OrbitCloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const OrbitCloseButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: readableColors.glassSurface,
              border: Border.all(color: readableColors.glassBorder),
            ),
            child: CustomPaint(
              size: const Size(20, 20),
              painter: _XPainter(color: readableColors.iconPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _XPainter extends CustomPainter {
  final Color color;

  const _XPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Center the X in the 24x24 container
    const inset = 15.0;
    const containerSize = 44.0;
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
  bool shouldRepaint(covariant _XPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
