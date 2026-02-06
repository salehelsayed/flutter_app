import 'package:flutter/material.dart';

/// Animated checkmark with soft pulse rings.
class CheckmarkBurstAnimation extends StatefulWidget {
  final double size;

  const CheckmarkBurstAnimation({super.key, this.size = 84});

  @override
  State<CheckmarkBurstAnimation> createState() =>
      _CheckmarkBurstAnimationState();
}

class _CheckmarkBurstAnimationState extends State<CheckmarkBurstAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _iconController;
  late final AnimationController _ringsController;
  late final Animation<double> _iconScale;

  @override
  void initState() {
    super.initState();

    _iconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _iconScale = CurvedAnimation(
      parent: _iconController,
      curve: Curves.elasticOut,
    );

    _ringsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _iconController.forward();
    });
  }

  @override
  void dispose() {
    _iconController.dispose();
    _ringsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final centerSize = widget.size * 0.42;
    final iconSize = widget.size * 0.24;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _buildPulseRing(phase: 0.0, baseOpacity: 0.52),
          _buildPulseRing(phase: 0.24, baseOpacity: 0.42),
          _buildPulseRing(phase: 0.48, baseOpacity: 0.34),
          ScaleTransition(
            scale: _iconScale,
            child: Container(
              width: centerSize,
              height: centerSize,
              decoration: const BoxDecoration(
                color: Color(0xFF49C462),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x703FC75F),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                Icons.check_rounded,
                size: iconSize,
                color: const Color.fromRGBO(10, 34, 18, 0.95),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulseRing({required double phase, required double baseOpacity}) {
    return AnimatedBuilder(
      animation: _ringsController,
      builder: (context, child) {
        final t = (_ringsController.value + phase) % 1.0;
        final scale = 0.74 + (t * 0.58);
        final opacity = (1 - t) * baseOpacity;

        return Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: widget.size * 0.54,
              height: widget.size * 0.54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF43BE5D), width: 2),
              ),
            ),
          ),
        );
      },
    );
  }
}
