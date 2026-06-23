import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';

typedef NotificationOpenSideEffect = Future<void> Function();

Future<void> routeAppRootInitialLocalNotificationOpen({
  required Future<String?> Function() consumeInitialPayload,
  required PrepareNotificationRouteTargetHandler onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
  NotificationOpenSideEffect? onBeforeOpen,
}) async {
  await onBeforeOpen?.call();
  await routeInitialLocalNotificationOpen(
    consumeInitialPayload: consumeInitialPayload,
    onBeforeRouteTarget: onBeforeRouteTarget,
    onRouteTarget: onRouteTarget,
  );
}

Future<void> routeAppRootLocalNotificationTap({
  required String payload,
  required PrepareNotificationRouteTargetHandler onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
  NotificationOpenSideEffect? onBeforeOpen,
}) async {
  await onBeforeOpen?.call();
  await routeNotificationPayload(
    payload: payload,
    onBeforeRouteTarget: onBeforeRouteTarget,
    onRouteTarget: onRouteTarget,
  );
}

Future<void> routeAppRootRemoteNotificationOpen({
  required Map<String, dynamic> data,
  required PrepareNotificationRouteTargetHandler onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
  MissingGroupNotificationRouteIdHandler? onMissingGroupRouteId,
  required MissingNotificationRouteTargetHandler onMissingRouteTarget,
  NotificationOpenSideEffect? onBeforeOpen,
}) async {
  await routeAppRootRemoteNotificationOpenWithResult(
    data: data,
    onBeforeRouteTarget: onBeforeRouteTarget,
    onRouteTarget: onRouteTarget,
    onMissingGroupRouteId: onMissingGroupRouteId,
    onMissingRouteTarget: onMissingRouteTarget,
    onBeforeOpen: onBeforeOpen,
  );
}

Future<bool> routeAppRootRemoteNotificationOpenWithResult({
  required Map<String, dynamic> data,
  required PrepareNotificationRouteTargetHandler onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
  MissingGroupNotificationRouteIdHandler? onMissingGroupRouteId,
  required MissingNotificationRouteTargetHandler onMissingRouteTarget,
  NotificationOpenSideEffect? onBeforeOpen,
}) async {
  await onBeforeOpen?.call();
  return routeRemoteNotificationOpenWithResult(
    data: data,
    onBeforeRouteTarget: onBeforeRouteTarget,
    onRouteTarget: onRouteTarget,
    onMissingGroupRouteId: onMissingGroupRouteId,
    onMissingRouteTarget: onMissingRouteTarget,
  );
}

bool isNotificationRouteTargetAlreadyActive({
  required NotificationRouteTarget routeTarget,
  required ActiveConversationTracker groupConversationTracker,
  ActiveConversationTracker? conversationTracker,
}) {
  switch (routeTarget.kind) {
    case NotificationRouteTargetKind.group:
      return groupConversationTracker.isViewing(routeTarget.toPayload());
    case NotificationRouteTargetKind.conversation:
      // Report 139: mirror the group guard for 1:1. `toPayload()` for the
      // conversation kind is the bare peerId, and the 1:1
      // `conversationTracker` is the same instance `ConversationWired` keeps
      // current via `setActive`/`clearIfActive`, so this is symmetric with the
      // group branch. A null tracker (no 1:1 screen wired) falls through to
      // false → push as before.
      return conversationTracker?.isViewing(routeTarget.toPayload()) ?? false;
    case NotificationRouteTargetKind.contactRequest:
    case NotificationRouteTargetKind.intros:
    case NotificationRouteTargetKind.post:
    case NotificationRouteTargetKind.postComment:
      return false;
  }
}
