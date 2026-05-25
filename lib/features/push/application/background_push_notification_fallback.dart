import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';

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

  final routeTarget = NotificationRouteTarget.fromRemoteMessageData(
    message.data,
  );
  if (routeTarget == null) {
    return false;
  }

  return true;
}

BackgroundPushNotificationFallback buildBackgroundPushFallbackNotification(
  RemoteMessage message,
) {
  final payload = _payloadFromMessage(message);
  final title = _resolvedTitle(message);
  final body = _resolvedBody(message);

  return BackgroundPushNotificationFallback(
    title: title,
    body: body,
    payload: payload,
  );
}

Future<bool> showForegroundPushFallbackNotificationIfNeeded({
  required ForegroundRemoteMessageResult result,
  required NotificationService notificationService,
  required RemoteMessage message,
}) async {
  if (result != ForegroundRemoteMessageResult.notificationNeeded) {
    return false;
  }

  final fallback = buildBackgroundPushFallbackNotification(message);
  if (fallback.payload == null) {
    return false;
  }

  await notificationService.showNotification(
    title: fallback.title,
    body: fallback.body,
    payload: fallback.payload,
  );
  return true;
}

String? backgroundPushFallbackDedupeKey(RemoteMessage message) {
  final payload = _payloadFromMessage(message);
  if (payload == null) {
    return null;
  }

  final uniqueId =
      _trimToNull(message.data['message_id']?.toString()) ??
      _trimToNull(message.data['messageId']?.toString()) ??
      _trimToNull(message.data['id']?.toString()) ??
      _trimToNull(message.data['msgId']?.toString()) ??
      _trimToNull(message.messageId);
  final timestamp =
      _trimToNull(message.data['timestamp']?.toString()) ??
      _trimToNull(message.data['sent_at']?.toString()) ??
      _trimToNull(message.data['sentAt']?.toString()) ??
      _trimToNull(message.data['ts']?.toString()) ??
      message.sentTime?.millisecondsSinceEpoch.toString();
  final threadId = _trimToNull(message.threadId);
  final collapseKey = _trimToNull(message.collapseKey);
  final title = _resolvedTitle(message);
  final body = _resolvedBody(message);
  final hasMessageIdentity =
      uniqueId != null ||
      timestamp != null ||
      threadId != null ||
      collapseKey != null;
  final hasSpecificCopy =
      title != backgroundPushDefaultTitle || body != backgroundPushDefaultBody;

  if (!hasMessageIdentity && !hasSpecificCopy) {
    return null;
  }

  final parts = <String>[
    'payload=$payload',
    if (uniqueId != null) 'id=$uniqueId',
    if (timestamp != null) 'ts=$timestamp',
    if (threadId != null) 'thread=$threadId',
    if (collapseKey != null) 'collapse=$collapseKey',
    if (!hasMessageIdentity && title != backgroundPushDefaultTitle)
      'title=$title',
    if (!hasMessageIdentity && body != backgroundPushDefaultBody) 'body=$body',
  ];
  return parts.join('|');
}

String? _payloadFromMessage(RemoteMessage message) {
  return NotificationRouteTarget.fromRemoteMessageData(
    message.data,
  )?.toPayload();
}

String _resolvedTitle(RemoteMessage message) {
  if (_usesProtectedMessagePreview(message)) {
    return backgroundPushDefaultTitle;
  }
  return _trimToNull(message.data['title']?.toString()) ??
      backgroundPushDefaultTitle;
}

String _resolvedBody(RemoteMessage message) {
  if (_usesProtectedMessagePreview(message)) {
    return backgroundPushDefaultBody;
  }
  return _trimToNull(message.data['body']?.toString()) ??
      backgroundPushDefaultBody;
}

bool _usesProtectedMessagePreview(RemoteMessage message) {
  final type = _trimToNull(message.data['type']?.toString());
  return type == 'new_message' ||
      NotificationRouteTarget.isGroupMessageLikeRemoteData(message.data);
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
