import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
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

  /// 134 §7 app-level reduced-motion opt-in for the feed surface: when true the
  /// Aurora ambient loop does NOT start its infinite repeat() and the static
  /// glow frame is rendered instead.
  ///
  /// 156 QW-3: the OS reduce-motion preference (`MediaQuery.disableAnimations` /
  /// `accessibleNavigation`) is now ALSO honored on every ambient surface,
  /// independently of this flag (see [_AmbientBackgroundState._shouldAnimate]).
  /// This flag remains the feed's explicit override.
  final bool reduceMotion;

  /// 158 (`critic-2`): steady-state idle-animation suppression for the chat/group
  /// surfaces. When true the Aurora ambient loop does NOT start its
  /// infinite repeat() — the static glow frame is rendered instead — so the
  /// always-mounted chrome `BackdropFilter`s (header/composer/group panel) sit in
  /// front of a STILL backdrop and become cacheable at rest. Distinct from
  /// [reduceMotion] (accessibility, feed-only) and the OS reduce-motion gate
  /// (156 QW-3): this is the default (motion-on) chat-surface perf axis. Defaults
  /// to false; ONLY the two chat call sites opt in (see
  /// [_AmbientBackgroundState._shouldAnimate]).
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
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  /// 156 QW-3: OS reduce-motion preference, read from MediaQuery in
  /// [didChangeDependencies] (mirrors cosmic_background).
  bool _motionDisabled = false;

  @override
  void initState() {
    super.initState();
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 156 QW-3: honor OS reduce-motion on EVERY ambient surface (previously only
  /// the feed surface, via [AmbientBackground.reduceMotion], honored it). Reads
  /// `disableAnimations` / `accessibleNavigation` like cosmic_background and
  /// starts/stops the ambient loop. SCOPED to this widget only — the production
  /// friend-profile and first-open orbits run their own `..repeat()` controllers
  /// and are intentionally NOT gated here (user-required).
  void _syncMotionPreference() {
    final mediaQuery = MediaQuery.maybeOf(context);
    _motionDisabled =
        (mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false);

    if (_shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_shouldAnimate && _controller.isAnimating) {
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
    final themedBackground = switch (widget.preference) {
      BackgroundPreference.defaultBackground => CosmicBackgroundMirrored(
        child: widget.child,
      ),
      BackgroundPreference.cosmic => CosmicBackground(child: widget.child),
      BackgroundPreference.aurora => _DefaultAmbientBackground(
        animation: _controller,
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
              (extension) =>
                  extension is! BackgroundReadableColors &&
                  extension is! FeedTokens,
            ),
            readableColors,
            feedTokens,
          ],
        ),
        child: themedBackground,
      ),
    );
  }

  bool get _usesGlowBackground {
    return widget.preference == BackgroundPreference.aurora;
  }

  /// The Aurora ambient loop runs UNLESS (a) the preference is not the glow
  /// treatment, (b) this is a chat/group surface (158 critic-2:
  /// idle-glow suppression so the always-mounted chrome BackdropFilters stay
  /// cacheable at rest), (c) this is the feed surface AND [reduceMotion] is
  /// requested, or (d) the OS reduce-motion preference is on (156 QW-3, applies
  /// to ALL ambient surfaces). Each clause is additive (OR-combined) — none
  /// short-circuits another. When gated off the controller stays at value 0 →
  /// the static final glow frame is rendered.
  bool get _shouldAnimate {
    if (!_usesGlowBackground) return false;
    if (widget.isChatSurface) return false;
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
