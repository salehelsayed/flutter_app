import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';

/// Default age after which a group message in 'sending' is considered stuck.
const Duration kStuckSendingGroupThreshold = Duration(seconds: 30);

/// Transitions outgoing group messages stuck in 'sending' to 'failed' so they
/// are picked up by [retryFailedGroupMessages] on the next retry cycle.
///
/// Intended to be called early in the app-resume sequence.
///
/// Returns the number of messages recovered (status changed to 'failed').
Future<int> recoverStuckSendingGroupMessages({
  required GroupMessageRepository groupMsgRepo,
  Duration threshold = kStuckSendingGroupThreshold,
}) async {
  final recoverStopwatch = Stopwatch()..start();
  emitFlowEvent(
    layer: 'FL',
    event: 'RECOVER_STUCK_SENDING_GROUP_START',
    details: {'thresholdSeconds': threshold.inSeconds},
  );

  final count = await groupMsgRepo.recoverStuckSendingMessages(
    olderThan: threshold,
  );

  emitFlowEvent(
    layer: 'FL',
    event: count > 0
        ? 'RECOVER_STUCK_SENDING_GROUP_RECOVERED'
        : 'RECOVER_STUCK_SENDING_GROUP_NONE',
    details: {'count': count},
  );
  emitFlowEvent(
    layer: 'FL',
    event: 'RECOVER_STUCK_SENDING_GROUP_TIMING',
    details: {
      'elapsedMs': recoverStopwatch.elapsedMilliseconds,
      'outcome': count > 0 ? 'recovered' : 'none',
      'count': count,
      'thresholdSeconds': threshold.inSeconds,
    },
  );

  return count;
}
