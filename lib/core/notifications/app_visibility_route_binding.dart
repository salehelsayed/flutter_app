import 'dart:async';

import 'package:flutter/material.dart';

import 'app_visibility_authority.dart';
import 'app_visibility_snapshot.dart';

/// A route that remains inside the exact conversation it covers.
///
/// The root [AppVisibilityRouteObserver] honors this marker only when the
/// immediately covered route is already registered for [identity]. A caller
/// therefore cannot manufacture chat visibility from settings (or inherit a
/// different chat) merely by pushing this route. Media viewers opened by a
/// conversation use this route so their transition never publishes an
/// intermediate `null` visibility value.
final class AppVisibilityInheritedConversationRoute<T>
    extends MaterialPageRoute<T> {
  AppVisibilityInheritedConversationRoute({
    required this.identity,
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
  });

  final AppVisibilityConversationIdentity identity;
}

/// The incumbent root observer, generalized with route removal/replacement
/// topology that Flutter's base [RouteObserver] does not deliver to RouteAware.
/// It remains one NavigatorObserver and preserves ordinary RouteAware behavior.
final class AppVisibilityRouteObserver extends RouteObserver<ModalRoute<void>> {
  final Map<ModalRoute<void>, _VisibilityRouteRegistration> _registrations =
      <ModalRoute<void>, _VisibilityRouteRegistration>{};
  final Set<ModalRoute<void>> _inheritedRoutes = <ModalRoute<void>>{};
  ModalRoute<void>? _topRoute;

  void registerVisibilityRoute({
    required ModalRoute<void> route,
    required Object owner,
    required AppVisibilityRouteRegistry registry,
    required AppVisibilityConversationIdentity identity,
  }) {
    _inheritedRoutes.remove(route);
    _registrations[route] = _VisibilityRouteRegistration(
      owner: owner,
      registry: registry,
      identity: identity,
    );
    if (identical(_topRoute, route) || route.isCurrent) {
      _topRoute = route;
      registry._becameTop(owner, identity);
    }
  }

  void unregisterVisibilityRoute({
    required ModalRoute<void> route,
    required Object owner,
  }) {
    final registration = _registrations[route];
    if (registration == null || !identical(registration.owner, owner)) return;
    _registrations.remove(route);
    if (identical(_topRoute, route)) {
      registration.registry._leftTop(owner);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final modalRoute = _modalRoute(route);
    _registerInheritedRoute(
      route: modalRoute,
      coveredRoute: _modalRoute(previousRoute),
      allowUnmarkedPopup: true,
    );
    super.didPush(route, previousRoute);
    _changeTop(modalRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (identical(_topRoute, route)) _changeTop(_modalRoute(previousRoute));
    _removeInheritedRoute(_modalRoute(route));
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (identical(_topRoute, route)) _changeTop(_modalRoute(previousRoute));
    _removeInheritedRoute(_modalRoute(route));
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final newModalRoute = _modalRoute(newRoute);
    final oldModalRoute = _modalRoute(oldRoute);
    _registerInheritedRoute(route: newModalRoute, coveredRoute: oldModalRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (identical(_topRoute, oldRoute)) _changeTop(newModalRoute);
    _removeInheritedRoute(oldModalRoute);
  }

  void _registerInheritedRoute({
    required ModalRoute<void>? route,
    required ModalRoute<void>? coveredRoute,
    bool allowUnmarkedPopup = false,
  }) {
    if (route == null) return;
    final covered = _registrations[coveredRoute];
    if (covered == null) return;

    if (route is AppVisibilityInheritedConversationRoute) {
      if (covered.identity != route.identity) return;
    } else if (!allowUnmarkedPopup || route is! PopupRoute) {
      return;
    }

    // Popup routes are transient overlays on the immediately covered route.
    // Only didPush enables this implicit inheritance; replacement stays
    // fail-closed unless it carries the exact explicit marker above.
    _registrations[route] = _VisibilityRouteRegistration(
      owner: route,
      registry: covered.registry,
      identity: covered.identity,
    );
    _inheritedRoutes.add(route);
  }

  void _removeInheritedRoute(ModalRoute<void>? route) {
    if (route == null || !_inheritedRoutes.remove(route)) return;
    _registrations.remove(route);
  }

  void _changeTop(ModalRoute<void>? nextRoute) {
    if (identical(_topRoute, nextRoute)) return;
    final previous = _registrations[_topRoute];
    final next = _registrations[nextRoute];
    if (previous != null &&
        next != null &&
        identical(previous.registry, next.registry) &&
        previous.identity == next.identity &&
        next.registry._handoffTop(
          fromOwner: previous.owner,
          toOwner: next.owner,
          identity: next.identity,
        )) {
      _topRoute = nextRoute;
      return;
    }
    if (previous != null) previous.registry._leftTop(previous.owner);
    _topRoute = nextRoute;
    if (next != null) next.registry._becameTop(next.owner, next.identity);
  }

  ModalRoute<void>? _modalRoute(Route<dynamic>? route) =>
      route is ModalRoute<void> ? route : null;
}

final class _VisibilityRouteRegistration {
  const _VisibilityRouteRegistration({
    required this.owner,
    required this.registry,
    required this.identity,
  });

  final Object owner;
  final AppVisibilityRouteRegistry registry;
  final AppVisibilityConversationIdentity identity;
}

/// Process-local top-route identity plus projection into the one durable
/// [AppVisibilityAuthority]. Top-route identity deliberately survives lifecycle
/// invalidation so notification-open dedupe never depends on freshness.
abstract interface class AppVisibilityTopRouteReader {
  AppVisibilityConversationIdentity? get currentTopConversation;

  bool isCurrentTopConversation(AppVisibilityConversationIdentity identity);

  bool isCurrentTopConversationValue({
    required AppVisibilityConversationLane lane,
    required String value,
  });
}

typedef ExactConversationActivationCleanup =
    Future<void> Function(AppVisibilityConversationIdentity identity);

final class AppVisibilityRouteRegistry implements AppVisibilityTopRouteReader {
  AppVisibilityRouteRegistry({
    required AppVisibilityAuthority authority,
    ExactConversationActivationCleanup? onExactConversationActivated,
  }) : _authority = authority,
       _onExactConversationActivated = onExactConversationActivated;

  final AppVisibilityAuthority _authority;
  final ExactConversationActivationCleanup? _onExactConversationActivated;
  Object? _topOwner;
  AppVisibilityConversationIdentity? _topConversation;
  Future<void> _lastProjection = Future<void>.value();
  Future<void> _lastActivationCleanup = Future<void>.value();
  bool _disposed = false;

  @override
  AppVisibilityConversationIdentity? get currentTopConversation =>
      _topConversation;

  @override
  bool isCurrentTopConversation(AppVisibilityConversationIdentity identity) =>
      _topConversation == identity;

  @override
  bool isCurrentTopConversationValue({
    required AppVisibilityConversationLane lane,
    required String value,
  }) {
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: lane,
      value: value,
    );
    return identity != null && isCurrentTopConversation(identity);
  }

  /// Republishes the process-local top route after native resume establishes a
  /// fresh lifecycle generation. A non-chat top route publishes a null key.
  Future<bool> republishCurrentTopConversation() async {
    if (_disposed) return false;
    final top = _topConversation;
    final projection = top == null
        ? _authority.clearVisibleConversation()
        : _authority.publishVisibleConversation(top);
    _track(projection);
    final committed = await projection;
    if (committed && top != null && _topConversation == top && !_disposed) {
      _scheduleActivationCleanup(top);
    }
    return committed;
  }

  /// Waits only for projections already issued by this registry. Intended for
  /// deterministic teardown/tests, not for lifecycle correctness.
  Future<void> settle() => Future.wait<void>(<Future<void>>[
    _lastProjection,
    _lastActivationCleanup,
  ]);

  void _becameTop(Object owner, AppVisibilityConversationIdentity identity) {
    if (_disposed) return;
    if (identical(_topOwner, owner) && _topConversation == identity) return;
    _topOwner = owner;
    _topConversation = identity;
    _track(_authority.publishVisibleConversation(identity));
    _scheduleActivationCleanup(identity);
  }

  void _leftTop(Object owner) {
    if (_disposed || !identical(_topOwner, owner)) return;
    _topOwner = null;
    _topConversation = null;
    _track(_authority.clearVisibleConversation());
  }

  bool _handoffTop({
    required Object fromOwner,
    required Object toOwner,
    required AppVisibilityConversationIdentity identity,
  }) {
    if (_disposed ||
        !identical(_topOwner, fromOwner) ||
        _topConversation != identity) {
      return false;
    }
    _topOwner = toOwner;
    return true;
  }

  void _track(Future<bool> projection) {
    _lastProjection = projection.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
  }

  void _scheduleActivationCleanup(AppVisibilityConversationIdentity identity) {
    final cleanup = _onExactConversationActivated;
    if (cleanup == null) return;
    final previous = _lastActivationCleanup;
    final current = Future<void>.sync(
      () => cleanup(identity),
    ).then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _lastActivationCleanup = Future.wait<void>(<Future<void>>[
      previous,
      current,
    ]);
  }

  void dispose() {
    if (_disposed) return;
    final hadTop = _topOwner != null;
    _disposed = true;
    _topOwner = null;
    _topConversation = null;
    if (hadTop) _track(_authority.clearVisibleConversation());
  }
}

/// Binds one conversation widget to the existing root RouteObserver.
///
/// The binding itself is [RouteAware], so callers do not need another mixin and
/// an existing screen-level RouteAware subscription can coexist on the same
/// route. Cover/pop/remove/replace events mutate only visibility eligibility;
/// this class has no read, notification-card, or cancellation dependency.
final class AppVisibilityRouteBinding extends StatefulWidget {
  const AppVisibilityRouteBinding({
    super.key,
    required this.registry,
    required this.identity,
    required this.observer,
    required this.child,
  });

  final AppVisibilityRouteRegistry registry;
  final AppVisibilityConversationIdentity identity;
  final RouteObserver<ModalRoute<void>>? observer;
  final Widget child;

  @override
  State<AppVisibilityRouteBinding> createState() =>
      _AppVisibilityRouteBindingState();
}

final class _AppVisibilityRouteBindingState
    extends State<AppVisibilityRouteBinding>
    with RouteAware {
  RouteObserver<ModalRoute<void>>? _observer;
  AppVisibilityRouteObserver? _visibilityObserver;
  ModalRoute<void>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeIfNeeded();
  }

  @override
  void didUpdateWidget(AppVisibilityRouteBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.registry, widget.registry) ||
        oldWidget.identity != widget.identity ||
        !identical(oldWidget.observer, widget.observer)) {
      oldWidget.registry._leftTop(this);
      _unsubscribe();
      _subscribeIfNeeded();
    }
  }

  void _subscribeIfNeeded() {
    final observer = widget.observer;
    final route = ModalRoute.of<void>(context);
    if (identical(observer, _observer) && identical(route, _route)) return;
    widget.registry._leftTop(this);
    _unsubscribe();
    if (observer == null || route == null) return;
    _observer = observer;
    _visibilityObserver = observer is AppVisibilityRouteObserver
        ? observer
        : null;
    _route = route;
    _visibilityObserver?.registerVisibilityRoute(
      route: route,
      owner: this,
      registry: widget.registry,
      identity: widget.identity,
    );
    observer.subscribe(this, route);
    if (_visibilityObserver == null && route.isCurrent) {
      widget.registry._becameTop(this, widget.identity);
    }
  }

  void _unsubscribe() {
    final route = _route;
    if (route != null) {
      _visibilityObserver?.unregisterVisibilityRoute(route: route, owner: this);
    }
    _observer?.unsubscribe(this);
    _observer = null;
    _visibilityObserver = null;
    _route = null;
  }

  @override
  void didPush() {
    if (_visibilityObserver == null) {
      widget.registry._becameTop(this, widget.identity);
    }
  }

  @override
  void didPopNext() {
    if (_visibilityObserver == null) {
      widget.registry._becameTop(this, widget.identity);
    }
  }

  @override
  void didPushNext() {
    if (_visibilityObserver == null) widget.registry._leftTop(this);
  }

  @override
  void didPop() {
    if (_visibilityObserver == null) widget.registry._leftTop(this);
  }

  @override
  void dispose() {
    widget.registry._leftTop(this);
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
