import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Cosmic shared app background with a static reduced-motion mode.
class CosmicBackground extends StatefulWidget {
  final Widget child;
  final int starCount;
  final int starSeed;
  final Duration driftPeriod;

  const CosmicBackground({
    super.key,
    required this.child,
    this.starCount = 36,
    this.starSeed = 811,
    this.driftPeriod = const Duration(seconds: 18),
  });

  @override
  State<CosmicBackground> createState() => _CosmicBackgroundState();
}

class _CosmicBackgroundState extends State<CosmicBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Star> _stars;
  final Stopwatch _clock = Stopwatch();
  bool _motionDisabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.driftPeriod,
    );
    _stars = _generateStars();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionPreference();
  }

  @override
  void didUpdateWidget(covariant CosmicBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driftPeriod != widget.driftPeriod) {
      _controller.duration = widget.driftPeriod;
    }
    if (oldWidget.starCount != widget.starCount ||
        oldWidget.starSeed != widget.starSeed) {
      _stars = _generateStars();
    }
    _syncMotionPreference();
  }

  @override
  void dispose() {
    _clock.stop();
    _controller.dispose();
    super.dispose();
  }

  List<_Star> _generateStars() {
    final rng = math.Random(widget.starSeed);
    return List.generate(
      widget.starCount,
      (_) => _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 0.4 + rng.nextDouble() * 1.6,
        delay: rng.nextDouble() * 4,
        period: 2.5 + rng.nextDouble() * 3,
      ),
    );
  }

  void _syncMotionPreference() {
    final mediaQuery = MediaQuery.maybeOf(context);
    final motionDisabled =
        (mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false);
    _motionDisabled = motionDisabled;

    if (motionDisabled) {
      _clock.stop();
      _controller.stop();
      _controller.value = 0;
      return;
    }

    if (!_clock.isRunning) {
      _clock.start();
    }
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('cosmic-background-root'),
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.7, 0.7),
          radius: 1.0,
          colors: [Color(0xFF0A1124), Color(0xFF050714), Color(0xFF02030A)],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                key: const ValueKey('cosmic-background-painter'),
                painter: _CosmicPainter(
                  animation: _motionDisabled ? null : _controller,
                  elapsedClock: _clock,
                  motionDisabled: _motionDisabled,
                  stars: _stars,
                ),
                isComplex: true,
                willChange: !_motionDisabled,
              ),
            ),
          ),
          RepaintBoundary(child: widget.child),
        ],
      ),
    );
  }
}

class _Star {
  final double x;
  final double y;
  final double size;
  final double delay;
  final double period;

  const _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.delay,
    required this.period,
  });
}

class _CosmicPainter extends CustomPainter {
  final Animation<double>? animation;
  final Stopwatch elapsedClock;
  final bool motionDisabled;
  final List<_Star> stars;

  _CosmicPainter({
    required this.animation,
    required this.elapsedClock,
    required this.motionDisabled,
    required this.stars,
  }) : super(repaint: motionDisabled ? null : animation);

  double get _driftT => motionDisabled ? 0 : animation?.value ?? 0;

  double get _elapsedSeconds =>
      motionDisabled ? 0 : elapsedClock.elapsedMilliseconds / 1000.0;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBlooms(canvas, size);
    _paintStars(canvas, size);
  }

  void _paintBlooms(Canvas canvas, Size size) {
    final wave = math.sin(_driftT * math.pi);
    final dx = 6 * wave;
    final dy = -4 * wave;
    final scale = 1.0 + 0.04 * wave;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-size.width / 2 + dx, -size.height / 2 + dy);

    _paintBloom(
      canvas,
      size,
      color: const Color(0xFF818CF8),
      opacity: 0.18,
      cx: 0.20,
      cy: 0.90,
      rx: 0.60,
      ry: 0.48,
      stop: 0.60,
    );
    _paintBloom(
      canvas,
      size,
      color: const Color(0xFF81E6D9),
      opacity: 0.10,
      cx: 0.85,
      cy: 0.10,
      rx: 0.50,
      ry: 0.40,
      stop: 0.62,
    );
    _paintBloom(
      canvas,
      size,
      color: const Color(0xFFF472B6),
      opacity: 0.07,
      cx: 0.70,
      cy: 0.60,
      rx: 0.40,
      ry: 0.32,
      stop: 0.60,
    );

    canvas.restore();
  }

  void _paintBloom(
    Canvas canvas,
    Size size, {
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
    canvas.scale(radiusX, radiusY);

    final shader = ui.Gradient.radial(
      Offset.zero,
      1.0,
      [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
      [0.0, stop],
    );
    canvas.drawCircle(Offset.zero, 1.0, Paint()..shader = shader);

    canvas.restore();
  }

  void _paintStars(Canvas canvas, Size size) {
    for (final star in stars) {
      final phaseSec = (_elapsedSeconds + star.delay) % star.period;
      final phaseFrac = phaseSec / star.period;
      final wave = math.sin(phaseFrac * math.pi);
      final opacity = 0.15 + 0.70 * wave;
      final scale = 0.9 + 0.20 * wave;
      final center = Offset(star.x * size.width, star.y * size.height);
      final radius = star.size * scale / 2;

      final dot = Paint()..color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(center, radius, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _CosmicPainter oldDelegate) {
    return oldDelegate.motionDisabled != motionDisabled ||
        oldDelegate.animation != animation ||
        oldDelegate.stars != stars;
  }
}
