import 'package:flutter/material.dart';
import 'package:flutter_app/core/notifications/app_visibility_route_binding.dart';

/// One process-stable observer used by every direct-conversation route.
///
/// The same instance is registered with the root [MaterialApp] and exposed
/// below its builder so a [RouteAware] conversation never depends on an
/// entry-point-specific observer parameter.
final RouteObserver<ModalRoute<void>> directPrivateMediaRouteObserver =
    AppVisibilityRouteObserver();

class DirectPrivateMediaRouteObserverScope extends InheritedWidget {
  const DirectPrivateMediaRouteObserverScope({
    super.key,
    required this.observer,
    this.appVisibilityRouteRegistry,
    required super.child,
  });

  final RouteObserver<ModalRoute<void>> observer;
  final AppVisibilityRouteRegistry? appVisibilityRouteRegistry;

  static RouteObserver<ModalRoute<void>>? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<
            DirectPrivateMediaRouteObserverScope
          >()
          ?.observer;

  static AppVisibilityRouteRegistry? maybeRegistryOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<
            DirectPrivateMediaRouteObserverScope
          >()
          ?.appVisibilityRouteRegistry;

  @override
  bool updateShouldNotify(DirectPrivateMediaRouteObserverScope oldWidget) =>
      !identical(observer, oldWidget.observer) ||
      !identical(
        appVisibilityRouteRegistry,
        oldWidget.appVisibilityRouteRegistry,
      );
}
