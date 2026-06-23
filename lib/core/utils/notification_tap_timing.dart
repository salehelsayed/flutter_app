import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Emits a [NOTIFICATION_TAP_TO_MESSAGE_TIMING] flow event measuring the
/// elapsed time from when the user tapped a notification to when the target
/// conversation screen finished loading messages.
///
/// This is extracted as a standalone function so it can be unit-tested
/// independently of widget lifecycle.
void emitNotificationTapTiming({
  required DateTime tappedAt,
  required String routeKind,
  String? messageId,
}) {
  final elapsed = DateTime.now().difference(tappedAt).inMilliseconds;
  emitFlowEvent(
    layer: 'FL',
    event: 'NOTIFICATION_TAP_TO_MESSAGE_TIMING',
    details: {
      'elapsedMs': elapsed,
      'routeKind': routeKind,
      // 145: tag the milestone this timing represents. This event fires at the
      // STALE-history render (the screen appears immediately on cached rows,
      // before the relay drain surfaces newer messages). `milestone` lives in
      // details — the payload-level milestone is a separate fixed sentinel.
      'milestone': 'stale_render',
      'messageId': messageId != null && messageId.length > 8
          ? messageId.substring(0, 8)
          : (messageId ?? ''),
    },
  );
}

/// Emits a [NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING] flow event measuring the
/// elapsed time from when the user tapped a notification to when the relay
/// drain finally surfaced a NEW incoming message (the "live" render milestone).
///
/// This is the post-drain counterpart to [emitNotificationTapTiming]: the
/// stale-render event fires when the screen first appears on cached history,
/// whereas this one fires once the just-received message actually lands.
/// [addedIncoming] records whether the drain surfaced a genuinely new incoming
/// row (it always should when this is emitted, but is carried explicitly so the
/// telemetry is self-describing).
void emitNotificationTapLiveRenderTiming({
  required DateTime tappedAt,
  required String routeKind,
  required bool addedIncoming,
  String? messageId,
}) {
  final elapsed = DateTime.now().difference(tappedAt).inMilliseconds;
  emitFlowEvent(
    layer: 'FL',
    event: 'NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING',
    details: {
      'elapsedMs': elapsed,
      'routeKind': routeKind,
      'addedIncoming': addedIncoming,
      'milestone': 'live_render',
      'messageId': messageId != null && messageId.length > 8
          ? messageId.substring(0, 8)
          : (messageId ?? ''),
    },
  );
}
