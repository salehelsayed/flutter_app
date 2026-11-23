import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show
        MethodChannel,
        MissingPluginException,
        PlatformException,
        PredictiveBackEvent;
import 'package:flutter/widgets.dart';

/// Channel owned by Android `MainActivity` (`MknoonCallTaskChannelHandler`).
const MethodChannel foregroundCallTaskChannel = MethodChannel(
  'mknoon/call_task',
);

/// Sends the app to the background and keeps the call running.
Future<void> moveAppToBackgroundForCall() =>
    _invokeCallTask('moveToBackground');

/// Tells Android whether a call surface owns Back. While it does, Android
/// moves the task to the back on Back (key or predictive swipe) before
/// Flutter's own back callback runs, so no hidden route is popped.
Future<void> setAndroidCallOwnsBack(bool owns) =>
    _invokeCallTask('setCallOwnsBack', <String, Object?>{'owns': owns});

Future<void> _invokeCallTask(String method, [Object? arguments]) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await foregroundCallTaskChannel.invokeMethod<bool>(method, arguments);
  } on MissingPluginException {
    // No Android host (for example a headless engine). Back is still
    // consumed by the guard.
  } on PlatformException {
    // The activity is going away. Back is still consumed by the guard.
  }
}

/// Handles the system Back action while a foreground call surface owns the
/// screen.
///
/// [ForegroundCallOverlay] is a Stack layer above the app navigator, not a
/// route. Without this guard, Back pops the hidden routes under the call and,
/// at the root route, `SystemNavigator.pop` finishes the Android activity. The
/// activity teardown then ends the call with `appShutdown` (beta 2026-09-24).
///
/// While a call surface shows, Back sends the app to the background, like
/// other calling apps, and the call keeps running (beta 2026-09-25). Android
/// handles Back first while [surfaceOwnsBack] is true. This guard handles a
/// Back that still reaches Flutter. The overlay also keeps Flutter's Android
/// back callback registered, so the system never closes the task itself.
///
/// [WidgetsBinding.handlePopRoute] asks observers in registration order and
/// the app's `WidgetsApp` registers its own navigator observer when it is
/// first built. So [attach] must run before `MaterialApp` is built (for
/// example in the `initState` of the widget that builds it).
final class ForegroundCallBackGuard with WidgetsBindingObserver {
  ForegroundCallBackGuard({
    Future<void> Function()? moveAppToBackground,
    Future<void> Function(bool owns)? publishCallOwnsBack,
  }) : _moveAppToBackground = moveAppToBackground ?? moveAppToBackgroundForCall,
       _publishCallOwnsBack = publishCallOwnsBack ?? setAndroidCallOwnsBack;

  final Future<void> Function() _moveAppToBackground;
  final Future<void> Function(bool owns) _publishCallOwnsBack;
  bool _attached = false;
  VoidCallback? _gestureAction;
  bool _surfaceOwnsBack = false;

  /// A finished call has a Flutter-only Back action.
  VoidCallback? dismissTerminal;

  /// Whether an incoming, outgoing, or active call surface is showing.
  bool get surfaceOwnsBack => _surfaceOwnsBack;

  set surfaceOwnsBack(bool owns) {
    if (_surfaceOwnsBack == owns) return;
    _surfaceOwnsBack = owns;
    if (!owns) _gestureAction = null;
    _run(() => _publishCallOwnsBack(owns));
  }

  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    surfaceOwnsBack = false;
    _gestureAction = null;
    dismissTerminal = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  VoidCallback? get _backAction =>
      dismissTerminal ?? (_surfaceOwnsBack ? _backgroundLiveCall : null);

  void _backgroundLiveCall() => _run(_moveAppToBackground);

  @override
  Future<bool> didPopRoute() {
    final action = _backAction;
    action?.call();
    return SynchronousFuture<bool>(action != null);
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    _gestureAction = _backAction;
    return _gestureAction != null;
  }

  @override
  void handleCommitBackGesture() {
    final action = _gestureAction;
    _gestureAction = null;
    action?.call();
  }

  @override
  void handleCancelBackGesture() {
    _gestureAction = null;
  }

  static void _run(Future<void> Function() action) {
    unawaited(Future<void>.sync(action).catchError((Object _) {}));
  }
}
