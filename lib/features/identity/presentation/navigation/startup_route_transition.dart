import 'package:flutter/material.dart';

/// Builds the opaque fade used for startup route replacement.
///
/// Startup should feel visually still and intentional, not like a content
/// sheet sliding over a half-built screen.
PageRouteBuilder<T> buildStartupReplacementRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    opaque: true,
    transitionDuration: const Duration(milliseconds: 160),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final fade = Tween<double>(begin: 0.96, end: 1).animate(curved);

      return FadeTransition(opacity: fade, child: child);
    },
  );
}
