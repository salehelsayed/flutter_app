import 'package:flutter/material.dart';

/// One process-stable observer used by every direct-conversation route.
///
/// The same instance is registered with the root [MaterialApp] and exposed
/// below its builder so a [RouteAware] conversation never depends on an
/// entry-point-specific observer parameter.
final RouteObserver<ModalRoute<void>> directPrivateMediaRouteObserver =
    RouteObserver<ModalRoute<void>>();

class DirectPrivateMediaRouteObserverScope extends InheritedWidget {
  const DirectPrivateMediaRouteObserverScope({
    super.key,
    required this.observer,
    required super.child,
  });

  final RouteObserver<ModalRoute<void>> observer;

  static RouteObserver<ModalRoute<void>>? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<
            DirectPrivateMediaRouteObserverScope
          >()
          ?.observer;

  @override
  bool updateShouldNotify(DirectPrivateMediaRouteObserverScope oldWidget) =>
      !identical(observer, oldWidget.observer);
}
