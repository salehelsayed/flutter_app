import 'dart:async';

import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

typedef RefreshAppVisibility = FutureOr<void> Function();

/// FDC-09 §6.3 write side — self-publishes the local peer's foreground/background
/// presence to the relay (via [RelayPresenceSet.setPresence]) so the read side
/// (FDC-08 `presence_get`) has a real FOREGROUND signal to key the send emphasis
/// off. The relay provably cannot infer foreground from a TTL-lagged socket, so
/// the peer must announce it (FDC-S3 Option C; Option B gossipsub beacon was
/// REJECTED).
///
/// Owns the foreground heartbeat timer that re-publishes within the TTL window;
/// the timer is ARMED on foreground ([onForegrounded]) and CANCELLED on
/// background ([onBackgrounded]) so it can never fire while the app is suspended.
/// The background publish is best-effort / fire-and-forget — it MUST NOT block
/// the pause path (it piggybacks FDC-06's bounded `beginBackgroundTask` window
/// without widening it).
///
/// Presence is a best-effort HINT and NEVER load-bearing: a failed/skipped
/// publish never throws away delivery (the durable inbox + push remain the
/// guarantee). An old relay degrades silently to "unsupported" (NET-REL-07); a
/// paused account-move blocks the publish at the primitive (move-gated).
class SetPresenceUseCase {
  SetPresenceUseCase({
    required RelayPresenceSet presenceSetter,
    RefreshAppVisibility? refreshAppVisibility,
    Duration presenceTtl = kPresenceSelfTtl,
    Duration heartbeatInterval = kPresenceForegroundHeartbeat,
  }) : _presenceSetter = presenceSetter,
       _refreshAppVisibility = refreshAppVisibility,
       _presenceTtl = presenceTtl,
       _heartbeatInterval = heartbeatInterval;

  final RelayPresenceSet _presenceSetter;
  final RefreshAppVisibility? _refreshAppVisibility;
  final Duration _presenceTtl;
  final Duration _heartbeatInterval;

  Timer? _heartbeat;

  /// FDC-S3-locked constants (device-tunable on closure): presence-entry TTL
  /// ≈180 s; foreground heartbeat/refresh ≈60 s (< TTL so a missed beat does not
  /// expire the entry).
  static const Duration kPresenceSelfTtl = Duration(seconds: 180);
  static const Duration kPresenceForegroundHeartbeat = Duration(seconds: 60);

  /// Whether the foreground heartbeat timer is currently armed (test/diagnostic).
  bool get isHeartbeatActive => _heartbeat?.isActive ?? false;

  /// Called when the app FOREGROUNDS (resume): publish `foreground` once and arm
  /// the heartbeat that re-publishes within the TTL. Awaitable but cheap — the
  /// resume path fires it UNAWAITED so it never adds latency.
  Future<void> onForegrounded() async {
    _startHeartbeat();
    await _refreshThenPublishForeground();
  }

  /// Called when the app BACKGROUNDS (pause): cancel the heartbeat (so it can
  /// never fire while suspended) and fire a best-effort `background` publish.
  /// Returns a future that completes IMMEDIATELY — the publish is UNAWAITED
  /// (fire-and-forget) so it can never block the pause path (it piggybacks
  /// FDC-06's bounded `beginBackgroundTask` window without widening it). A caller
  /// may safely `await` this; it will not wait on the network round-trip.
  Future<void> onBackgrounded() async {
    _stopHeartbeat();
    unawaited(_publish('background', bestEffort: true));
  }

  /// Cancels the heartbeat without publishing (dispose / teardown).
  void dispose() => _stopHeartbeat();

  Future<void> _publish(String state, {required bool bestEffort}) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'PRESENCE_SELF_PUBLISH',
      details: {'state': state, if (bestEffort) 'bestEffort': true},
    );
    final result = await _presenceSetter.setPresence(
      state,
      _presenceTtl.inMilliseconds,
    );
    if (result == PresenceSetResult.unsupported) {
      // Old relay (NET-REL-07): record the un-upgraded relay, do NOT retry/spam.
      emitFlowEvent(
        layer: 'FL',
        event: 'PRESENCE_SELF_PUBLISH_UNSUPPORTED',
        details: {'state': state},
      );
    }
  }

  Future<void> _refreshThenPublishForeground() async {
    try {
      await _refreshAppVisibility?.call();
    } catch (error) {
      // Visibility is fail-notify and presence is only a hint. A local refresh
      // failure must not couple or suppress the incumbent relay publication.
      emitFlowEvent(
        layer: 'FL',
        event: 'APP_VISIBILITY_REFRESH_FAILED',
        details: {'errorType': error.runtimeType.toString()},
      );
    }
    await _publish('foreground', bestEffort: false);
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      unawaited(_refreshThenPublishForeground());
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }
}
