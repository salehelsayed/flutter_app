import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/group_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/remote_notification_identity.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';
import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';
import 'package:flutter_app/features/push/application/notification_preview_copy.dart';
import 'package:flutter_app/features/push/application/resolve_group_notification_route_target_use_case.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';

const backgroundPushDefaultTitle = 'New Message';
const backgroundPushDefaultBody = 'You have a new message';
const backgroundPushReactionFallbackTitle = 'Reaction';
const backgroundPushReactionFallbackBody = 'Someone reacted to your message';
const backgroundPushGroupReactionFallbackTitle = 'New reaction';
const backgroundPushGroupReactionFallbackBody =
    'Someone reacted to your message';

// 252: a data-only Intros-routed push with no provider copy must never
// masquerade as a chat message. These route-aware defaults are the safe
// fallback for legacy/copyless `intros` pushes; recognized relay pushes carry
// explicit copy that is preserved byte-for-byte.
const backgroundPushIntrosFallbackTitle = 'Introduction update';
const backgroundPushIntrosFallbackBody =
    'Open Mknoon to see the latest update.';

typedef GroupMessageNotificationDisplayEligibilityResolver =
    Future<GroupMessageNotificationDisplayEligibility> Function(String groupId);
typedef ForegroundGroupReactionNotificationResolver =
    Future<BackgroundPushNotificationFallback?> Function(RemoteMessage message);
typedef ForegroundGroupNotificationReadAcknowledgementResolver =
    Future<bool> Function({
      required String groupId,
      required ConversationNotificationContentKind contentKind,
      required String eventIdentity,
      required BackgroundManagedGroupNotificationComparand? comparand,
    });
typedef ForegroundGroupNotificationPendingReadAcknowledgementResolver =
    Future<bool> Function({
      required String groupId,
      required ConversationNotificationContentKind contentKind,
      required String eventIdentity,
    });

class BackgroundPushNotificationFallback {
  final String title;
  final String body;
  final String? payload;
  final BackgroundManagedGroupNotificationComparand? groupComparand;

  const BackgroundPushNotificationFallback({
    required this.title,
    required this.body,
    this.payload,
    this.groupComparand,
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

/// Returns true only when the canonical row proves this exact incoming group
/// message crossed a durable read boundary. A missing or different row is not
/// acknowledgement of the foreground FCM event.
bool isExactForegroundGroupMessageReadAcknowledgement({
  required String groupId,
  required String eventIdentity,
  required String? canonicalGroupId,
  required String? canonicalMessageId,
  required bool canonicalIsIncoming,
  required DateTime? canonicalReadAt,
}) =>
    groupId.trim().isNotEmpty &&
    eventIdentity.trim().isNotEmpty &&
    canonicalGroupId == groupId &&
    canonicalMessageId == eventIdentity &&
    canonicalIsIncoming &&
    canonicalReadAt != null;

/// Binds an acknowledgement to the exact decrypted reaction-state comparand.
/// A provisional comparand, malformed time, or distinct/newer ADD remains
/// eligible; an old conversation read must never suppress the next transition.
bool isExactForegroundGroupReactionReadAcknowledgement({
  required BackgroundManagedGroupNotificationComparand? comparand,
  required String? canonicalReactionId,
  required String? canonicalMessageId,
  required String? canonicalSenderPeerId,
  required String? canonicalTimestamp,
  required String? canonicalNotificationAcknowledgedAt,
}) {
  if (comparand is! BackgroundGroupReactionNotificationComparand ||
      canonicalNotificationAcknowledgedAt == null) {
    return false;
  }
  final expectedAt = DateTime.tryParse(comparand.timestamp)?.toUtc();
  final canonicalAt = DateTime.tryParse(canonicalTimestamp ?? '')?.toUtc();
  return canonicalReactionId == comparand.reactionId &&
      canonicalMessageId == comparand.messageId &&
      canonicalSenderPeerId == comparand.senderPeerId &&
      expectedAt != null &&
      canonicalAt != null &&
      expectedAt.isAtSameMomentAs(canonicalAt);
}

/// Resolves the exact durable read boundary before any foreground claim, tone,
/// or native show. Pending custody is authoritative for push-before-inbox
/// events; canonical state is consulted only when no exact pending tuple owns
/// this event.
Future<bool> resolveForegroundGroupNotificationReadAcknowledgement({
  required String groupId,
  required ConversationNotificationContentKind contentKind,
  required String eventIdentity,
  ForegroundGroupNotificationPendingReadAcknowledgementResolver?
  pendingReadAcknowledgementResolver,
  required Future<bool> Function() canonicalReadAcknowledgementResolver,
}) async {
  final pendingResolver = pendingReadAcknowledgementResolver;
  if (pendingResolver != null &&
      await pendingResolver(
        groupId: groupId,
        contentKind: contentKind,
        eventIdentity: eventIdentity,
      )) {
    return true;
  }
  return canonicalReadAcknowledgementResolver();
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
  ForegroundGroupReactionNotificationResolver?
  groupReactionNotificationResolver,
  ResolveDurableNotificationCoordinator?
  durableReactionNotificationCoordinatorResolver,
  ActiveConversationTracker? groupConversationTracker,
  AppLifecycleState Function()? getAppLifecycleState,
  ResolveDurableNotificationCoordinator?
  durableGroupMessageNotificationCoordinatorResolver,
  GroupNotificationPresentationCoordinator?
  groupNotificationPresentationCoordinator,
  ForegroundGroupNotificationReadAcknowledgementResolver?
  groupNotificationReadAcknowledgementResolver,
}) async {
  if (result != ForegroundRemoteMessageResult.notificationNeeded) {
    return false;
  }

  if (_routesToGroupReaction(message)) {
    final resolver = groupReactionNotificationResolver;
    final groupId = NotificationRouteTarget.groupIdFromRemoteMessageData(
      message.data,
    );
    final eventId =
        _trimToNull(message.data['event_id']?.toString()) ??
        _trimToNull(message.data['reaction_id']?.toString());
    if (resolver == null || groupId == null || eventId == null) {
      return false;
    }
    final conversationKey = 'group:$groupId';
    final tracker = groupConversationTracker;
    final lifecycle = getAppLifecycleState;
    final coordinatorResolver = durableReactionNotificationCoordinatorResolver;
    if (tracker == null || lifecycle == null || coordinatorResolver == null) {
      throw StateError(
        'group reaction foreground presentation authority unavailable',
      );
    }
    final eventIdentity = boundedReactionEventIdentity(eventId);
    Future<bool> present() async {
      final resolved = await resolver(message);
      if (resolved == null || resolved.payload == null) {
        return false;
      }
      final readAcknowledgementResolver =
          groupNotificationReadAcknowledgementResolver;
      if (readAcknowledgementResolver != null &&
          await readAcknowledgementResolver(
            groupId: groupId,
            contentKind: ConversationNotificationContentKind.reaction,
            eventIdentity: eventIdentity,
            comparand: resolved.groupComparand,
          )) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_FOREGROUND_FALLBACK_NOTIFICATION_SUPPRESSED',
          details: const {'reason': 'canonical_read_acknowledged'},
        );
        return false;
      }
      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: lifecycle,
        contactPeerId: conversationKey,
        routePayload: resolved.payload,
        senderUsername: resolved.title,
        messageText: resolved.body,
        messageId: eventId,
        notificationEventIdentity: eventIdentity,
        notificationEventType: 'message_reaction',
        durableNotificationCoordinatorResolver: coordinatorResolver,
        backgroundDuplicateGuardDelay: Duration.zero,
      );
      return true;
    }

    final presentationCoordinator = groupNotificationPresentationCoordinator;
    if (presentationCoordinator == null) {
      return present();
    }
    return presentationCoordinator.runForGroup(groupId, present);
  }

  final routeTarget = NotificationRouteTarget.fromRemoteMessageData(
    message.data,
  );
  if (routeTarget?.kind == NotificationRouteTargetKind.group) {
    final groupId = _trimToNull(routeTarget?.groupId);
    if (groupId == null) return false;
    final tracker = groupConversationTracker;
    final lifecycle = getAppLifecycleState;
    final coordinatorResolver =
        durableGroupMessageNotificationCoordinatorResolver;
    if (tracker == null || lifecycle == null || coordinatorResolver == null) {
      throw StateError(
        'ordinary group foreground fallback presentation authority unavailable',
      );
    }

    final conversationKey = 'group:$groupId';
    final canonicalMessageId =
        remoteNotificationMessageIdFromData(message.data) ??
        _trimToNull(routeTarget?.messageId);
    final genericBody = localizedNotificationMessage();
    Future<bool> present() async {
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

      if (canonicalMessageId == null) {
        final barePayload = NotificationRouteTarget.group(groupId).toPayload();
        final isViewing =
            tracker.isViewing(conversationKey) ||
            tracker.isViewing(barePayload);
        if (lifecycle() == AppLifecycleState.resumed && isViewing) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_FOREGROUND_FALLBACK_NOTIFICATION_SUPPRESSED',
            details: {
              'reason': 'viewing_conversation_without_canonical_message_id',
              'payload': barePayload,
            },
          );
          return false;
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_FOREGROUND_GROUP_FALLBACK_UNANCHORED',
          details: {'reason': 'missing_canonical_message_id'},
        );
        await notificationService.showMessageNotification(
          contactPeerId: conversationKey,
          senderUsername: 'Mknoon',
          messageText: genericBody,
          payload: barePayload,
          silent: true,
          contentKind: ConversationNotificationContentKind.message,
        );
        return true;
      }

      final canonicalPayload = NotificationRouteTarget.group(
        groupId,
        messageId: canonicalMessageId,
      ).toPayload();
      final readAcknowledgementResolver =
          groupNotificationReadAcknowledgementResolver;
      if (readAcknowledgementResolver != null &&
          await readAcknowledgementResolver(
            groupId: groupId,
            contentKind: ConversationNotificationContentKind.message,
            eventIdentity: canonicalMessageId,
            comparand: null,
          )) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PUSH_FOREGROUND_FALLBACK_NOTIFICATION_SUPPRESSED',
          details: const {'reason': 'canonical_read_acknowledged'},
        );
        return false;
      }
      await maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: lifecycle,
        contactPeerId: conversationKey,
        routePayload: canonicalPayload,
        senderUsername: 'Mknoon',
        messageText: genericBody,
        messageId: canonicalMessageId,
        durableNotificationCoordinatorResolver: coordinatorResolver,
        notificationEventType: 'group_message',
        backgroundDuplicateGuardDelay: Duration.zero,
      );
      return true;
    }

    final presentationCoordinator = groupNotificationPresentationCoordinator;
    if (presentationCoordinator == null) {
      return present();
    }
    return presentationCoordinator.runForGroup(groupId, present);
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
      _trimToNull(message.data['event_id']?.toString()) ??
      _trimToNull(message.data['reaction_id']?.toString()) ??
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
    return _defaultTitleFor(message);
  }
  return _trimToNull(message.data['title']?.toString()) ??
      _defaultTitleFor(message);
}

String _resolvedBody(RemoteMessage message) {
  if (_usesProtectedMessagePreview(message)) {
    return _defaultBodyFor(message);
  }
  return _trimToNull(message.data['body']?.toString()) ??
      _defaultBodyFor(message);
}

String _defaultTitleFor(RemoteMessage message) {
  if (_routesToGroupReaction(message)) {
    return backgroundPushGroupReactionFallbackTitle;
  }
  if (_routesToDirectReaction(message)) {
    return backgroundPushReactionFallbackTitle;
  }
  return _routesToIntros(message)
      ? backgroundPushIntrosFallbackTitle
      : backgroundPushDefaultTitle;
}

String _defaultBodyFor(RemoteMessage message) {
  if (_routesToGroupReaction(message)) {
    return backgroundPushGroupReactionFallbackBody;
  }
  if (_routesToDirectReaction(message)) {
    return backgroundPushReactionFallbackBody;
  }
  return _routesToIntros(message)
      ? backgroundPushIntrosFallbackBody
      : backgroundPushDefaultBody;
}

bool _routesToIntros(RemoteMessage message) {
  return NotificationRouteTarget.fromRemoteMessageData(message.data)?.kind ==
      NotificationRouteTargetKind.intros;
}

bool _routesToDirectReaction(RemoteMessage message) {
  return _trimToNull(message.data['type']?.toString()) == 'message_reaction';
}

bool _routesToGroupReaction(RemoteMessage message) {
  final routeTarget = NotificationRouteTarget.fromRemoteMessageData(
    message.data,
  );
  return routeTarget?.kind == NotificationRouteTargetKind.group &&
      groupNotificationContentKindFromRemoteData(message.data) ==
          ConversationNotificationContentKind.reaction;
}

bool _usesProtectedMessagePreview(RemoteMessage message) {
  final type = _trimToNull(message.data['type']?.toString());
  return type == 'new_message' ||
      type == 'message_reaction' ||
      type == 'group_reaction' ||
      NotificationRouteTarget.isGroupMessageLikeRemoteData(message.data);
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
