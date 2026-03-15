import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/handle_initial_remote_message_use_case.dart';

typedef NotificationRouteTargetHandler =
    Future<void> Function(NotificationRouteTarget routeTarget);
typedef MissingNotificationRouteTargetHandler = Future<void> Function();

Future<void> routeNotificationPayload({
  required String? payload,
  required NotificationRouteTargetHandler onRouteTarget,
}) async {
  final routeTarget = NotificationRouteTarget.fromPayload(payload);
  if (routeTarget == null) {
    return;
  }
  await onRouteTarget(routeTarget);
}

Future<void> routeInitialLocalNotificationOpen({
  required Future<String?> Function() consumeInitialPayload,
  required NotificationRouteTargetHandler onRouteTarget,
}) async {
  final payload = await consumeInitialPayload();
  await routeNotificationPayload(
    payload: payload,
    onRouteTarget: onRouteTarget,
  );
}

Future<void> routeRemoteNotificationOpen({
  required Map<String, dynamic> data,
  required NotificationRouteTargetHandler onRouteTarget,
  required MissingNotificationRouteTargetHandler onMissingRouteTarget,
}) async {
  final routeTarget = NotificationRouteTarget.fromRemoteMessageData(data);
  if (routeTarget == null) {
    await onMissingRouteTarget();
    return;
  }
  await onRouteTarget(routeTarget);
}

Future<void> routeInitialRemoteNotificationOpen({
  required GetInitialRemoteMessageFn getInitialMessage,
  required NotificationRouteTargetHandler onRouteTarget,
  required MissingNotificationRouteTargetHandler onMissingRouteTarget,
}) async {
  await handleInitialRemoteMessage(
    getInitialMessage: getInitialMessage,
    onMessageOpened: (message) => routeRemoteNotificationOpen(
      data: message.data,
      onRouteTarget: onRouteTarget,
      onMissingRouteTarget: onMissingRouteTarget,
    ),
  );
}
