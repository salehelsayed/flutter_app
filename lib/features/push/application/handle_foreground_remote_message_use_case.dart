import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

typedef DrainOfflineInboxFn = Future<void> Function();
typedef DrainGroupOfflineInboxForGroupFn =
    Future<void> Function(String groupId);

Future<void> handleForegroundRemoteMessage({
  required Map<String, dynamic> data,
  required String? messageId,
  required DrainOfflineInboxFn drainOfflineInbox,
  required DrainGroupOfflineInboxForGroupFn drainGroupOfflineInboxForGroup,
}) async {
  final routeTarget = NotificationRouteTarget.fromRemoteMessageData(data);
  if (routeTarget == null) {
    _emitUnroutable(data);
    return;
  }

  if (routeTarget.kind == NotificationRouteTargetKind.post ||
      routeTarget.kind == NotificationRouteTargetKind.postComment) {
    _emitUnroutable(data);
    return;
  }

  if (routeTarget.kind == NotificationRouteTargetKind.group) {
    final groupId = routeTarget.groupId;
    if (groupId == null || groupId.isEmpty) {
      _emitUnroutable(data);
      return;
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_FOREGROUND_MESSAGE_ROUTED',
    details: {
      'kind': routeTarget.kind.name,
      'hasGroupId': (routeTarget.groupId?.isNotEmpty ?? false),
      'hasMessageId':
          (routeTarget.messageId?.isNotEmpty ?? false) ||
          (messageId?.trim().isNotEmpty ?? false),
    },
  );

  try {
    switch (routeTarget.kind) {
      case NotificationRouteTargetKind.conversation:
      case NotificationRouteTargetKind.contactRequest:
      case NotificationRouteTargetKind.intros:
        await drainOfflineInbox();
        return;
      case NotificationRouteTargetKind.group:
        await drainGroupOfflineInboxForGroup(routeTarget.groupId!);
        return;
      case NotificationRouteTargetKind.post:
      case NotificationRouteTargetKind.postComment:
        _emitUnroutable(data);
        return;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_FOREGROUND_DRAIN_ERROR',
      details: {'kind': routeTarget.kind.name, 'error': e.toString()},
    );
  }
}

void _emitUnroutable(Map<String, dynamic> data) {
  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_FOREGROUND_MESSAGE_UNROUTABLE',
    details: {'type': data['type']?.toString(), 'dataKeys': data.keys.toList()},
  );
}
