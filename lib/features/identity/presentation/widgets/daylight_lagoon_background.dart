import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 248 — the Signal ("warm mineral sky") shared background. A calm, static warm
/// gradient ground with two broad, still colour fields (a violet bloom and a
/// sage bloom). There is deliberately NO animation controller: reduced-motion
/// and ordinary mode render the exact same still composition, so the
/// always-mounted chrome `BackdropFilter`s sit in front of a cacheable backdrop
/// and nothing ticks at rest.
class DaylightLagoonBackground extends StatelessWidget {
  final Widget child;

  /// Warm mineral/linen ground; pure white is forbidden as the Signal canvas.
  final Color baseColor;

  /// Warm center-to-edge depth without a white hotspot.
  final List<Color> groundGradientColors;

  /// Broad static violet colour field.
  final Color violetWash;

  /// Broad static sage colour field.
  final Color sageWash;

  const DaylightLagoonBackground({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFFECE8E1),
    this.groundGradientColors = const [
      Color(0xFFF4F0EA),
      Color(0xFFECE8E1),
      Color(0xFFE5DED5),
    ],
    this.violetWash = const Color(0x177C69C8),
    this.sageWash = const Color(0x1258A989),
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('daylight-lagoon-background-root'),
      decoration: BoxDecoration(
        color: baseColor,
        gradient: RadialGradient(
          center: const Alignment(0.0, -0.06),
          radius: 1.15,
          colors: groundGradientColors,
          stops: const [0.0, 0.62, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                key: const ValueKey('daylight-lagoon-background-painter'),
                painter: _DaylightLagoonPainter(
                  violet: violetWash,
                  sage: sageWash,
                ),
                isComplex: true,
                willChange: false,
              ),
            ),
          ),
          RepaintBoundary(child: child),
        ],
      ),
    );
  }
}

class _DaylightLagoonPainter extends CustomPainter {
  final Color violet;
  final Color sage;

  const _DaylightLagoonPainter({required this.violet, required this.sage});

  @override
  void paint(Canvas canvas, Size size) {
    _paintBloom(
      canvas,
      size,
      color: violet,
      cx: 0.20,
      cy: 0.90,
      rx: 0.60,
      ry: 0.48,
      stop: 0.60,
    );
    _paintBloom(
      canvas,
      size,
      color: sage,
      cx: 0.85,
      cy: 0.10,
      rx: 0.50,
      ry: 0.40,
      stop: 0.62,
    );
  }

  void _paintBloom(
    Canvas canvas,
    Size size, {
    required Color color,
    required double cx,
    required double cy,
    required double rx,
    required double ry,
    required double stop,
  }) {
    final centerX = cx * size.width;
    final centerY = cy * size.height;
    final radiusX = rx * size.width;
    final radiusY = ry * size.height;

    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.scale(radiusX, radiusY);

    final shader = ui.Gradient.radial(
      Offset.zero,
      1.0,
      [color, color.withValues(alpha: 0)],
      [0.0, stop],
    );
    canvas.drawCircle(Offset.zero, 1.0, Paint()..shader = shader);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DaylightLagoonPainter oldDelegate) {
    return oldDelegate.violet != violet || oldDelegate.sage != sage;
  }
}
