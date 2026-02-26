import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Production implementation of [NotificationService] using
/// `flutter_local_notifications`.
class FlutterNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'mknoon_messages';
  static const _channelName = 'Messages';
  static const _channelDescription = 'Incoming message notifications';

  @override
  void Function(String contactPeerId)? onNotificationTap;

  @override
  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

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
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentSound: true,
      presentAlert: true,
      presentBadge: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // One notification per conversation — updates on new messages
    final notificationId = contactPeerId.hashCode;

    await _plugin.show(
      notificationId,
      senderUsername,
      messageText,
      details,
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
  void dispose() {
    // Nothing to dispose — plugin is a singleton.
  }
}
