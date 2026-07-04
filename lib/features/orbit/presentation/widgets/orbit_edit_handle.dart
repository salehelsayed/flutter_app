import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';

/// 198 fidelity — one geometry-anchored edit handle (mockup `.handle`,
/// html:192-228): a glowing circular disc (30px at default scale; 203 B3
/// scales it with the avatar-size knob via [effectiveDiscSize]) with a
/// per-knob stroke icon, seated ON the orbit geometry by the host surface,
/// with an always-visible tip-pill (localized name + letter-free direction
/// glyph) hanging below.
///
/// Unarmed: green border + a breathing green halo (`pulseH`). Armed: static
/// teal halo + translucent teal fill — "the +/− steppers are wired to me".
/// The pulse honors OS reduce-motion via the house `_syncMotionPreference`
/// idiom (donor: unread_orbit_indicator.dart) and freezes at its resting
/// glow, keeping the handle fully visible.
///
/// The pan/tap [GestureDetector] itself carries
/// `ValueKey('orbit-handle-<knob>')` — tests and the F13 perf harness target
/// that key; never move or rename it.
class OrbitEditHandle extends StatefulWidget {
  final OrbitKnob knob;

  /// Localized knob name (`orbit_handle_*`) — tip-pill copy AND the handle's
  /// one Semantics label. Glyphs never enter it.
  final String label;
  final bool armed;

  /// 202: false while the host band-hides this handle (Offstage). The pulse
  /// freezes (drops its ticker) when invisible, so an off-band handle costs
  /// nothing per frame — the element stays MOUNTED (TC-198-71 / TC-202-05).
  final bool visible;

  /// 203 B3 — RAW avatarScale from the live geometry. The disc, glow and icon
  /// derive from ONE [effectiveDiscSize]; the interactive box ([hitTarget]),
  /// the Positioned centring and the tip-pill offset NEVER scale.
  final double scale;

  final VoidCallback onArm;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final VoidCallback? onPanCancel;

  const OrbitEditHandle({
    super.key,
    required this.knob,
    required this.label,
    required this.armed,
    this.visible = true,
    this.scale = 1.0,
    required this.onArm,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    this.onPanCancel,
  });

  /// The interactive box the host centres on the geometry anchor (INV-F7).
  static const double hitTarget = 44.0;

  /// Visual disc diameter at default scale (mockup 30px) — see
  /// [effectiveDiscSize] for the rendered size.
  static const double discSize = 30.0;

  /// 203 B3 — the ONE shared disc-size helper: raw avatarScale in, rendered
  /// disc diameter out, clamped to [24, 42]. The host's bubble clamp uses it
  /// too, so the bubble always hugs the disc actually painted.
  static double effectiveDiscSize(double scale) =>
      (discSize * scale).clamp(24.0, 42.0);

  @override
  State<OrbitEditHandle> createState() => _OrbitEditHandleState();
}

class _OrbitEditHandleState extends State<OrbitEditHandle>
    with SingleTickerProviderStateMixin {
  // Mockup palette: unarmed green terminal, armed teal.
  static const _greenBorder = Color(0xFF1ED760);
  static const _greenFill = Color(0xEB14281C);
  static const _greenHalo = Color(0xCC1DB954);
  static const _greenIcon = Color(0xFFB9F6CA);
  static const _tealBorder = Color(0xFF4ECDC4);
  static const _tealFill = Color(0x4D4ECDC4);
  static const _tealHalo = Color(0xCC4ECDC4);
  static const _tealIcon = Color(0xFFE0FFFA);
  static const _tipTextGreen = Color(0xFFD9F7E4);
  static const _tipTextTeal = Color(0xFFD8FFF9);
  static const _tipFillGreen = Color(0xEB0A140E);
  static const _tipFillTeal = Color(0xF0081814);
  static const _tipBorderGreen = Color(0x731DB954);
  static const _tipBorderTeal = Color(0x994ECDC4);

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionPreference();
  }

  @override
  void didUpdateWidget(covariant OrbitEditHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotionPreference();
  }

  /// House ambient-motion convention (unread_orbit_indicator.dart:79-95):
  /// freeze + pin to the resting glow under OS reduce-motion or while armed
  /// (the armed halo is static in the mockup); otherwise repeat idempotently.
  void _syncMotionPreference() {
    final mediaQuery = MediaQuery.maybeOf(context);
    final reduceMotion = (mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false);
    // 202: a band-hidden handle freezes too — no ticker off-band (TC-202-05).
    final shouldAnimate = !widget.armed && !reduceMotion && widget.visible;
    if (!shouldAnimate) {
      _pulse.stop();
      _pulse.value = 0;
      return;
    }
    if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final armed = widget.armed;
    final effectiveDisc = OrbitEditHandle.effectiveDiscSize(widget.scale);
    final factor = effectiveDisc / OrbitEditHandle.discSize;
    final glyph = widget.knob == OrbitKnob.maxPerArc ? '⟷' : '↕';
    final tipStyle = TextStyle(
      fontSize: 9.5,
      fontWeight: FontWeight.w600,
      color: armed ? _tipTextTeal : _tipTextGreen,
      height: 1,
    );

    return SizedBox(
      width: OrbitEditHandle.hitTarget,
      height: OrbitEditHandle.hitTarget,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Semantics(
            // container so the handle OWNS its node — exactly one announced
            // button per handle (TC-198-56), tap action merged from the
            // detector below.
            container: true,
            button: true,
            label: widget.label,
            child: GestureDetector(
              key: ValueKey('orbit-handle-${widget.knob.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.onArm,
              onPanStart: widget.onPanStart,
              onPanUpdate: widget.onPanUpdate,
              onPanEnd: widget.onPanEnd,
              onPanCancel: widget.onPanCancel,
              child: Center(
                child: SizedBox(
                  width: effectiveDisc,
                  height: effectiveDisc,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // 202 INV-202-1: the breathing halo is a pre-rasterized
                      // max-size shadow whose OPACITY cross-fades — a constant
                      // raster cost instead of a per-frame Gaussian re-blur.
                      // Unarmed only; the armed handle keeps its static teal
                      // halo on the disc below.
                      if (!armed)
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, child) {
                            // pulseH keyframes: rest → peak → rest per period.
                            final wave = 0.5 -
                                0.5 * math.cos(2 * math.pi * _pulse.value);
                            return Opacity(
                              key: ValueKey(
                                  'orbit-handle-halo-${widget.knob.name}'),
                              opacity: wave.clamp(0.0, 1.0),
                              child: child,
                            );
                          },
                          child: RepaintBoundary(
                            child: Container(
                              width: effectiveDisc,
                              height: effectiveDisc,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  // Peak of the old breathing range
                                  // (rest 10/1 → peak 22/5), rasterized once.
                                  BoxShadow(
                                    color: _greenHalo,
                                    blurRadius: 22 * factor,
                                    spreadRadius: 5 * factor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // The disc: a CONSTANT resting (unarmed) / static (armed)
                      // shadow — no per-frame blur re-raster.
                      Container(
                        key: ValueKey('orbit-handle-disc-${widget.knob.name}'),
                        width: effectiveDisc,
                        height: effectiveDisc,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: armed ? _tealFill : _greenFill,
                          border: Border.all(
                            color: armed ? _tealBorder : _greenBorder,
                            width: 2,
                          ),
                          boxShadow: [
                            if (armed)
                              BoxShadow(
                                color: _tealHalo,
                                blurRadius: 20 * factor,
                                spreadRadius: 4 * factor,
                              )
                            else
                              // Resting halo (wave = 0 values) held constant.
                              BoxShadow(
                                color: _greenHalo,
                                blurRadius: 10 * factor,
                                spreadRadius: 1 * factor,
                              ),
                          ],
                        ),
                        child: Center(
                          child: CustomPaint(
                            key: ValueKey(
                                'orbit-handle-icon-${widget.knob.name}'),
                            // The painter normalizes by size/24, so the scaled
                            // box scales the strokes with it.
                            size: Size(16 * factor, 16 * factor),
                            painter: OrbitHandleIconPainter(
                              knob: widget.knob,
                              color: armed ? _tealIcon : _greenIcon,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Tip-pill below the disc: informative only — no hits, and excluded
          // from semantics so the handle announces exactly once (TC-198-56).
          Positioned(
            top: OrbitEditHandle.hitTarget + 4,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: armed ? _tipFillTeal : _tipFillGreen,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: armed ? _tipBorderTeal : _tipBorderGreen,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.label, style: tipStyle),
                      const SizedBox(width: 4),
                      Text(glyph, style: tipStyle),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The five 16px stroke glyphs (mockup html:1025-1038), drawn in a 24-unit
/// viewBox scaled to [size]. Carries its [knob] so a swapped icon assignment
/// re-reds the widget test.
class OrbitHandleIconPainter extends CustomPainter {
  final OrbitKnob knob;
  final Color color;

  const OrbitHandleIconPainter({required this.knob, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (knob) {
      case OrbitKnob.spacingScale: // vertical double-headed arrow
        path.moveTo(12 * s, 4 * s);
        path.lineTo(12 * s, 20 * s);
        path.moveTo(8 * s, 8 * s);
        path.lineTo(12 * s, 4 * s);
        path.lineTo(16 * s, 8 * s);
        path.moveTo(8 * s, 16 * s);
        path.lineTo(12 * s, 20 * s);
        path.lineTo(16 * s, 16 * s);
      case OrbitKnob.avatarScale: // circle
        path.addOval(
            Rect.fromCircle(center: Offset(12 * s, 12 * s), radius: 7 * s));
      case OrbitKnob.arcWrap: // single arch
        path.moveTo(4 * s, 16 * s);
        path.quadraticBezierTo(12 * s, 6 * s, 20 * s, 16 * s);
      case OrbitKnob.maxPerArc: // rightward arrow
        path.moveTo(4 * s, 12 * s);
        path.lineTo(20 * s, 12 * s);
        path.moveTo(14 * s, 6 * s);
        path.lineTo(20 * s, 12 * s);
        path.lineTo(14 * s, 18 * s);
      case OrbitKnob.orbitGap: // two arches + radial tie
        path.moveTo(4 * s, 8 * s);
        path.quadraticBezierTo(12 * s, 2 * s, 20 * s, 8 * s);
        path.moveTo(4 * s, 21 * s);
        path.quadraticBezierTo(12 * s, 15 * s, 20 * s, 21 * s);
        path.moveTo(12 * s, 10 * s);
        path.lineTo(12 * s, 17 * s);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant OrbitHandleIconPainter oldDelegate) =>
      oldDelegate.knob != knob || oldDelegate.color != color;
}
