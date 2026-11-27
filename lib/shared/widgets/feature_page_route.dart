import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Platform navigation for Feed, Orbit, and Settings.
class FeaturePageRoute<T> extends MaterialPageRoute<T> {
  FeaturePageRoute({required super.builder, super.settings});

  static const _fadeDuration = Duration(milliseconds: 200);

  bool get _reduceMotion {
    final context = navigator?.context;
    return context != null && MediaQuery.disableAnimationsOf(context);
  }

  bool get _usesCupertino {
    final context = navigator?.context;
    return context != null && Theme.of(context).platform == TargetPlatform.iOS;
  }

  @override
  Duration get transitionDuration {
    if (_reduceMotion) return _fadeDuration;
    if (_usesCupertino)
      return CupertinoRouteTransitionMixin.kTransitionDuration;
    return const Duration(milliseconds: 420);
  }

  @override
  Duration get reverseTransitionDuration {
    if (_reduceMotion) return _fadeDuration;
    if (_usesCupertino)
      return CupertinoRouteTransitionMixin.kTransitionDuration;
    return const Duration(milliseconds: 280);
  }

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _usesCupertino && !_reduceMotion ? super.delegatedTransition : null;

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) =>
      !_reduceMotion &&
      (!_usesCupertino || super.canTransitionFrom(previousRoute));

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      // Keep the native edge gesture while reducing its visual effect to a fade.
      final cupertino = CupertinoRouteTransitionMixin.buildPageTransitions<T>(
        this,
        context,
        reduceMotion ? kAlwaysCompleteAnimation : animation,
        reduceMotion ? kAlwaysDismissedAnimation : secondaryAnimation,
        child,
      );
      return reduceMotion
          ? FadeTransition(opacity: animation, child: cupertino)
          : cupertino;
    }
    if (reduceMotion) return FadeTransition(opacity: animation, child: child);

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(curved);
    final fade = Tween<double>(begin: 0.92, end: 1).animate(curved);
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}
