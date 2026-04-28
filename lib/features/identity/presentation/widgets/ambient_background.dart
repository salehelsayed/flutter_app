import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

/// Animated ambient background with floating glow orbs.
class AmbientBackground extends StatefulWidget {
  final Widget child;
  final BackgroundPreference preference;

  const AmbientBackground({
    super.key,
    required this.child,
    this.preference = BackgroundPreference.defaultBackground,
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
    switch (widget.preference) {
      case BackgroundPreference.defaultBackground:
        return _DefaultAmbientBackground(
          animation: _controller,
          child: widget.child,
        );
    }
  }
}

class _DefaultAmbientBackground extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _DefaultAmbientBackground({
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Stack(
        children: [
          // Green glow - top left
          AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final value = animation.value;
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
            animation: animation,
            builder: (context, child) {
              final value = animation.value;
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
          child,
        ],
      ),
    );
  }
}
