import 'dart:math';

import 'package:flutter/material.dart';

/// Static dark cosmic backdrop for Orbit2 — a deep radial gradient + a fixed
/// starfield. Deliberately NOT animated (no drifting green/red glows), so the
/// constellation stays calm and the moving avatars are the only motion.
class Orbit2Backdrop extends StatelessWidget {
  final Widget child;
  const Orbit2Backdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.6, 0.7),
          radius: 1.2,
          colors: [Color(0xFF0A1124), Color(0xFF050714), Color(0xFF02030A)],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _StaticStarfield()),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _StaticStarfield extends CustomPainter {
  const _StaticStarfield();

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(811);
    final paint = Paint();
    for (var i = 0; i < 64; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      final r = 0.4 + rng.nextDouble() * 1.3;
      paint.color =
          Colors.white.withValues(alpha: 0.12 + rng.nextDouble() * 0.5);
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StaticStarfield oldDelegate) => false;
}
