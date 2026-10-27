import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// The three gestures the Orbit intro teaches, in order. Each one ends only
/// when the user really does it on the Orbit underneath.
enum OrbitIntroStep { spread, openDepth, turn }

/// A coach mark over the live Orbit: dimmed, one animated hand, a short line
/// and Skip. Only Skip takes touches, so every gesture reaches the Orbit.
class OrbitIntroOverlay extends StatefulWidget {
  const OrbitIntroOverlay({
    super.key,
    required this.step,
    required this.onSkip,
  });

  final OrbitIntroStep step;
  final VoidCallback onSkip;

  @override
  State<OrbitIntroOverlay> createState() => _OrbitIntroOverlayState();
}

class _OrbitIntroOverlayState extends State<OrbitIntroOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hand = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _hand
        ..stop()
        ..value = .6;
    } else if (!_hand.isAnimating) {
      _hand.repeat();
    }
  }

  @override
  void dispose() {
    _hand.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (title, body) = switch (widget.step) {
      OrbitIntroStep.spread => (
        l10n.orbit_intro_spread_title,
        l10n.orbit_intro_spread_body,
      ),
      OrbitIntroStep.openDepth => (
        l10n.orbit_intro_open_title,
        l10n.orbit_intro_open_body,
      ),
      OrbitIntroStep.turn => (
        l10n.orbit_intro_turn_title,
        l10n.orbit_intro_turn_body,
      ),
    };
    return Stack(
      key: ValueKey('orbit-intro-${widget.step.name}'),
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: ColoredBox(
            color: const Color(0x8C000000),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedBuilder(
                  animation: _hand,
                  builder: (context, _) => _Hand(
                    step: widget.step,
                    progress: Curves.easeInOut.transform(
                      (_hand.value / .7).clamp(0.0, 1.0),
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, .55),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFD7DBE0),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final step in OrbitIntroStep.values)
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: step == widget.step
                                      ? const Color(0xFF7FD8CC)
                                      : const Color(0xFF5A6270),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: AlignmentDirectional.topEnd,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextButton(
                key: const ValueKey('orbit-intro-skip'),
                onPressed: widget.onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0x24FFFFFF),
                  minimumSize: const Size(64, 44),
                ),
                child: Text(l10n.orbit_intro_skip),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Fingertips showing the step's gesture, [progress] 0..1 through it.
class _Hand extends StatelessWidget {
  const _Hand({required this.step, required this.progress});

  final OrbitIntroStep step;
  final double progress;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final center = Offset(
        constraints.maxWidth / 2,
        constraints.maxHeight * .4,
      );
      final tips = switch (step) {
        OrbitIntroStep.spread => [
          center + Offset(-14 - 30 * progress, -14 - 26 * progress),
          center + Offset(14 + 30 * progress, 14 + 26 * progress),
        ],
        OrbitIntroStep.openDepth => [center + Offset(0, -80 + 150 * progress)],
        OrbitIntroStep.turn => [center + Offset(70 - 140 * progress, 60)],
      };
      return Stack(
        children: [
          for (final tip in tips)
            Positioned(
              left: tip.dx - 18,
              top: tip.dy - 18,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xE6FFFFFF),
                  boxShadow: const [
                    BoxShadow(color: Color(0x2EFFFFFF), spreadRadius: 8),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
