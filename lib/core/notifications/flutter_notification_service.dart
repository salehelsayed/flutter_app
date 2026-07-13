import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

typedef ConversationNotificationIdRegistryResolver =
    Future<DurableConversationNotificationIdRegistry> Function();
typedef ConversationNotificationIdResolver =
    Future<int> Function(String conversationKey);

/// Production implementation of [NotificationService] using
/// `flutter_local_notifications`.
class FlutterNotificationService implements NotificationService {
  final bool _requestApplePermissions;
  final ConversationNotificationIdRegistryResolver
  _notificationIdRegistryResolver;
  final ConversationNotificationIdResolver? _notificationIdResolver;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  DurableConversationNotificationIdRegistry? _notificationIdRegistry;
  String? _initialPayload;
  int? _initialNotificationId;
  bool _initialPayloadConsumed = false;

  FlutterNotificationService({
    bool requestApplePermissions = true,
    ConversationNotificationIdRegistryResolver? notificationIdRegistryResolver,
    ConversationNotificationIdResolver? notificationIdResolver,
  }) : _requestApplePermissions = requestApplePermissions,
       _notificationIdResolver = notificationIdResolver,
       _notificationIdRegistryResolver =
           notificationIdRegistryResolver ??
           DurableConversationNotificationIdRegistry.openMobileDefault;

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
    bool silent = false,
  }) async {
    // One notification per conversation — updates on new messages. The id is
    // keyed off the conversation (NOT the per-message payload) so a burst
    // coalesces into a single card; the silent variant reuses the SAME id to
    // update in place without sounding (118 Phase 3/4).
    final notificationId = await _resolveNotificationId(contactPeerId);
    final resolvedPayload = payload ?? contactPeerId;

    await _plugin.show(
      notificationId,
      senderUsername,
      messageText,
      mknoonConversationNotificationDetails(
        conversationKey: contactPeerId,
        silent: silent,
      ),
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
        'silent': silent,
      },
    );
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    final notificationId = await _resolveNotificationId(
      _genericNotificationConversationKey(payload: payload, title: title),
    );

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

  Future<int> _resolveNotificationId(String conversationKey) async {
    try {
      final injectedResolver = _notificationIdResolver;
      if (injectedResolver != null) {
        return await injectedResolver(conversationKey);
      }
      var registry = _notificationIdRegistry;
      if (registry == null) {
        registry = await _notificationIdRegistryResolver();
        _notificationIdRegistry = registry;
      }
      return await registry.resolve(
        conversationKey,
        activeNotificationIds: () async =>
            (await _plugin.getActiveNotifications()).map(
              (notification) => notification.id,
            ),
      );
    } catch (error) {
      final allocationError = error is NotificationIdAllocationException
          ? error
          : NotificationIdAllocationException(
              operation: 'registry_open',
              errorType: error.runtimeType.toString(),
            );
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_ID_ALLOCATION_UNAVAILABLE',
        details: {
          'operation': allocationError.operation,
          'errorType': allocationError.errorType,
        },
      );
      throw allocationError;
    }
  }

  String _genericNotificationConversationKey({
    required String? payload,
    required String title,
  }) {
    final target = NotificationRouteTarget.fromPayload(payload);
    return switch (target?.kind) {
      NotificationRouteTargetKind.conversation => target!.peerId!,
      NotificationRouteTargetKind.group => 'group:${target!.groupId!}',
      _ => payload?.trim().isNotEmpty == true ? payload!.trim() : title,
    };
  }
}
