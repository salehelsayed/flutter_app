import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_control_circle.dart';

/// The X control for closing the Orbit screen: the shared [OrbitControlCircle].
class OrbitCloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const OrbitCloseButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return GestureDetector(
      onTap: onTap,
      child: OrbitControlCircle.custom(
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _XPainter(color: readableColors.chromeInk),
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
