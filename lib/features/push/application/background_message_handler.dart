import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/notifications/recent_background_notification_gate.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/remote_notification_identity.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/push_decrypt_preview.dart';

final FlutterLocalNotificationsPlugin _backgroundNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
bool _backgroundNotificationsInitialized = false;

typedef BackgroundPushNotificationResolver =
    Future<BackgroundPushNotificationFallback> Function(RemoteMessage message);

BackgroundPushNotificationResolver _backgroundPushNotificationResolver =
    resolveBackgroundPushNotification;

@visibleForTesting
void debugSetBackgroundPushNotificationResolver(
  BackgroundPushNotificationResolver resolver,
) {
  _backgroundPushNotificationResolver = resolver;
}

@visibleForTesting
void debugResetBackgroundPushNotificationResolver() {
  _backgroundPushNotificationResolver = resolveBackgroundPushNotification;
}

Future<void> _initializeBackgroundNotifications() async {
  if (_backgroundNotificationsInitialized) return;

  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
    ),
  );

  await _backgroundNotificationsPlugin.initialize(settings);
  await ensureMknoonNotificationChannel(_backgroundNotificationsPlugin);
  _backgroundNotificationsInitialized = true;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_BACKGROUND_FIREBASE_INIT_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_BACKGROUND_MESSAGE_RECEIVED',
    details: {
      'messageId': message.messageId,
      'dataKeys': message.data.keys.toList(),
      'note':
          'local notification shown if routable; inbox drain on next resume',
    },
  );

  final routeTarget = NotificationRouteTarget.fromRemoteMessageData(
    message.data,
  );
  if (routeTarget != null) {
    final payload = routeTarget.toPayload();
    final messageId =
        routeTargetSupportsMessageAwareRemoteDedupe(routeTarget.kind)
        ? remoteNotificationMessageIdFromData(message.data)
        : null;
    await recentRemoteNotificationGate.markAnnouncement(
      payload: payload,
      messageId: messageId,
    );
  }

  if (!shouldShowBackgroundPushFallbackNotification(message)) {
    return;
  }

  try {
    await _initializeBackgroundNotifications();
    final fallback = await _backgroundPushNotificationResolver(message);
    final dedupeKey = backgroundPushFallbackDedupeKey(message);
    if (dedupeKey != null &&
        await recentBackgroundNotificationGate.wasRecentlyShown(dedupeKey)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
        details: {
          'messageId': message.messageId,
          'reason': 'recent_duplicate_background_push',
          'payload': fallback.payload ?? '',
        },
      );
      return;
    }
    final notificationId =
        (fallback.payload ?? message.messageId ?? fallback.title).hashCode;

    await _backgroundNotificationsPlugin.show(
      notificationId,
      fallback.title,
      fallback.body,
      mknoonMessagesNotificationDetails,
      payload: fallback.payload,
    );
    if (dedupeKey != null) {
      await recentBackgroundNotificationGate.markShown(dedupeKey);
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
      details: {
        'messageId': message.messageId,
        'payload': fallback.payload ?? '',
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_BACKGROUND_NOTIFICATION_ERROR',
      details: {'error': e.toString()},
    );
  }
}
