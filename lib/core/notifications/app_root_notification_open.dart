import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';

Future<void> routeAppRootInitialLocalNotificationOpen({
  required Future<String?> Function() consumeInitialPayload,
  required PrepareNotificationRouteTargetHandler onBeforeRouteTarget,
  required NotificationRouteTargetHandler onRouteTarget,
}) async {
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
}) async {
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
  required MissingNotificationRouteTargetHandler onMissingRouteTarget,
}) async {
  await routeRemoteNotificationOpen(
    data: data,
    onBeforeRouteTarget: onBeforeRouteTarget,
    onRouteTarget: onRouteTarget,
    onMissingRouteTarget: onMissingRouteTarget,
  );
}
