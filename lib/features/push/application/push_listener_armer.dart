import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// 191 (Fix D2): observable, retryable, idempotent push-listener arming.
///
/// Extracts the foreground-push / open-app subscription arm out of
/// `_MyAppState._setupPushListeners` so it is:
///   - observable: emits `PUSH_LISTENERS_ARMED{platform, kinds}` exactly once
///     when the listeners are first subscribed (previously the arm was silent,
///     so a permanently-disarmed launch left no telemetry);
///   - retryable: a not-ready [arm] is a no-op that does NOT consume the latch,
///     so a later ready [arm] — the third arm point wired on
///     `FirebaseReadiness` first-success — still arms;
///   - idempotent: repeated ready [arm] calls never double-subscribe (a double
///     `onMessage.listen` would duplicate foreground-push handling + routing).
class PushListenerArmer {
  PushListenerArmer({
    required bool Function() firebaseReady,
    required void Function() subscribe,
    required String platform,
    List<String> kinds = const ['onMessage', 'onMessageOpenedApp'],
  }) : _firebaseReady = firebaseReady,
       _subscribe = subscribe,
       _platform = platform,
       _kinds = kinds;

  final bool Function() _firebaseReady;
  final void Function() _subscribe;
  final String _platform;
  final List<String> _kinds;

  bool _armed = false;

  /// Whether the listeners have been subscribed.
  bool get armed => _armed;

  /// Subscribes the push listeners if Firebase is ready and they are not
  /// already armed. The ready guard is checked BEFORE the latch so a not-ready
  /// attempt does not consume it (keeping a later ready attempt effective).
  void arm() {
    if (!_firebaseReady()) {
      // Not ready: no-op, latch NOT consumed — a later ready arm still fires.
      return;
    }
    if (_armed) {
      return;
    }
    _armed = true;
    try {
      _subscribe();
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_LISTENER_ERROR',
        details: {'error': error.toString()},
      );
      return;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_LISTENERS_ARMED',
      details: {'platform': _platform, 'kinds': _kinds},
    );
  }
}
