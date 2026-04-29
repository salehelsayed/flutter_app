// Standalone, dependency-free Flutter port of the "Background-Feed 6-5"
// ambient sky — the light-mode counterpart of `CosmicBackground` (6-1).
//
// Layers, painted bottom → top:
//   1. Pure white base (#FFFFFF)
//   2. Three drifting chromatic blooms (violet, teal, pink) — slow 18s loop
//      Same positions/sizes as 6-1, with alphas bumped so the colors
//      register on white the way they do on the cosmic dark.
//   3. Caller-provided child on top
//
// No starfield — stars don't read on a bright sky.
//
// Drop this file into any Flutter project and wrap your screen body with
// `DaylightLagoonBackground(child: ...)`.
//
// Example:
//   Scaffold(
//     body: DaylightLagoonBackground(
//       child: Center(child: Text('Hello')),
//     ),
//   )

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class DaylightLagoonBackground extends StatefulWidget {
  final Widget child;

  /// Length of one full chromatic-bloom drift loop.
  final Duration driftPeriod;

  /// Solid base color filling the page behind the blooms.
  final Color baseColor;

  /// Hue of each cf3-ambient bloom. Defaults match the web reference.
  final Color violetBloom; // bottom-left, dominant
  final Color tealBloom;   // top-right, medium
  final Color pinkBloom;   // middle-right, soft accent

  const DaylightLagoonBackground({
    super.key,
    required this.child,
    this.driftPeriod = const Duration(seconds: 18),
    this.baseColor = const Color(0xFFFFFFFF),
    this.violetBloom = const Color(0xFF818CF8),
    this.tealBloom   = const Color(0xFF81E6D9),
    this.pinkBloom   = const Color(0xFFF472B6),
  });

  @override
  State<DaylightLagoonBackground> createState() =>
      _DaylightLagoonBackgroundState();
}

class _DaylightLagoonBackgroundState extends State<DaylightLagoonBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.driftPeriod,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: widget.baseColor),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _DaylightLagoonPainter(
              driftT: _controller.value,
              violet: widget.violetBloom,
              teal: widget.tealBloom,
              pink: widget.pinkBloom,
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}

class _DaylightLagoonPainter extends CustomPainter {
  final double driftT; // 0..1 progress through the drift period
  final Color violet;
  final Color teal;
  final Color pink;

  _DaylightLagoonPainter({
    required this.driftT,
    required this.violet,
    required this.teal,
    required this.pink,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintBlooms(canvas, size);
  }

  // ── Drifting chromatic blooms (cf3-ambient) ─────────────────────────────
  //
  // CSS keyframe:
  //   0%, 100% { transform: translate3d(0, 0, 0) scale(1); }
  //   50%      { transform: translate3d(6px, -4px, 0) scale(1.04); }
  //
  // sin(π·t) gives 0 → 1 → 0 over one cycle, matching the keyframe shape.
  void _paintBlooms(Canvas canvas, Size size) {
    final wave = math.sin(driftT * math.pi);
    final dx = 6 * wave;
    final dy = -4 * wave;
    final scale = 1.0 + 0.04 * wave;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-size.width / 2 + dx, -size.height / 2 + dy);

    // Bloom positions/sizes/stops match 6-1 exactly. Alphas are bumped to
    // the 6-5 values so the pastel colors register on white.
    _paintBloom(canvas, size,
        color: violet, opacity: 0.30,
        cx: 0.20, cy: 0.90, rx: 0.60, ry: 0.48, stop: 0.60);
    _paintBloom(canvas, size,
        color: teal,   opacity: 0.22,
        cx: 0.85, cy: 0.10, rx: 0.50, ry: 0.40, stop: 0.62);
    _paintBloom(canvas, size,
        color: pink,   opacity: 0.18,
        cx: 0.70, cy: 0.60, rx: 0.40, ry: 0.32, stop: 0.60);

    canvas.restore();
  }

  /// One elliptical radial bloom — color at center fading to transparent.
  ///
  /// Uses canvas.scale to stretch a unit-circle gradient into an ellipse so
  /// the falloff is truly elliptical (Flutter's RadialGradient is otherwise
  /// always circular regardless of the box's aspect ratio).
  void _paintBloom(Canvas canvas, Size size, {
    required Color color,
    required double opacity,
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
    canvas.scale(radiusX, radiusY); // unit-ellipse local space

    final shader = ui.Gradient.radial(
      Offset.zero,
      1.0,
      [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
      [0.0, stop],
    );
    canvas.drawCircle(Offset.zero, 1.0, Paint()..shader = shader);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DaylightLagoonPainter old) => true;
}
