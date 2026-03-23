import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/handle_initial_remote_message_use_case.dart';

typedef NotificationRouteTargetHandler =
    Future<void> Function(NotificationRouteTarget routeTarget);
typedef MissingNotificationRouteTargetHandler = Future<void> Function();
typedef PrepareNotificationRouteTargetHandler =
    Future<void> Function(NotificationRouteTarget routeTarget);

Future<void> routeNotificationPayload({
  required String? payload,
  PrepareNotificationRouteTargetHandler? onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
}) async {
  final routeTarget = NotificationRouteTarget.fromPayload(payload);
  if (routeTarget == null) {
    return;
  }
  await onBeforeRouteTarget?.call(routeTarget);
  await onRouteTarget(routeTarget);
}

Future<void> routeInitialLocalNotificationOpen({
  required Future<String?> Function() consumeInitialPayload,
  PrepareNotificationRouteTargetHandler? onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
}) async {
  final payload = await consumeInitialPayload();
  await routeNotificationPayload(
    payload: payload,
    onBeforeRouteTarget: onBeforeRouteTarget,
    onRouteTarget: onRouteTarget,
  );
}

Future<void> routeRemoteNotificationOpen({
  required Map<String, dynamic> data,
  PrepareNotificationRouteTargetHandler? onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
  required MissingNotificationRouteTargetHandler onMissingRouteTarget,
}) async {
  final routeTarget = NotificationRouteTarget.fromRemoteMessageData(data);
  if (routeTarget == null) {
    await onMissingRouteTarget();
    return;
  }
  await onBeforeRouteTarget?.call(routeTarget);
  await onRouteTarget(routeTarget);
}

Future<void> routeInitialRemoteNotificationOpen({
  required GetInitialRemoteMessageFn getInitialMessage,
  PrepareNotificationRouteTargetHandler? onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
  required MissingNotificationRouteTargetHandler onMissingRouteTarget,
}) async {
  await handleInitialRemoteMessage(
    getInitialMessage: getInitialMessage,
    onMessageOpened: (message) => routeRemoteNotificationOpen(
      data: message.data,
      onBeforeRouteTarget: onBeforeRouteTarget,
      onRouteTarget: onRouteTarget,
      onMissingRouteTarget: onMissingRouteTarget,
    ),
  );
}
