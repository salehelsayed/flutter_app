import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';

const backgroundPushDefaultTitle = 'New Message';
const backgroundPushDefaultBody = 'You have a new message';

class BackgroundPushNotificationFallback {
  final String title;
  final String body;
  final String? payload;

  const BackgroundPushNotificationFallback({
    required this.title,
    required this.body,
    this.payload,
  });
}

bool shouldShowBackgroundPushFallbackNotification(RemoteMessage message) {
  if (message.notification != null) return false;

  return NotificationRouteTarget.fromRemoteMessageData(message.data) != null;
}

BackgroundPushNotificationFallback buildBackgroundPushFallbackNotification(
  RemoteMessage message,
) {
  final payload = _payloadFromMessage(message);
  final title =
      _trimToNull(message.data['title']) ?? backgroundPushDefaultTitle;
  final body = _trimToNull(message.data['body']) ?? backgroundPushDefaultBody;

  return BackgroundPushNotificationFallback(
    title: title,
    body: body,
    payload: payload,
  );
}

String? _payloadFromMessage(RemoteMessage message) {
  return NotificationRouteTarget.fromRemoteMessageData(
    message.data,
  )?.toPayload();
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
