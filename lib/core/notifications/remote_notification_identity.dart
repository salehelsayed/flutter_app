import 'package:flutter_app/core/notifications/notification_route_target.dart';

String? remoteNotificationMessageIdFromData(Map<String, dynamic> data) {
  return _trimToNull(data['message_id']?.toString()) ??
      _trimToNull(data['messageId']?.toString()) ??
      _trimToNull(data['id']?.toString()) ??
      _trimToNull(data['msgId']?.toString());
}

bool routeTargetSupportsMessageAwareRemoteDedupe(
  NotificationRouteTargetKind kind,
) {
  return switch (kind) {
    NotificationRouteTargetKind.conversation => true,
    NotificationRouteTargetKind.group => true,
    _ => false,
  };
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
