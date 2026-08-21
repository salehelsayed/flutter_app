import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/notifications/remote_notification_identity.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

typedef DrainOfflineInboxFn = Future<void> Function();
typedef DrainGroupOfflineInboxForGroupFn =
    Future<void> Function(String groupId);
typedef DrainOfflineInboxCompletelyFn = Future<bool> Function();
typedef DrainGroupOfflineInboxForGroupCompletelyFn =
    Future<bool> Function(String groupId);

enum ForegroundRemoteMessageResult {
  drained(canonicalStateComplete: true, needsNotification: false),
  drainFailed(canonicalStateComplete: false, needsNotification: false),
  unroutable(canonicalStateComplete: false, needsNotification: false),

  /// Canonical inbox replay completed, but this event still requires a local
  /// foreground presentation (for example, a group reaction).
  notificationNeeded(canonicalStateComplete: true, needsNotification: true),

  /// Presentation is still useful, but the authoritative inbox replay did not
  /// converge. Keeping this distinct prevents presentation policy from
  /// falsely certifying native recovery completeness.
  notificationNeededAfterDrainFailure(
    canonicalStateComplete: false,
    needsNotification: true,
  );

  const ForegroundRemoteMessageResult({
    required this.canonicalStateComplete,
    required this.needsNotification,
  });

  final bool canonicalStateComplete;
  final bool needsNotification;
}

Future<ForegroundRemoteMessageResult> handleForegroundRemoteMessage({
  required Map<String, dynamic> data,
  required String? messageId,
  required DrainOfflineInboxFn drainOfflineInbox,
  required DrainGroupOfflineInboxForGroupFn drainGroupOfflineInboxForGroup,
  DrainOfflineInboxCompletelyFn? drainOfflineInboxCompletely,
  DrainGroupOfflineInboxForGroupCompletelyFn?
  drainGroupOfflineInboxForGroupCompletely,
  RecentRemoteNotificationGate? recentRemoteGate,
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

  // A foreground arrival reaches this handler exactly BECAUSE iOS did not
  // present it (willPresent completes with no options), yet the NSE has
  // already written its "shown" sidecar. Discard it BEFORE draining — the
  // drain triggers the local materialization, and a surviving sidecar makes
  // the recent-remote gate suppress that banner as a duplicate of a banner
  // that never appeared (the user then sees nothing at all).
  if (recentRemoteGate != null) {
    try {
      await discardSuppressedForegroundRemoteSidecar(
        data: data,
        gate: recentRemoteGate,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_FOREGROUND_SIDECAR_DISCARD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  try {
    switch (routeTarget.kind) {
      case NotificationRouteTargetKind.conversation:
      case NotificationRouteTargetKind.contactRequest:
      case NotificationRouteTargetKind.groupInvite:
      case NotificationRouteTargetKind.intros:
        final complete = drainOfflineInboxCompletely == null
            ? await (() async {
                await drainOfflineInbox();
                return true;
              })()
            : await drainOfflineInboxCompletely();
        return complete
            ? ForegroundRemoteMessageResult.drained
            : ForegroundRemoteMessageResult.drainFailed;
      case NotificationRouteTargetKind.group:
        final complete = drainGroupOfflineInboxForGroupCompletely == null
            ? await (() async {
                await drainGroupOfflineInboxForGroup(routeTarget.groupId!);
                return true;
              })()
            : await drainGroupOfflineInboxForGroupCompletely(
                routeTarget.groupId!,
              );
        if (!complete) {
          return ForegroundRemoteMessageResult
              .notificationNeededAfterDrainFailure;
        }
        return data['type']?.toString().trim() == 'group_reaction'
            ? ForegroundRemoteMessageResult.notificationNeeded
            : ForegroundRemoteMessageResult.drained;
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
      return ForegroundRemoteMessageResult.notificationNeededAfterDrainFailure;
    }
    return ForegroundRemoteMessageResult.drainFailed;
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
