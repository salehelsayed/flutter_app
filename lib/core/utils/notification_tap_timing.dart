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
      'messageId': messageId != null && messageId.length > 8
          ? messageId.substring(0, 8)
          : (messageId ?? ''),
    },
  );
}
