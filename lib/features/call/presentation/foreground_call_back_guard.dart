import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show
        MethodCall,
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

/// Gives Android priority over the Flutter routes covered by the call.
Future<void> setAndroidCallOwnsBack(bool owns, {String? minimizeCallId}) =>
    _invokeCallTask('setCallOwnsBack', <String, Object?>{
      'owns': owns,
      'minimizeCallId': ?minimizeCallId,
    });

bool get _usesAndroidCallTaskChannel =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<void> _invokeCallTask(String method, [Object? arguments]) async {
  if (!_usesAndroidCallTaskChannel) return;
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
/// Android handles Back first for a live call surface. An expanded active or
/// outgoing call minimizes in the app. Other guarded live surfaces background
/// the task and keep the call running. The overlay keeps the Flutter Back
/// callback registered as a fallback.
///
/// [WidgetsBinding.handlePopRoute] asks observers in registration order and
/// the app's `WidgetsApp` registers its own navigator observer when it is
/// first built. So [attach] must run before `MaterialApp` is built (for
/// example in the `initState` of the widget that builds it).
final class ForegroundCallBackGuard with WidgetsBindingObserver {
  ForegroundCallBackGuard({
    Future<void> Function()? moveAppToBackground,
    Future<void> Function(bool owns, {String? minimizeCallId})?
    publishCallOwnsBack,
  }) : _moveAppToBackground = moveAppToBackground ?? moveAppToBackgroundForCall,
       _publishCallOwnsBack = publishCallOwnsBack ?? setAndroidCallOwnsBack;

  static ForegroundCallBackGuard? _androidChannelOwner;
  final Future<void> Function() _moveAppToBackground;
  final Future<void> Function(bool owns, {String? minimizeCallId})
  _publishCallOwnsBack;
  bool _attached = false;
  VoidCallback? _gestureAction;
  bool _surfaceOwnsBack = false;
  ({String callId, VoidCallback action})? _minimizeTarget;

  /// A finished call has a Flutter-only Back action.
  VoidCallback? dismissTerminal;

  void setSurfaceBackAction(
    bool owns, {
    ({String callId, VoidCallback action})? minimize,
  }) {
    final previousCallId = _minimizeTarget?.callId;
    _minimizeTarget = owns && _usesAndroidCallTaskChannel ? minimize : null;
    final minimizeCallId = _minimizeTarget?.callId;
    if (_surfaceOwnsBack == owns && previousCallId == minimizeCallId) return;
    _surfaceOwnsBack = owns;
    if (!owns || previousCallId != minimizeCallId) _gestureAction = null;
    _publishSurfaceBack();
  }

  void _publishSurfaceBack() {
    if (_androidChannelOwner != null &&
        !identical(_androidChannelOwner, this)) {
      return;
    }
    _run(
      () => _publishCallOwnsBack(
        _surfaceOwnsBack,
        minimizeCallId: _minimizeTarget?.callId,
      ),
    );
  }

  void attach() {
    if (_attached) return;
    _attached = true;
    if (_usesAndroidCallTaskChannel) {
      final previous = _androidChannelOwner;
      previous?._gestureAction = null;
      _androidChannelOwner = this;
      foregroundCallTaskChannel.setMethodCallHandler(_handleAndroidBack);
      if (previous?._surfaceOwnsBack == true || _surfaceOwnsBack) {
        _publishSurfaceBack();
      }
    }
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    setSurfaceBackAction(false);
    if (identical(_androidChannelOwner, this)) {
      _androidChannelOwner = null;
      foregroundCallTaskChannel.setMethodCallHandler(null);
    }
    _gestureAction = null;
    dismissTerminal = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<void> _handleAndroidBack(MethodCall call) async {
    if (!identical(_androidChannelOwner, this) ||
        call.method != 'minimizeCall') {
      return;
    }
    final target = _minimizeTarget;
    final callId = call.arguments;
    if (target != null && callId is String && callId == target.callId) {
      target.action();
    }
  }

  VoidCallback? get _backAction {
    if (_androidChannelOwner != null &&
        !identical(_androidChannelOwner, this)) {
      return null;
    }
    return dismissTerminal ??
        _minimizeTarget?.action ??
        (_surfaceOwnsBack ? _backgroundLiveCall : null);
  }

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
