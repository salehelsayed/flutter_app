// Standalone, dependency-free Flutter port of the "Background-Feed 6-6"
// ambient sky.
//
// Same skeleton as Background-Feed 6-1 (cosmic radial gradient + drifting
// blooms + twinkling starfield) but the violet and teal hues swap corners,
// AND the violet bloom is enlarged so it reaches well into the screen
// instead of clinging to the top-right corner.
//
// Layers, bottom → top:
//   1. Deep cosmic radial gradient (#0A1124 → #050714 → #02030A)
//   2. Three drifting chromatic blooms:
//        - Teal,   bottom-left  — dominant     (rx 0.60, ry 0.48, α 0.18)
//        - Violet, top-right    — wide spread  (rx 0.70, ry 0.55, α 0.22)
//        - Pink,   middle-right — soft accent  (rx 0.40, ry 0.32, α 0.07)
//   3. 70 twinkling white stars
//   4. Caller-provided child on top
//
// Drop this file into any Flutter project and wrap your screen body with
// `CosmicBackgroundMirrored(child: ...)`.
//
// Example:
//   Scaffold(
//     body: CosmicBackgroundMirrored(
//       child: Center(child: Text('Hello')),
//     ),
//   )

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class CosmicBackgroundMirrored extends StatefulWidget {
  final Widget child;

  /// How many stars to scatter across the sky.
  final int starCount;

  /// Length of one full chromatic-bloom drift loop.
  final Duration driftPeriod;

  /// Three-stop radial gradient that fills the page. Listed center → edge.
  final List<Color> baseColors;

  /// Hue of each cf3-ambient bloom. Defaults match the web reference.
  final Color violetBloom; // top-right, wide spread (was bottom-left in 6-1)
  final Color tealBloom;   // bottom-left, dominant (was top-right in 6-1)
  final Color pinkBloom;   // middle-right, soft accent (unchanged)

  const CosmicBackgroundMirrored({
    super.key,
    required this.child,
    this.starCount = 70,
    this.driftPeriod = const Duration(seconds: 18),
    this.baseColors = const [
      Color(0xFF0A1124),
      Color(0xFF050714),
      Color(0xFF02030A),
    ],
    this.violetBloom = const Color(0xFF818CF8),
    this.tealBloom   = const Color(0xFF81E6D9),
    this.pinkBloom   = const Color(0xFFF472B6),
  });

  @override
  State<CosmicBackgroundMirrored> createState() =>
      _CosmicBackgroundMirroredState();
}

class _CosmicBackgroundMirroredState extends State<CosmicBackgroundMirrored>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Star> _stars;
  final Stopwatch _clock = Stopwatch();

  @override
  void initState() {
    super.initState();
    _clock.start();
    _controller = AnimationController(
      vsync: this,
      duration: widget.driftPeriod,
    )..repeat();

    final rng = math.Random();
    _stars = List.generate(
      widget.starCount,
      (_) => _Star(
        x: rng.nextDouble(),                // fraction of width   (0..1)
        y: rng.nextDouble(),                // fraction of height  (0..1)
        size: 0.4 + rng.nextDouble() * 1.6, // 0.4 .. 2.0 px
        delay: rng.nextDouble() * 4,        // 0 .. 4 s
        period: 2.5 + rng.nextDouble() * 3, // 2.5 .. 5.5 s
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        // Web ref: radial-gradient(ellipse at 15% 85%, #0A1124, #050714 45%, #02030A 100%)
        // Alignment(-0.7, 0.7) ≈ 15% from left, 85% from top.
        gradient: RadialGradient(
          center: const Alignment(-0.7, 0.7),
          radius: 1.0,
          colors: widget.baseColors,
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _CosmicPainter(
              driftT: _controller.value,
              elapsedSeconds: _clock.elapsedMilliseconds / 1000.0,
              stars: _stars,
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

class _Star {
  final double x;       // fraction of width   (0..1)
  final double y;       // fraction of height  (0..1)
  final double size;    // diameter in logical px
  final double delay;   // phase offset in seconds
  final double period;  // twinkle period in seconds

  _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.delay,
    required this.period,
  });
}

class _CosmicPainter extends CustomPainter {
  final double driftT;         // 0..1 progress through the drift period
  final double elapsedSeconds; // continuous time since the widget mounted
  final List<_Star> stars;
  final Color violet;
  final Color teal;
  final Color pink;

  _CosmicPainter({
    required this.driftT,
    required this.elapsedSeconds,
    required this.stars,
    required this.violet,
    required this.teal,
    required this.pink,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintBlooms(canvas, size);
    _paintStars(canvas, size);
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

    // ── 6-6 layout (mirrored from 6-1, with violet's spread bumped) ──
    // Bottom-left, dominant — TEAL (was violet in 6-1).
    _paintBloom(canvas, size,
        color: teal,   opacity: 0.18,
        cx: 0.20, cy: 0.90, rx: 0.60, ry: 0.48, stop: 0.60);
    // Top-right — VIOLET (was teal in 6-1), bumped in size, alpha and stop
    // so it spreads visibly into the screen instead of staying corner-only.
    _paintBloom(canvas, size,
        color: violet, opacity: 0.22,
        cx: 0.85, cy: 0.10, rx: 0.70, ry: 0.55, stop: 0.70);
    // Middle-right — PINK soft accent (unchanged from 6-1).
    _paintBloom(canvas, size,
        color: pink,   opacity: 0.07,
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

  // ── Twinkling stars (cf3-starfield) ─────────────────────────────────────
  //
  // CSS keyframe per star:
  //   0%, 100% { opacity: 0.15; transform: scale(0.9); }
  //   50%      { opacity: 0.85; transform: scale(1.1); }
  //
  // Each star has its own 2.5–5.5s period and 0–4s delay, driven by the
  // continuous Stopwatch so phases don't snap when the drift controller
  // wraps around.
  void _paintStars(Canvas canvas, Size size) {
    for (final s in stars) {
      final phaseSec = (elapsedSeconds + s.delay) % s.period;
      final phaseFrac = phaseSec / s.period;
      final wave = math.sin(phaseFrac * math.pi); // 0 → 1 → 0

      final opacity = 0.15 + 0.70 * wave;
      final scale = 0.9 + 0.20 * wave;

      final cx = s.x * size.width;
      final cy = s.y * size.height;
      final r = s.size * scale / 2;

      // Soft halo (mimics CSS box-shadow: 0 0 4px rgba(255,255,255,0.6))
      final glow = Paint()
        ..color = Colors.white.withValues(alpha: opacity * 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(Offset(cx, cy), r * 2, glow);

      // Sharp pinpoint
      final dot = Paint()..color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(Offset(cx, cy), r, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _CosmicPainter old) => true;
}
