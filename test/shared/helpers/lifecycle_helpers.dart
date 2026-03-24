import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Simulates the pause side of a background cycle via the production
/// lifecycle handler.
Future<AppPausedResult> simulateAppPaused({
  required MessageRepository messageRepo,
}) async {
  return handleAppPaused(messageRepo: messageRepo);
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
  FutureOr<void> Function()? afterPause,
  FutureOr<void> Function()? afterResume,
  Future<int> Function()? recoverStuckSendingMessagesFn,
  Future<int> Function()? retryIncompleteUploadsFn,
  Future<int> Function()? retryFailedMessagesFn,
  Future<int> Function()? retryUnackedMessagesFn,
}) async {
  await simulateAppPaused(messageRepo: messageRepo);
  await afterPause?.call();

  final result = await handleAppResumed(
    bridge: bridge,
    p2pService: p2pService,
    recoverStuckSendingMessagesFn: recoverStuckSendingMessagesFn,
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
  int cycles = 3,
  Duration pauseBetween = Duration.zero,
  FutureOr<void> Function()? afterPause,
  FutureOr<void> Function()? afterResume,
  Future<int> Function()? recoverStuckSendingMessagesFn,
  Future<int> Function()? retryIncompleteUploadsFn,
  Future<int> Function()? retryFailedMessagesFn,
  Future<int> Function()? retryUnackedMessagesFn,
}) async {
  for (var i = 0; i < cycles; i++) {
    await simulateBackgroundForegroundCycle(
      bridge: bridge,
      p2pService: p2pService,
      messageRepo: messageRepo,
      afterPause: afterPause,
      afterResume: afterResume,
      recoverStuckSendingMessagesFn: recoverStuckSendingMessagesFn,
      retryIncompleteUploadsFn: retryIncompleteUploadsFn,
      retryFailedMessagesFn: retryFailedMessagesFn,
      retryUnackedMessagesFn: retryUnackedMessagesFn,
    );
    if (pauseBetween > Duration.zero) {
      await Future.delayed(pauseBetween);
    }
  }
}
