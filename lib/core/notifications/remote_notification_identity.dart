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

/// iOS: a push that arrives while the app is FOREGROUND is provably never
/// presented (willPresent completes with the persisted presentation options —
/// none), yet the NSE already wrote its cross-process "shown" sidecar. Left in
/// place, that marker makes the gate suppress the drain-triggered local banner
/// too, so the user sees nothing at all. Discard the sidecar for exactly this
/// message so the local path presents the one visible banner. Dart-map markers
/// ([RecentRemoteNotificationGate.markAnnouncement]) are untouched, keeping
/// recovery/replay dedupe intact. Returns false for non-message-aware payloads.
Future<bool> discardSuppressedForegroundRemoteSidecar({
  required Map<String, dynamic> data,
  required RecentRemoteNotificationGate gate,
}) async {
  final routeTarget = NotificationRouteTarget.fromRemoteMessageData(data);
  if (routeTarget == null ||
      !routeTargetSupportsMessageAwareRemoteDedupe(routeTarget.kind)) {
    return false;
  }
  final messageId =
      remoteNotificationMessageIdFromData(data) ?? routeTarget.messageId;
  if (messageId == null || messageId.trim().isEmpty) {
    return false;
  }
  await gate.discardSidecarMarker(
    payload: routeTarget.toPayload(),
    messageId: messageId,
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
