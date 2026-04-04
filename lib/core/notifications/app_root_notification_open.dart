import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';

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
  required MissingNotificationRouteTargetHandler onMissingRouteTarget,
  NotificationOpenSideEffect? onBeforeOpen,
}) async {
  await onBeforeOpen?.call();
  await routeRemoteNotificationOpen(
    data: data,
    onBeforeRouteTarget: onBeforeRouteTarget,
    onRouteTarget: onRouteTarget,
    onMissingRouteTarget: onMissingRouteTarget,
  );
}
