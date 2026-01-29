import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

/// Animated ambient background with floating glow orbs.
class AmbientBackground extends StatefulWidget {
  final Widget child;

  const AmbientBackground({
    super.key,
    required this.child,
  });

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Stack(
        children: [
          // Green glow - top left
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = _controller.value;
              final xOffset = math.sin(value * 2 * math.pi) * 30;
              final yOffset = math.cos(value * 2 * math.pi) * 20;
              return Positioned(
                top: -100 + yOffset,
                left: -100 + xOffset,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.greenGlow.withValues(alpha: 0.3),
                        AppColors.greenGlow.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // Red glow - bottom right
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = _controller.value;
              final xOffset = math.cos(value * 2 * math.pi) * 25;
              final yOffset = math.sin(value * 2 * math.pi) * 30;
              return Positioned(
                bottom: -100 + yOffset,
                right: -100 + xOffset,
                child: Container(
                  width: 350,
                  height: 350,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.redGlow.withValues(alpha: 0.25),
                        AppColors.redGlow.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // Child content
          widget.child,
        ],
      ),
    );
  }
}
