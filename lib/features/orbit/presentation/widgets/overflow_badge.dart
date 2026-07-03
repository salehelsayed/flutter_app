import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// "+N" circle badge shown on the outer ring when the inner circle overflows 13.
///
/// 198 — the badge is now a TOGGLE: tapping it reveals/hides the overflow arcs
/// ([onTap]). It shows a chevron in the open state ([expanded]), carries a
/// localized plural Semantics label, floors its hit target to 44pt (a −8px inset
/// around the 28px visual), and gates its delayed entrance on reduce-motion.
/// It NEVER opens a chat (INV-1).
class OverflowBadge extends StatefulWidget {
  final int count;

  /// True while the overflow arcs are revealed — swaps "+N" for a chevron and
  /// switches the Semantics label to the collapse affordance.
  final bool expanded;

  /// Toggles the arcs. When null the badge is a passive indicator (legacy).
  final VoidCallback? onTap;

  const OverflowBadge({
    super.key,
    required this.count,
    this.expanded = false,
    this.onTap,
  });

  @override
  State<OverflowBadge> createState() => _OverflowBadgeState();
}

class _OverflowBadgeState extends State<OverflowBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _entranceScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.ease);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entranceScheduled) return;
    _entranceScheduled = true;
    // 198 INV-7 — honor OS reduce-motion: appear instantly, no entrance frames.
    final mq = MediaQuery.maybeOf(context);
    final motionEnabled = !((mq?.disableAnimations ?? false) ||
        (mq?.accessibleNavigation ?? false));
    if (motionEnabled) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final surfaceColor = readableColors.isLightSurface
        ? readableColors.surfaceSubtle.withValues(alpha: 0.82)
        : readableColors.glassSurface;
    final borderColor = readableColors.border.withValues(
      alpha: readableColors.isLightSurface ? 0.28 : 0.20,
    );

    final visual = ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: surfaceColor,
            border: Border.all(
              color: borderColor,
              width: 1,
              style: BorderStyle.none, // dashed via paint
            ),
          ),
          child: CustomPaint(
            painter: _DashedBorderPainter(color: borderColor),
            child: Center(
              child: Text(
                widget.expanded ? '⌄' : '+${widget.count}',
                style: TextStyle(
                  fontSize: widget.expanded ? 14 : 10,
                  fontWeight: FontWeight.w600,
                  color: readableColors.textMuted,
                  letterSpacing: -0.5,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // 44pt hit target: a −8px inset around the 28px visual. The Semantics label
    // is localized + plural; the badge is a button, never a chat entry.
    Widget interactive = visual;
    if (widget.onTap != null) {
      final l10n = AppLocalizations.of(context)!;
      interactive = Semantics(
        button: true,
        label: widget.expanded
            ? l10n.orbit_overflow_badge_collapse
            : l10n.orbit_overflow_badge_open(widget.count),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: visual),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Opacity(opacity: _animation.value, child: child),
        );
      },
      child: interactive,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;

  const _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const dashLength = 4.0;
    const gapLength = 3.0;
    final circumference = 2 * 3.14159 * radius;
    final totalDashes = (circumference / (dashLength + gapLength)).floor();

    for (var i = 0; i < totalDashes; i++) {
      final startAngle =
          (i * (dashLength + gapLength) / circumference) * 2 * 3.14159;
      final sweepAngle = (dashLength / circumference) * 2 * 3.14159;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
