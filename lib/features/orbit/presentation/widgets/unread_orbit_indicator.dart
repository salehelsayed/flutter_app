import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';

/// 194 — per-node unread "messenger orbit" indicator, drawn as a tilted 3D
/// orbit (owner request 2026-11-10).
///
/// A thin green ellipse is tilted around the friend's avatar ([child]), with up
/// to three glowing dots, one per unread message, capped at 3, no numerals.
/// The back half of the orbit and the dots on it paint behind the avatar; the
/// front half and its dots paint in front, larger and brighter. A non-null
/// [thoughtStarColor] adds a four-point star on its own, opposite-tilted orbit
/// with no line: the friend has a thought the user has not opened.
///
/// Renders only [child] (no orbit, no ticker) when [unreadCount] `<= 0` and
/// there is no star, so parents may mount it unconditionally (INV-1). Motion is
/// a mixin-vsync'd controller (so the 163 off-screen pane mute applies) and
/// freezes under `MediaQuery.disableAnimations || accessibleNavigation` while
/// the orbit stays statically visible (INV-4). The orbit never hit-tests and
/// adds no semantics, so [child]'s taps and label are untouched (INV-2).
class UnreadOrbitIndicator extends StatefulWidget {
  /// The friend's unread message count. `<= 0` draws no orbit line or dots.
  final int unreadCount;

  /// The host avatar diameter; the orbit and dots scale from it.
  final double diameter;

  /// When false the motion is frozen (still statically visible). Combined
  /// with the widget's own reduce-motion read — either disables motion.
  final bool motionEnabled;

  /// Opt-in relationship colour used by the Orbital Quiet prototype.
  final Color accent;

  /// V2 replaces the revolving satellites with one restrained numeric badge.
  final bool showSatellites;
  final bool showCountBadge;

  /// Non-null when the friend has an unopened thought to show as a star. On a
  /// light background the star takes this colour (the friend's own); on a dark
  /// background it is gold.
  final Color? thoughtStarColor;

  /// The avatar the orbit is drawn around. Defaults to an empty box of
  /// [diameter].
  final Widget? child;

  const UnreadOrbitIndicator({
    super.key,
    required this.unreadCount,
    this.diameter = 38,
    this.motionEnabled = true,
    this.accent = kUnreadAccent,
    this.showSatellites = true,
    this.showCountBadge = false,
    this.thoughtStarColor,
    this.child,
  });

  /// The app's green unread accent (the `#1DB954` family shared with
  /// `UnreadCountBadge`). Deliberately theme-independent so the indicator reads
  /// as "unread" on both dark and light readable surfaces.
  static const Color kUnreadAccent = Color(0xFF1DB954);

  static const Color kInk = Color(0xFF0B0F19);

  @override
  State<UnreadOrbitIndicator> createState() => _UnreadOrbitIndicatorState();
}

/// One body on the tilted orbit at parameter [theta]: its offset from the
/// avatar center and its depth (`sin(theta)`, -1 farthest, +1 nearest).
class _OrbitBody {
  final Offset offset;
  final double depth;

  _OrbitBody(double theta, double a, double b, double tilt)
    : depth = sin(theta),
      offset = Offset(
        a * cos(theta) * cos(tilt) - b * sin(theta) * sin(tilt),
        a * cos(theta) * sin(tilt) + b * sin(theta) * cos(tilt),
      );

  bool get isBehind => depth < 0;
  double get scale => 0.875 + 0.325 * depth;
  double get opacity => 0.75 + 0.25 * depth;
}

class _UnreadOrbitIndicatorState extends State<UnreadOrbitIndicator>
    with SingleTickerProviderStateMixin {
  static const double _dotTilt = -18 * pi / 180;
  static const double _starTilt = 20 * pi / 180;
  static const Key _hostKey = ValueKey('unread-orbit-host');

  late final AnimationController _controller;

  int get _satelliteCount => min(widget.unreadCount, 3);

  bool get _hasOrbit =>
      widget.unreadCount > 0 || widget.thoughtStarColor != null;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
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
    final shouldAnimate = widget.motionEnabled && !reduceMotion && _hasOrbit;

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
    if (!_hasOrbit) {
      return widget.child ?? const SizedBox.shrink();
    }
    final lightSurface = context.backgroundReadableColors.isLightSurface;
    // The host is passed as the AnimatedBuilder child so only the orbit
    // rebuilds each frame — the avatar subtree is not rebuilt per tick
    // (TC-194-36).
    return AnimatedBuilder(
      animation: _controller,
      child: KeyedSubtree(
        key: _hostKey,
        child: widget.child ?? SizedBox.square(dimension: widget.diameter),
      ),
      builder: (context, host) =>
          _orbit(host!, _controller.value, lightSurface),
    );
  }

  Widget _orbit(Widget host, double t, bool lightSurface) {
    final a = widget.diameter / 2 + 10;
    final b = a * 0.32;
    final scale = widget.diameter / 48;
    final behind = <Widget>[];
    final inFront = <Widget>[];
    void place(_OrbitBody body, Widget visual) =>
        (body.isBehind ? behind : inFront).add(
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Transform.translate(
                  offset: body.offset,
                  child: Transform.scale(
                    scale: body.scale,
                    child: Opacity(opacity: body.opacity, child: visual),
                  ),
                ),
              ),
            ),
          ),
        );

    final showRing = widget.unreadCount > 0;
    if (showRing && widget.showSatellites) {
      final n = _satelliteCount;
      // Rest phases keep every dot clear of the avatar when motion is frozen:
      // with two dots the default would park one straight behind the face.
      final rest = pi / 2 + (n == 2 ? pi / 3 : 0);
      for (var i = 0; i < n; i++) {
        place(
          _OrbitBody(2 * pi * (t + i / n) + rest, a, b, _dotTilt),
          _dot(i, 7 * scale),
        );
      }
    }
    final starColor = widget.thoughtStarColor;
    if (starColor != null) {
      final twinkle = 0.975 + 0.175 * sin(4 * pi * t);
      place(
        _OrbitBody(2 * pi * t + pi / 6, a, b, _starTilt),
        Transform.scale(
          scale: twinkle,
          child: CustomPaint(
            key: const ValueKey('orbit-thought-star'),
            size: Size.square((lightSurface ? 16 : 14) * scale),
            painter: ThoughtStarPainter(
              friendColour: lightSurface ? starColor : null,
            ),
          ),
        ),
      );
    }

    UnreadOrbitRingPainter? ring({required bool front}) => showRing
        ? UnreadOrbitRingPainter(
            accent: widget.accent,
            semiMajor: a,
            semiMinor: b,
            tilt: _dotTilt,
            front: front,
          )
        : null;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        CustomPaint(
          painter: ring(front: false),
          foregroundPainter: ring(front: true),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [...behind, host],
          ),
        ),
        ...inFront,
        if (showRing && widget.showCountBadge)
          Positioned(
            key: const ValueKey('orbit-unread-count-badge'),
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
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
            ),
          ),
      ],
    );
  }

  Widget _dot(int index, double size) => Container(
    key: ValueKey('unread-satellite-$index'),
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: widget.accent,
      boxShadow: [
        BoxShadow(
          color: widget.accent.withValues(alpha: 0.55),
          blurRadius: size,
        ),
      ],
    ),
  );
}

/// Paints one half of the tilted orbit line: the back half under the avatar
/// ([front] false) or the front half over it. [accent] is the opaque base
/// green; the stroke alpha is applied here so tests can assert on the
/// configured accent field (not pixels) — TC-194-08.
class UnreadOrbitRingPainter extends CustomPainter {
  final Color accent;
  final double semiMajor;
  final double semiMinor;
  final double tilt;
  final bool front;

  UnreadOrbitRingPainter({
    required this.accent,
    required this.semiMajor,
    required this.semiMinor,
    required this.tilt,
    required this.front,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.55);
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(tilt)
      ..drawArc(
        Rect.fromCenter(
          center: Offset.zero,
          width: semiMajor * 2,
          height: semiMinor * 2,
        ),
        front ? 0 : pi,
        pi,
        false,
        line,
      )
      ..restore();
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant UnreadOrbitRingPainter old) =>
      old.accent != accent ||
      old.semiMajor != semiMajor ||
      old.semiMinor != semiMinor ||
      old.tilt != tilt ||
      old.front != front;
}

/// The four-point thought star. Gold with a warm glow on dark backgrounds;
/// on light backgrounds [friendColour] with a thin white outline and a soft
/// halo of the same colour.
class ThoughtStarPainter extends CustomPainter {
  static const Color darkFill = Color(0xFFFFF4CC);

  final Color? friendColour;

  ThoughtStarPainter({this.friendColour});

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final star = Path()
      ..moveTo(12, 1)
      ..lineTo(14.6, 9.4)
      ..lineTo(23, 12)
      ..lineTo(14.6, 14.6)
      ..lineTo(12, 23)
      ..lineTo(9.4, 14.6)
      ..lineTo(1, 12)
      ..lineTo(9.4, 9.4)
      ..close();
    canvas
      ..save()
      ..scale(k);
    final colour = friendColour;
    if (colour == null) {
      canvas
        ..drawPath(star, _glow(const Color(0xD9FFC850), 6))
        ..drawPath(star, _glow(const Color(0xFFFFE08A), 2.6))
        ..drawPath(star, Paint()..color = darkFill);
    } else {
      canvas
        ..drawPath(star, _glow(colour.withValues(alpha: 0.45), 2.25))
        ..drawPath(
          star,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.white,
        )
        ..drawPath(star, Paint()..color = colour);
    }
    canvas.restore();
  }

  /// [sigma] is in the star's 24-unit space; the canvas scale carries it to
  /// the drawn size.
  Paint _glow(Color color, double sigma) => Paint()
    ..color = color
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant ThoughtStarPainter old) =>
      old.friendColour != friendColour;
}
