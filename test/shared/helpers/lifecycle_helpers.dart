import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';

/// Simulates the pause side of a background cycle via the production
/// lifecycle handler.
Future<AppPausedResult> simulateAppPaused({
  required MessageRepository messageRepo,
  GroupMessageRepository? groupMsgRepo,
}) async {
  return handleAppPaused(messageRepo: messageRepo, groupMsgRepo: groupMsgRepo);
}

/// Simulates a complete background/foreground cycle in tests.
///
/// Calls the real [handleAppPaused] then [handleAppResumed] pair, with
/// optional injected recovery callbacks for tests that need the full
/// Section 6 pause/resume path.
Future<bool?> simulateBackgroundForegroundCycle({
  required Bridge bridge,
  required P2PService p2pService,
  required MessageRepository messageRepo,
  GroupMessageRepository? groupMsgRepo,
  FutureOr<void> Function()? afterPause,
  FutureOr<void> Function()? afterResume,
  Future<int> Function()? recoverStuckSendingMessagesFn,
  Future<int> Function()? recoverStuckSendingGroupMessagesFn,
  Future<int> Function()? retryIncompleteGroupUploadsFn,
  Future<int> Function()? retryFailedGroupMessagesFn,
  Future<int> Function()? retryIncompleteUploadsFn,
  Future<int> Function()? retryFailedMessagesFn,
  Future<int> Function()? retryUnackedMessagesFn,
}) async {
  await simulateAppPaused(messageRepo: messageRepo, groupMsgRepo: groupMsgRepo);
  await afterPause?.call();

  final result = await handleAppResumed(
    bridge: bridge,
    p2pService: p2pService,
    recoverStuckSendingMessagesFn: recoverStuckSendingMessagesFn,
    recoverStuckSendingGroupMessagesFn: recoverStuckSendingGroupMessagesFn,
    retryIncompleteGroupUploadsFn: retryIncompleteGroupUploadsFn,
    retryFailedGroupMessagesFn: retryFailedGroupMessagesFn,
    retryIncompleteUploadsFn: retryIncompleteUploadsFn,
    retryFailedMessagesFn: retryFailedMessagesFn,
    retryUnackedMessagesFn: retryUnackedMessagesFn,
  );
  await afterResume?.call();
  return result;
}

/// Simulates rapid lock-unlock (N full background/foreground cycles).
///
/// Used by the rapid-lock-unlock integration test to verify idempotency.
Future<void> simulateRapidLockUnlock({
  required Bridge bridge,
  required P2PService p2pService,
  required MessageRepository messageRepo,
  GroupMessageRepository? groupMsgRepo,
  int cycles = 3,
  Duration pauseBetween = Duration.zero,
  FutureOr<void> Function()? afterPause,
  FutureOr<void> Function()? afterResume,
  Future<int> Function()? recoverStuckSendingMessagesFn,
  Future<int> Function()? recoverStuckSendingGroupMessagesFn,
  Future<int> Function()? retryIncompleteGroupUploadsFn,
  Future<int> Function()? retryFailedGroupMessagesFn,
  Future<int> Function()? retryIncompleteUploadsFn,
  Future<int> Function()? retryFailedMessagesFn,
  Future<int> Function()? retryUnackedMessagesFn,
}) async {
  for (var i = 0; i < cycles; i++) {
    await simulateBackgroundForegroundCycle(
      bridge: bridge,
      p2pService: p2pService,
      messageRepo: messageRepo,
      groupMsgRepo: groupMsgRepo,
      afterPause: afterPause,
      afterResume: afterResume,
      recoverStuckSendingMessagesFn: recoverStuckSendingMessagesFn,
      recoverStuckSendingGroupMessagesFn: recoverStuckSendingGroupMessagesFn,
      retryIncompleteGroupUploadsFn: retryIncompleteGroupUploadsFn,
      retryFailedGroupMessagesFn: retryFailedGroupMessagesFn,
      retryIncompleteUploadsFn: retryIncompleteUploadsFn,
      retryFailedMessagesFn: retryFailedMessagesFn,
      retryUnackedMessagesFn: retryUnackedMessagesFn,
    );
    if (pauseBetween > Duration.zero) {
      await Future.delayed(pauseBetween);
    }
  }
}
