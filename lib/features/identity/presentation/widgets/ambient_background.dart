import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background_mirrored.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

/// Shared app background that renders the selected ambient treatment.
class AmbientBackground extends StatefulWidget {
  final Widget child;
  final BackgroundPreference preference;
  final bool isFeedSurface;
  final BackgroundReadableTone? readableToneOverride;

  const AmbientBackground({
    super.key,
    required this.child,
    this.preference = BackgroundPreference.defaultBackground,
    this.isFeedSurface = false,
    this.readableToneOverride,
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
    );
    if (_usesDefaultBackground) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AmbientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_usesDefaultBackground && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_usesDefaultBackground && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = BackgroundReadableColors.resolve(
      widget.preference,
      representativeToneOverride: widget.readableToneOverride,
    );
    final theme = Theme.of(context);
    final themedBackground = switch (widget.preference) {
      BackgroundPreference.defaultBackground => _DefaultAmbientBackground(
        animation: _controller,
        child: widget.child,
      ),
      BackgroundPreference.cosmic => CosmicBackground(child: widget.child),
      BackgroundPreference.cosmicMirrored => CosmicBackgroundMirrored(
        child: widget.child,
      ),
      BackgroundPreference.daylightLagoon => DaylightLagoonBackground(
        child: widget.child,
      ),
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: readableColors.systemUiOverlayStyle,
      child: Theme(
        data: theme.copyWith(
          extensions: [
            ...theme.extensions.values.where(
              (extension) => extension is! BackgroundReadableColors,
            ),
            readableColors,
          ],
        ),
        child: themedBackground,
      ),
    );
  }

  bool get _usesDefaultBackground {
    return widget.preference == BackgroundPreference.defaultBackground;
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
