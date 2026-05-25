import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

typedef DrainOfflineInboxFn = Future<void> Function();
typedef DrainGroupOfflineInboxForGroupFn =
    Future<void> Function(String groupId);

enum ForegroundRemoteMessageResult { drained, unroutable, notificationNeeded }

Future<ForegroundRemoteMessageResult> handleForegroundRemoteMessage({
  required Map<String, dynamic> data,
  required String? messageId,
  required DrainOfflineInboxFn drainOfflineInbox,
  required DrainGroupOfflineInboxForGroupFn drainGroupOfflineInboxForGroup,
}) async {
  final routeTarget = NotificationRouteTarget.fromRemoteMessageData(data);
  if (routeTarget == null) {
    if (NotificationRouteTarget.isGroupMessageLikeRemoteData(data) &&
        NotificationRouteTarget.groupIdFromRemoteMessageData(data) == null) {
      _emitMissingGroupId(data);
      return ForegroundRemoteMessageResult.unroutable;
    }
    _emitUnroutable(data);
    return ForegroundRemoteMessageResult.unroutable;
  }

  if (routeTarget.kind == NotificationRouteTargetKind.post ||
      routeTarget.kind == NotificationRouteTargetKind.postComment) {
    _emitUnroutable(data);
    return ForegroundRemoteMessageResult.unroutable;
  }

  if (routeTarget.kind == NotificationRouteTargetKind.group) {
    final groupId = routeTarget.groupId;
    if (groupId == null || groupId.isEmpty) {
      _emitMissingGroupId(data);
      return ForegroundRemoteMessageResult.unroutable;
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
        return ForegroundRemoteMessageResult.drained;
      case NotificationRouteTargetKind.group:
        await drainGroupOfflineInboxForGroup(routeTarget.groupId!);
        return ForegroundRemoteMessageResult.drained;
      case NotificationRouteTargetKind.post:
      case NotificationRouteTargetKind.postComment:
        _emitUnroutable(data);
        return ForegroundRemoteMessageResult.unroutable;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_FOREGROUND_DRAIN_ERROR',
      details: {'kind': routeTarget.kind.name, 'error': e.toString()},
    );
    if (routeTarget.kind == NotificationRouteTargetKind.group) {
      return ForegroundRemoteMessageResult.notificationNeeded;
    }
    return ForegroundRemoteMessageResult.drained;
  }
}

void _emitMissingGroupId(Map<String, dynamic> data) {
  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_GROUP_ROUTE_MISSING_GROUP_ID',
    details: NotificationRouteTarget.missingGroupIdTelemetryDetails(data),
  );
}

void _emitUnroutable(Map<String, dynamic> data) {
  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_FOREGROUND_MESSAGE_UNROUTABLE',
    details: {'type': data['type']?.toString(), 'dataKeys': data.keys.toList()},
  );
}
