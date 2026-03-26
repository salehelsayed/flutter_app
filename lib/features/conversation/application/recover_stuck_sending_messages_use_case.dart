import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Default age after which a 'sending' message is considered stuck.
const Duration kStuckSendingThreshold = Duration(seconds: 30);

/// Transitions outgoing messages stuck in 'sending' to 'failed' so they
/// are picked up by [retryFailedMessages] on the next retry cycle.
///
/// Intended to be called early in the app-resume sequence, before the
/// pending-message retrier fires.
///
/// Returns the number of messages recovered (status changed to 'failed').
Future<int> recoverStuckSendingMessages({
  required MessageRepository messageRepo,
  Duration threshold = kStuckSendingThreshold,
}) async {
  final recoverStopwatch = Stopwatch()..start();
  emitFlowEvent(
    layer: 'FL',
    event: 'RECOVER_STUCK_SENDING_START',
    details: {'thresholdSeconds': threshold.inSeconds},
  );

  final count = await messageRepo.recoverStuckSendingMessages(
    olderThan: threshold,
  );

  emitFlowEvent(
    layer: 'FL',
    event: count > 0
        ? 'RECOVER_STUCK_SENDING_RECOVERED'
        : 'RECOVER_STUCK_SENDING_NONE',
    details: {'count': count},
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'RECOVER_STUCK_SENDING_TIMING',
    details: {
      'elapsedMs': recoverStopwatch.elapsedMilliseconds,
      'outcome': count > 0 ? 'recovered' : 'none',
      'count': count,
      'thresholdSeconds': threshold.inSeconds,
    },
  );

  return count;
}
