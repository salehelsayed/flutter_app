import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Light shared app background with pastel drifting blooms.
class DaylightLagoonBackground extends StatefulWidget {
  final Widget child;
  final Duration driftPeriod;
  final Color baseColor;
  final Color violetBloom;
  final Color tealBloom;
  final Color pinkBloom;

  const DaylightLagoonBackground({
    super.key,
    required this.child,
    this.driftPeriod = const Duration(seconds: 18),
    this.baseColor = Colors.white,
    this.violetBloom = const Color(0xFF818CF8),
    this.tealBloom = const Color(0xFF81E6D9),
    this.pinkBloom = const Color(0xFFF472B6),
  });

  @override
  State<DaylightLagoonBackground> createState() =>
      _DaylightLagoonBackgroundState();
}

class _DaylightLagoonBackgroundState extends State<DaylightLagoonBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _motionDisabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.driftPeriod,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionPreference();
  }

  @override
  void didUpdateWidget(covariant DaylightLagoonBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driftPeriod != widget.driftPeriod) {
      _controller.duration = widget.driftPeriod;
    }
    _syncMotionPreference();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncMotionPreference() {
    final mediaQuery = MediaQuery.maybeOf(context);
    final motionDisabled =
        (mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false);
    _motionDisabled = motionDisabled;

    if (motionDisabled) {
      _controller.stop();
      _controller.value = 0;
      return;
    }

    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('daylight-lagoon-background-root'),
      decoration: BoxDecoration(color: widget.baseColor),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                key: const ValueKey('daylight-lagoon-background-painter'),
                painter: _DaylightLagoonPainter(
                  animation: _motionDisabled ? null : _controller,
                  motionDisabled: _motionDisabled,
                  violet: widget.violetBloom,
                  teal: widget.tealBloom,
                  pink: widget.pinkBloom,
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

class _DaylightLagoonPainter extends CustomPainter {
  final Animation<double>? animation;
  final bool motionDisabled;
  final Color violet;
  final Color teal;
  final Color pink;

  _DaylightLagoonPainter({
    required this.animation,
    required this.motionDisabled,
    required this.violet,
    required this.teal,
    required this.pink,
  }) : super(repaint: motionDisabled ? null : animation);

  double get _driftT => motionDisabled ? 0 : animation?.value ?? 0;

  @override
  void paint(Canvas canvas, Size size) {
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
      color: violet,
      opacity: 0.30,
      cx: 0.20,
      cy: 0.90,
      rx: 0.60,
      ry: 0.48,
      stop: 0.60,
    );
    _paintBloom(
      canvas,
      size,
      color: teal,
      opacity: 0.22,
      cx: 0.85,
      cy: 0.10,
      rx: 0.50,
      ry: 0.40,
      stop: 0.62,
    );
    _paintBloom(
      canvas,
      size,
      color: pink,
      opacity: 0.18,
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

  @override
  bool shouldRepaint(covariant _DaylightLagoonPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.motionDisabled != motionDisabled ||
        oldDelegate.violet != violet ||
        oldDelegate.teal != teal ||
        oldDelegate.pink != pink;
  }
}
