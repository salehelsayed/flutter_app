import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

typedef DrainGroupOfflineInboxForGroupFn =
    Future<void> Function(String groupId);

class PrepareNotificationOpenResult {
  final bool ok;
  final String? error;

  const PrepareNotificationOpenResult._({required this.ok, this.error});

  const PrepareNotificationOpenResult.success() : this._(ok: true);

  const PrepareNotificationOpenResult.failed(String error)
    : this._(ok: false, error: error);
}

Future<PrepareNotificationOpenResult> prepareNotificationOpen({
  required NotificationRouteTarget routeTarget,
  required Future<void> Function() drainOfflineInbox,
  required DrainGroupOfflineInboxForGroupFn drainGroupOfflineInboxForGroup,
}) async {
  try {
    switch (routeTarget.kind) {
      case NotificationRouteTargetKind.conversation:
        await drainOfflineInbox();
        break;
      case NotificationRouteTargetKind.group:
        final groupId = routeTarget.groupId;
        if (groupId == null || groupId.isEmpty) {
          return const PrepareNotificationOpenResult.failed(
            'missing groupId for group notification route',
          );
        }
        await drainGroupOfflineInboxForGroup(groupId);
        break;
      case NotificationRouteTargetKind.intros:
      case NotificationRouteTargetKind.post:
      case NotificationRouteTargetKind.postComment:
        break;
    }

    return const PrepareNotificationOpenResult.success();
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_OPEN_PREPARATION_ERROR',
      details: {'kind': routeTarget.kind.name, 'error': e.toString()},
    );
    return PrepareNotificationOpenResult.failed(e.toString());
  }
}
