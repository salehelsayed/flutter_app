import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';
import 'package:flutter_app/features/push/application/resolve_group_notification_route_target_use_case.dart';

const backgroundPushDefaultTitle = 'New Message';
const backgroundPushDefaultBody = 'You have a new message';

// 252: a data-only Intros-routed push with no provider copy must never
// masquerade as a chat message. These route-aware defaults are the safe
// fallback for legacy/copyless `intros` pushes; recognized relay pushes carry
// explicit copy that is preserved byte-for-byte.
const backgroundPushIntrosFallbackTitle = 'Introduction update';
const backgroundPushIntrosFallbackBody =
    'Open Mknoon to see the latest update.';

typedef GroupMessageNotificationDisplayEligibilityResolver =
    Future<GroupMessageNotificationDisplayEligibility> Function(String groupId);

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

class PushFallbackNotificationDisplayEligibility {
  final bool shouldDisplay;
  final String reason;

  const PushFallbackNotificationDisplayEligibility._({
    required this.shouldDisplay,
    required this.reason,
  });

  const PushFallbackNotificationDisplayEligibility.allow()
    : this._(shouldDisplay: true, reason: 'display_allowed');

  const PushFallbackNotificationDisplayEligibility.suppressed(String reason)
    : this._(shouldDisplay: false, reason: reason);
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

Future<PushFallbackNotificationDisplayEligibility>
resolveBackgroundPushFallbackDisplayEligibility(
  RemoteMessage message, {
  GroupMessageNotificationDisplayEligibilityResolver?
  groupMessageDisplayEligibilityResolver,
}) async {
  return _resolvePushFallbackDisplayEligibility(
    message,
    suppressVisibleProviderNotification: true,
    groupMessageDisplayEligibilityResolver:
        groupMessageDisplayEligibilityResolver,
  );
}

Future<PushFallbackNotificationDisplayEligibility>
resolveForegroundPushFallbackDisplayEligibility(
  RemoteMessage message, {
  GroupMessageNotificationDisplayEligibilityResolver?
  groupMessageDisplayEligibilityResolver,
}) async {
  return _resolvePushFallbackDisplayEligibility(
    message,
    suppressVisibleProviderNotification: false,
    groupMessageDisplayEligibilityResolver:
        groupMessageDisplayEligibilityResolver,
  );
}

Future<PushFallbackNotificationDisplayEligibility>
_resolvePushFallbackDisplayEligibility(
  RemoteMessage message, {
  required bool suppressVisibleProviderNotification,
  GroupMessageNotificationDisplayEligibilityResolver?
  groupMessageDisplayEligibilityResolver,
}) async {
  if (suppressVisibleProviderNotification && message.notification != null) {
    return const PushFallbackNotificationDisplayEligibility.suppressed(
      'not_routable_for_local_fallback',
    );
  }

  final routeTarget = NotificationRouteTarget.fromRemoteMessageData(
    message.data,
  );
  if (routeTarget == null) {
    return const PushFallbackNotificationDisplayEligibility.suppressed(
      'not_routable_for_local_fallback',
    );
  }

  if (routeTarget.kind != NotificationRouteTargetKind.group) {
    return const PushFallbackNotificationDisplayEligibility.allow();
  }

  final groupId = routeTarget.groupId?.trim();
  if (groupId == null || groupId.isEmpty) {
    return const PushFallbackNotificationDisplayEligibility.suppressed(
      'group_route_missing',
    );
  }

  final resolver = groupMessageDisplayEligibilityResolver;
  if (resolver == null) {
    return const PushFallbackNotificationDisplayEligibility.suppressed(
      'group_display_eligibility_unavailable',
    );
  }

  final eligibility = await resolver(groupId);
  if (eligibility.shouldDisplay) {
    return const PushFallbackNotificationDisplayEligibility.allow();
  }
  return PushFallbackNotificationDisplayEligibility.suppressed(
    eligibility.reason,
  );
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
  GroupMessageNotificationDisplayEligibilityResolver?
  groupMessageDisplayEligibilityResolver,
}) async {
  if (result != ForegroundRemoteMessageResult.notificationNeeded) {
    return false;
  }

  final displayEligibility =
      await resolveForegroundPushFallbackDisplayEligibility(
        message,
        groupMessageDisplayEligibilityResolver:
            groupMessageDisplayEligibilityResolver,
      );
  if (!displayEligibility.shouldDisplay) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_FOREGROUND_FALLBACK_NOTIFICATION_SUPPRESSED',
      details: {
        'messageId': message.messageId,
        'reason': displayEligibility.reason,
        'payload': _payloadFromMessage(message) ?? '',
      },
    );
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
  // Compare against the route-aware defaults so the 252 intros fallback copy
  // stays "non-specific" for dedupe purposes, exactly like the old global
  // defaults did.
  final defaultTitle = _defaultTitleFor(message);
  final defaultBody = _defaultBodyFor(message);
  final hasMessageIdentity =
      uniqueId != null ||
      timestamp != null ||
      threadId != null ||
      collapseKey != null;
  final hasSpecificCopy = title != defaultTitle || body != defaultBody;

  if (!hasMessageIdentity && !hasSpecificCopy) {
    return null;
  }

  final parts = <String>[
    'payload=$payload',
    if (uniqueId != null) 'id=$uniqueId',
    if (timestamp != null) 'ts=$timestamp',
    if (threadId != null) 'thread=$threadId',
    if (collapseKey != null) 'collapse=$collapseKey',
    if (!hasMessageIdentity && title != defaultTitle) 'title=$title',
    if (!hasMessageIdentity && body != defaultBody) 'body=$body',
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
      _defaultTitleFor(message);
}

String _resolvedBody(RemoteMessage message) {
  if (_usesProtectedMessagePreview(message)) {
    return backgroundPushDefaultBody;
  }
  return _trimToNull(message.data['body']?.toString()) ??
      _defaultBodyFor(message);
}

String _defaultTitleFor(RemoteMessage message) {
  return _routesToIntros(message)
      ? backgroundPushIntrosFallbackTitle
      : backgroundPushDefaultTitle;
}

String _defaultBodyFor(RemoteMessage message) {
  return _routesToIntros(message)
      ? backgroundPushIntrosFallbackBody
      : backgroundPushDefaultBody;
}

bool _routesToIntros(RemoteMessage message) {
  return NotificationRouteTarget.fromRemoteMessageData(message.data)?.kind ==
      NotificationRouteTargetKind.intros;
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
