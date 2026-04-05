import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Production implementation of [NotificationService] using
/// `flutter_local_notifications`.
class FlutterNotificationService implements NotificationService {
  final bool _requestApplePermissions;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  String? _initialPayload;
  int? _initialNotificationId;
  bool _initialPayloadConsumed = false;

  FlutterNotificationService({bool requestApplePermissions = true})
    : _requestApplePermissions = requestApplePermissions;

  @override
  void Function(String payload)? onNotificationTap;

  @override
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    final iosSettings = DarwinInitializationSettings(
      requestSoundPermission: _requestApplePermissions,
      requestBadgePermission: _requestApplePermissions,
      requestAlertPermission: _requestApplePermissions,
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
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    _initialPayload = launchDetails?.notificationResponse?.payload;
    _initialNotificationId = launchDetails?.notificationResponse?.id;

    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_SERVICE_INITIALIZED',
      details: {},
    );
  }

  void _onNotificationResponse(NotificationResponse response) {
    final notificationId = response.id;
    if (notificationId != null) {
      _dismissNotificationById(notificationId, reason: 'notification_tap');
    }

    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_TAPPED',
      details: {
        'payload': payload.length > 32 ? payload.substring(0, 32) : payload,
      },
    );

    onNotificationTap?.call(payload);
  }

  @override
  Future<String?> consumeInitialPayload() async {
    if (_initialPayloadConsumed) {
      return null;
    }
    _initialPayloadConsumed = true;
    final notificationId = _initialNotificationId;
    _initialNotificationId = null;
    if (notificationId != null) {
      await _dismissNotificationById(
        notificationId,
        reason: 'initial_local_notification_launch',
      );
    }
    return _initialPayload;
  }

  Future<void> _dismissNotificationById(
    int notificationId, {
    required String reason,
  }) async {
    try {
      await _plugin.cancel(notificationId);
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_DISMISSED',
        details: {'id': notificationId, 'reason': reason},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_DISMISS_ERROR',
        details: {
          'id': notificationId,
          'reason': reason,
          'error': e.toString(),
        },
      );
    }
  }

  @override
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
  }) async {
    // One notification per conversation — updates on new messages
    final notificationId = contactPeerId.hashCode;
    final resolvedPayload = payload ?? contactPeerId;

    await _plugin.show(
      notificationId,
      senderUsername,
      messageText,
      mknoonMessagesNotificationDetails,
      payload: resolvedPayload,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_SHOWN',
      details: {
        'contactPeerId': contactPeerId.length > 10
            ? contactPeerId.substring(0, 10)
            : contactPeerId,
        'sender': senderUsername,
        'payload': resolvedPayload,
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
  Future<void> clearDeliveredNotifications() async {
    try {
      await _plugin.cancelAll();
      emitFlowEvent(layer: 'FL', event: 'NOTIFICATIONS_CLEARED', details: {});
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATIONS_CLEAR_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  @override
  void dispose() {
    // Nothing to dispose — plugin is a singleton.
  }
}
