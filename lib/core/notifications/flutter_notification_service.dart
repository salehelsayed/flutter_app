import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Production implementation of [NotificationService] using
/// `flutter_local_notifications`.
class FlutterNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  @override
  void Function(String contactPeerId)? onNotificationTap;

  @override
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    await ensureMknoonNotificationChannel(_plugin);

    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_SERVICE_INITIALIZED',
      details: {},
    );
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_TAPPED',
      details: {
        'contactPeerId': payload.length > 10
            ? payload.substring(0, 10)
            : payload,
      },
    );

    onNotificationTap?.call(payload);
  }

  @override
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
  }) async {
    // One notification per conversation — updates on new messages
    final notificationId = contactPeerId.hashCode;

    await _plugin.show(
      notificationId,
      senderUsername,
      messageText,
      mknoonMessagesNotificationDetails,
      payload: contactPeerId,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_SHOWN',
      details: {
        'contactPeerId': contactPeerId.length > 10
            ? contactPeerId.substring(0, 10)
            : contactPeerId,
        'sender': senderUsername,
      },
    );
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    // Use payload hashCode for notification ID so same-type notifications update
    final notificationId = (payload ?? title).hashCode;

    await _plugin.show(
      notificationId,
      title,
      body,
      mknoonMessagesNotificationDetails,
      payload: payload,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_SHOWN',
      details: {'title': title, 'payload': payload ?? ''},
    );
  }

  @override
  void dispose() {
    // Nothing to dispose — plugin is a singleton.
  }
}
