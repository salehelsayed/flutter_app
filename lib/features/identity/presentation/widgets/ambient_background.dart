import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/app_shell_theme_binding.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
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

  /// Uses the static Aurora glow on the feed. Every background also follows
  /// the saved and OS motion preferences.
  final bool reduceMotion;

  /// Uses static ambient artwork behind direct and group chat so the header
  /// and composer backdrop filters can remain idle. Chat content retains its
  /// own animation and accessibility settings.
  final bool isChatSurface;

  const AmbientBackground({
    super.key,
    required this.child,
    this.preference = BackgroundPreference.defaultBackground,
    this.isFeedSurface = false,
    this.readableToneOverride,
    this.reduceMotion = false,
    this.isChatSurface = false,
  });

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;

  /// Motion policy for the ambient artwork.
  bool _motionDisabled = false;
  bool _appResumed = true;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appResumed = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    // The repeat/stop decision is made in didChangeDependencies once MediaQuery
    // (disableAnimations) is available.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionPreference();
  }

  @override
  void didUpdateWidget(covariant AmbientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotionPreference();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (_appResumed == resumed) return;
    setState(() {
      _appResumed = resumed;
      _syncMotionPreference();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  /// Applies the chat, OS, and saved background settings. Lifecycle and route
  /// pauses preserve phase. Content keeps its original MediaQuery.
  void _syncMotionPreference() {
    final mediaQuery = MediaQuery.maybeOf(context);
    _motionDisabled =
        widget.isChatSurface ||
        !BackgroundMotionScope.enabledOf(context) ||
        (mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false);

    final animate = _shouldAnimate && !_temporarilyPaused;
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
    }
    if (!_shouldAnimate) {
      // Render the static final glow frame instead of a frozen mid-loop frame.
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = BackgroundReadableColors.resolve(
      widget.preference,
      representativeToneOverride: widget.readableToneOverride,
    );
    final feedTokens = readableColors.isLightSurface
        ? FeedTokens.light
        : FeedTokens.dark;
    final theme = Theme.of(context);
    final originalMediaQuery =
        MediaQuery.maybeOf(context) ?? const MediaQueryData();
    final content = MediaQuery(data: originalMediaQuery, child: widget.child);
    final themedBackground = switch (widget.preference) {
      BackgroundPreference.defaultBackground => CosmicBackgroundMirrored(
        paused: _temporarilyPaused,
        child: content,
      ),
      BackgroundPreference.cosmic => CosmicBackground(
        paused: _temporarilyPaused,
        child: content,
      ),
      BackgroundPreference.aurora => _DefaultAmbientBackground(
        animation: _controller,
        child: content,
      ),
      BackgroundPreference.daylightLagoon => DaylightLagoonBackground(
        child: content,
      ),
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: readableColors.systemUiOverlayStyle,
      child: Theme(
        data: theme.copyWith(
          extensions: [
            ...theme.extensions.values.where(
              (extension) =>
                  extension is! BackgroundReadableColors &&
                  extension is! FeedTokens,
            ),
            readableColors,
            feedTokens,
          ],
        ),
        child: MediaQuery(
          data: originalMediaQuery.copyWith(disableAnimations: _motionDisabled),
          child: themedBackground,
        ),
      ),
    );
  }

  bool get _usesGlowBackground {
    return widget.preference == BackgroundPreference.aurora;
  }

  bool get _temporarilyPaused =>
      !_appResumed || !TickerMode.valuesOf(context).enabled;

  /// Aurora uses its static glow when the shared background policy or the
  /// feed's explicit reduced-motion setting disables motion.
  bool get _shouldAnimate {
    if (!_usesGlowBackground) return false;
    if (widget.isFeedSurface && widget.reduceMotion) return false;
    if (_motionDisabled) return false;
    return true;
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
          // Green glow - top left. 156 QW-2: the constant gradient Container is
          // hoisted into the AnimatedBuilder's `child` (built once) and wrapped
          // in a RepaintBoundary so the per-frame work is just re-positioning a
          // cached layer, not re-rasterizing the gradient.
          AnimatedBuilder(
            animation: animation,
            child: RepaintBoundary(
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
            ),
            builder: (context, child) {
              final value = animation.value;
              final xOffset = math.sin(value * 2 * math.pi) * 30;
              final yOffset = math.cos(value * 2 * math.pi) * 20;
              return Positioned(
                top: -100 + yOffset,
                left: -100 + xOffset,
                child: child!,
              );
            },
          ),
          // Red glow - bottom right.
          AnimatedBuilder(
            animation: animation,
            child: RepaintBoundary(
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
            ),
            builder: (context, child) {
              final value = animation.value;
              final xOffset = math.cos(value * 2 * math.pi) * 25;
              final yOffset = math.sin(value * 2 * math.pi) * 30;
              return Positioned(
                bottom: -100 + yOffset,
                right: -100 + xOffset,
                child: child!,
              );
            },
          ),
          // Child content. 156 QW-2: isolate the screen content in its own
          // RepaintBoundary so the animating glows never invalidate its raster.
          RepaintBoundary(child: child),
        ],
      ),
    );
  }
}
