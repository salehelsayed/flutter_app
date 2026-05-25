import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/handle_initial_remote_message_use_case.dart';

typedef NotificationRouteTargetHandler =
    Future<void> Function(NotificationRouteTarget routeTarget);
typedef MissingNotificationRouteTargetHandler = Future<void> Function();
typedef MissingGroupNotificationRouteIdHandler =
    Future<void> Function(Map<String, dynamic> data);
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
  MissingGroupNotificationRouteIdHandler? onMissingGroupRouteId,
  required MissingNotificationRouteTargetHandler onMissingRouteTarget,
}) async {
  await routeRemoteNotificationOpenWithResult(
    data: data,
    onBeforeRouteTarget: onBeforeRouteTarget,
    onRouteTarget: onRouteTarget,
    onMissingGroupRouteId: onMissingGroupRouteId,
    onMissingRouteTarget: onMissingRouteTarget,
  );
}

Future<bool> routeRemoteNotificationOpenWithResult({
  required Map<String, dynamic> data,
  PrepareNotificationRouteTargetHandler? onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
  MissingGroupNotificationRouteIdHandler? onMissingGroupRouteId,
  required MissingNotificationRouteTargetHandler onMissingRouteTarget,
}) async {
  final routeTarget = NotificationRouteTarget.fromRemoteMessageData(data);
  if (routeTarget == null) {
    if (NotificationRouteTarget.isGroupMessageLikeRemoteData(data) &&
        NotificationRouteTarget.groupIdFromRemoteMessageData(data) == null) {
      await onMissingGroupRouteId?.call(data);
    }
    await onMissingRouteTarget();
    return false;
  }
  await onBeforeRouteTarget?.call(routeTarget);
  await onRouteTarget(routeTarget);
  return true;
}

Future<void> routeInitialRemoteNotificationOpen({
  required GetInitialRemoteMessageFn getInitialMessage,
  PrepareNotificationRouteTargetHandler? onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
  MissingGroupNotificationRouteIdHandler? onMissingGroupRouteId,
  required MissingNotificationRouteTargetHandler onMissingRouteTarget,
}) async {
  await handleInitialRemoteMessage(
    getInitialMessage: getInitialMessage,
    onMessageOpened: (message) => routeRemoteNotificationOpen(
      data: message.data,
      onBeforeRouteTarget: onBeforeRouteTarget,
      onRouteTarget: onRouteTarget,
      onMissingGroupRouteId: onMissingGroupRouteId,
      onMissingRouteTarget: onMissingRouteTarget,
    ),
  );
}
