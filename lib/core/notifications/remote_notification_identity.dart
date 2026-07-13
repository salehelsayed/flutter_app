import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';

String? remoteNotificationMessageIdFromData(Map<String, dynamic> data) {
  final type = _trimToNull(data['type']?.toString());
  if (type == 'message_reaction' || type == 'group_reaction') {
    return _trimToNull(data['event_id']?.toString()) ??
        _trimToNull(data['reaction_id']?.toString());
  }
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

Future<bool> markRemoteNotificationOpenAsRecentAnnouncement({
  required Map<String, dynamic> data,
  required RecentRemoteNotificationGate gate,
}) async {
  final routeTarget = NotificationRouteTarget.fromRemoteMessageData(data);
  if (routeTarget == null ||
      !routeTargetSupportsMessageAwareRemoteDedupe(routeTarget.kind)) {
    return false;
  }

  await gate.markAnnouncement(
    payload: routeTarget.toPayload(),
    messageId:
        remoteNotificationMessageIdFromData(data) ?? routeTarget.messageId,
  );
  return true;
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
