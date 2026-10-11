import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;
import 'package:flutter/widgets.dart';

/// Swallows the system Back action while the SE-41 hard overlay shows.
///
/// The overlay is a layer above the app navigator, not a route, so a
/// `PopScope` there has no route to guard. Without this guard, Back would pop
/// the hidden routes under the overlay.
///
/// [WidgetsBinding.handlePopRoute] asks observers in registration order, and
/// `WidgetsApp` registers its navigator observer when it is first built. So
/// [attach] must run before `MaterialApp` is built, like
/// `ForegroundCallBackGuard`.
final class UpdateRequiredBackGuard with WidgetsBindingObserver {
  bool _attached = false;

  /// Whether the hard overlay is showing.
  bool blocking = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    blocking = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  Future<bool> didPopRoute() => SynchronousFuture<bool>(blocking);

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) => blocking;
}
