import 'dart:math';
import 'package:flutter/material.dart';

/// 194 — per-node unread "messenger orbit" indicator (approved mockup B).
///
/// A thin green accent ring hugging a friend's orbital avatar with up to three
/// glowing satellites revolving around it — one satellite per unread message,
/// capped at 3, no numerals. The visual vocabulary is borrowed from the
/// contact-profile hero orbit (`_OrbitRingsPainter`), sped up to ~9s so it reads
/// as *activity*.
///
/// Renders nothing (not merely invisible) when [unreadCount] `<= 0` and starts
/// no live ticker in that state, so parents may mount it unconditionally
/// (INV-1). Rotation is a mixin-vsync'd controller (so the 163 off-screen pane
/// mute applies) and freezes under `MediaQuery.disableAnimations ||
/// accessibleNavigation` while the ring + satellites stay statically visible
/// (INV-4). Never affects hit-testing — the parent mounts it behind
/// `IgnorePointer` (INV-2).
class UnreadOrbitIndicator extends StatefulWidget {
  /// The friend's unread message count. `<= 0` renders nothing.
  final int unreadCount;

  /// The host avatar diameter; the ring + satellites scale from it.
  final double diameter;

  /// When false the rotation is frozen (still statically visible). Combined
  /// with the widget's own reduce-motion read — either disables motion.
  final bool motionEnabled;

  /// Opt-in relationship colour used by the Orbital Quiet prototype.
  final Color accent;

  /// V2 replaces the revolving satellites with one restrained numeric badge.
  final bool showSatellites;
  final bool showCountBadge;

  const UnreadOrbitIndicator({
    super.key,
    required this.unreadCount,
    this.diameter = 38,
    this.motionEnabled = true,
    this.accent = kUnreadAccent,
    this.showSatellites = true,
    this.showCountBadge = false,
  });

  /// The app's green unread accent (the `#1DB954` family shared with
  /// `UnreadCountBadge`). Deliberately theme-independent so the indicator reads
  /// as "unread" on both dark and light readable surfaces.
  static const Color kUnreadAccent = Color(0xFF1DB954);

  @override
  State<UnreadOrbitIndicator> createState() => _UnreadOrbitIndicatorState();
}

class _UnreadOrbitIndicatorState extends State<UnreadOrbitIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Donor satellite phases (contact_profile_screen.dart), fixed relative angles.
  static const List<double> _satelliteAngles = [0.6, 3.3, 5.1];

  int get _satelliteCount => min(widget.unreadCount, 3);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionPreference();
  }

  @override
  void didUpdateWidget(covariant UnreadOrbitIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotionPreference();
  }

  /// Mirrors the ambient-motion convention (cosmic_background._syncMotionPreference):
  /// freeze + pin to 0 when reduce-motion is on, the widget opts out, or there
  /// is nothing to show; otherwise repeat idempotently.
  void _syncMotionPreference() {
    final mediaQuery = MediaQuery.maybeOf(context);
    final reduceMotion =
        (mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false);
    final shouldAnimate =
        widget.motionEnabled && !reduceMotion && widget.unreadCount > 0;

    if (!shouldAnimate) {
      _controller.stop();
      _controller.value = 0;
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.unreadCount <= 0) {
      return const SizedBox.shrink();
    }

    final avatarRadius = widget.diameter / 2;
    final ringRadius = avatarRadius * 1.35;
    final coreRadius = widget.diameter * 0.06;
    final haloReach = coreRadius * 2.6;
    // Box must contain the ring plus the outermost satellite halo.
    final boxSize = (ringRadius + haloReach) * 2;
    final center = boxSize / 2;

    final field = Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: UnreadOrbitRingPainter(
              accent: widget.accent,
              ringRadius: ringRadius,
            ),
          ),
        ),
        if (widget.showSatellites)
          for (var i = 0; i < _satelliteCount; i++)
            _satellite(
              index: i,
              center: center,
              ringRadius: ringRadius,
              coreRadius: coreRadius,
              haloReach: haloReach,
            ),
      ],
    );

    final rotatingField = AnimatedBuilder(
      animation: _controller,
      child: field,
      builder: (context, child) =>
          Transform.rotate(angle: _controller.value * 2 * pi, child: child),
    );

    return SizedBox(
      width: boxSize,
      height: boxSize,
      // The rotating field is passed as the AnimatedBuilder child so only the
      // Transform rebuilds each frame — the ring/satellites (and, in the host,
      // the avatar) are not rebuilt per tick (TC-194-36).
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: rotatingField),
          if (widget.showCountBadge)
            Positioned(
              key: const ValueKey('orbit-unread-count-badge'),
              right: 0,
              top: 0,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${widget.unreadCount}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _satellite({
    required int index,
    required double center,
    required double ringRadius,
    required double coreRadius,
    required double haloReach,
  }) {
    final angle = _satelliteAngles[index];
    final dx = center + ringRadius * cos(angle);
    final dy = center + ringRadius * sin(angle);
    final boxSize = haloReach * 2;
    return Positioned(
      left: dx - boxSize / 2,
      top: dy - boxSize / 2,
      child: SizedBox(
        width: boxSize,
        height: boxSize,
        child: Center(
          child: Container(
            key: ValueKey('unread-satellite-$index'),
            width: coreRadius * 2,
            height: coreRadius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.accent,
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: 0.16),
                  blurRadius: coreRadius * 1.6,
                  spreadRadius: coreRadius * 1.6,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the single thin accent ring hugging the node. [accent] is the opaque
/// base green; the stroke alpha is applied here so tests can assert on the
/// configured accent field (not pixels) — TC-194-08.
class UnreadOrbitRingPainter extends CustomPainter {
  final Color accent;
  final double ringRadius;

  UnreadOrbitRingPainter({required this.accent, required this.ringRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = accent.withValues(alpha: 0.55);
    canvas.drawCircle(center, ringRadius, ring);
  }

  @override
  bool shouldRepaint(covariant UnreadOrbitRingPainter old) =>
      old.accent != accent || old.ringRadius != ringRadius;
}
