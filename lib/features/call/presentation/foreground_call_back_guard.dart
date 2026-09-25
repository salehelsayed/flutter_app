import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;
import 'package:flutter/widgets.dart';

/// Consumes the system Back action while a foreground call surface owns the
/// screen.
///
/// [ForegroundCallOverlay] is a Stack layer above the app navigator, not a
/// route. Without this guard, Back pops the hidden routes under the call and,
/// at the root route, `SystemNavigator.pop` finishes the Android activity. The
/// activity teardown then ends the call with `appShutdown` (beta 2026-09-24).
///
/// [WidgetsBinding.handlePopRoute] asks observers in registration order and
/// the app's `WidgetsApp` registers its own navigator observer when it is
/// first built. So [attach] must run before `MaterialApp` is built (for
/// example in the `initState` of the widget that builds it).
final class ForegroundCallBackGuard with WidgetsBindingObserver {
  bool _attached = false;

  /// Whether an incoming, outgoing, or active call surface is showing.
  bool surfaceOwnsBack = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    surfaceOwnsBack = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  Future<bool> didPopRoute() => SynchronousFuture<bool>(surfaceOwnsBack);

  /// Claims a predictive back swipe so the navigator never starts a pop
  /// transition under the call surface. The commit is then a no-op.
  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) => surfaceOwnsBack;
}
