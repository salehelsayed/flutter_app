import 'dart:async';

import 'package:flutter/foundation.dart';
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
typedef ConversationNotificationIdLookup =
    Future<int?> Function(String conversationKey);
typedef ConversationNotificationContentRegistryResolver =
    Future<ConversationNotificationContentRegistry> Function();

/// Production implementation of [NotificationService] using
/// `flutter_local_notifications`.
class FlutterNotificationService
    implements
        NotificationService,
        ConversationNotificationCancellation,
        ConversationNotificationGenerationCancellation,
        ConversationNotificationGenerationReplacement {
  final bool _requestApplePermissions;
  final ConversationNotificationIdRegistryResolver
  _notificationIdRegistryResolver;
  final ConversationNotificationIdResolver? _notificationIdResolver;
  final ConversationNotificationIdLookup? _notificationIdLookup;
  final ConversationNotificationContentRegistryResolver?
  _notificationContentRegistryResolver;
  final ConversationNotificationGenerationFactory
  _notificationGenerationFactory;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  DurableConversationNotificationIdRegistry? _notificationIdRegistry;
  ConversationNotificationContentRegistry? _notificationContentRegistry;
  String? _initialPayload;
  int? _initialNotificationId;
  bool _initialPayloadConsumed = false;

  FlutterNotificationService({
    bool requestApplePermissions = true,
    ConversationNotificationIdRegistryResolver? notificationIdRegistryResolver,
    ConversationNotificationIdResolver? notificationIdResolver,
    ConversationNotificationIdLookup? notificationIdLookup,
    ConversationNotificationContentRegistryResolver?
    notificationContentRegistryResolver,
    ConversationNotificationGenerationFactory? notificationGenerationFactory,
  }) : _requestApplePermissions = requestApplePermissions,
       _notificationIdResolver = notificationIdResolver,
       _notificationIdLookup = notificationIdLookup,
       _notificationContentRegistryResolver =
           notificationContentRegistryResolver,
       _notificationGenerationFactory =
           notificationGenerationFactory ??
           createConversationNotificationGeneration,
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
    final rawPayload = response.payload;
    final envelope = decodeConversationNotificationPayload(rawPayload);
    if (envelope == null &&
        rawPayload?.trim().startsWith(
              conversationNotificationPayloadEnvelopePrefix,
            ) ==
            true) {
      // A damaged managed envelope has neither a trustworthy route nor an
      // exact generation. Fail closed instead of navigating to encoded bytes
      // or falling back to a stable-id cancellation.
      return;
    }
    if (notificationId != null) {
      if (envelope != null) {
        // Typed Android conversation cards disable platform auto-cancel. The
        // exact generation comparison prevents a delivered old payload from
        // deleting a stable-id replacement. Android PendingIntent extras use
        // FLAG_UPDATE_CURRENT, so strict pre-delivery old-payload identity is
        // a separate native boundary; same-group routing remains correct.
        unawaited(
          _dismissTypedNotificationGeneration(
            notificationId: notificationId,
            envelope: envelope,
            reason: 'notification_tap',
          ),
        );
      } else if (defaultTargetPlatform != TargetPlatform.android) {
        _dismissNotificationById(notificationId, reason: 'notification_tap');
      }
    }

    final payload = envelope?.routePayload ?? rawPayload;
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
    final rawPayload = _initialPayload;
    final envelope = decodeConversationNotificationPayload(rawPayload);
    if (envelope == null &&
        rawPayload?.trim().startsWith(
              conversationNotificationPayloadEnvelopePrefix,
            ) ==
            true) {
      return null;
    }
    if (notificationId != null) {
      if (envelope != null) {
        await _dismissTypedNotificationGeneration(
          notificationId: notificationId,
          envelope: envelope,
          reason: 'initial_local_notification_launch',
        );
      } else if (defaultTargetPlatform != TargetPlatform.android) {
        await _dismissNotificationById(
          notificationId,
          reason: 'initial_local_notification_launch',
        );
      }
    }
    return envelope?.routePayload ?? rawPayload;
  }

  Future<void> _dismissTypedNotificationGeneration({
    required int notificationId,
    required ConversationNotificationPayloadEnvelope envelope,
    required String reason,
  }) async {
    try {
      final registry = await _resolveNotificationContentRegistry();
      final cancelled = await registry.cancelContentIfGeneration(
        conversationKey: envelope.conversationKey,
        notificationId: notificationId,
        generation: envelope.metadata.generation!,
        cancel: () => _dismissNotificationById(
          notificationId,
          reason: reason,
          propagateFailure: true,
        ),
      );
      if (!cancelled) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONVERSATION_NOTIFICATION_CANCEL_SKIPPED',
          details: {'reason': 'content_generation_mismatch_or_unknown'},
        );
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_DISMISS_ERROR',
        details: {
          'id': notificationId,
          'reason': reason,
          'errorType': error.runtimeType.toString(),
        },
      );
    }
  }

  Future<void> _dismissNotificationById(
    int notificationId, {
    required String reason,
    bool propagateFailure = false,
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
      if (propagateFailure) rethrow;
    }
  }

  @override
  Future<void> showMessageNotification({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    ConversationNotificationContentKind? contentKind,
    String? contentEventIdentity,
  }) async {
    // One notification per conversation — updates on new messages. The id is
    // keyed off the conversation (NOT the per-message payload) so a burst
    // coalesces into a single card; the silent variant reuses the SAME id to
    // update in place without sounding (118 Phase 3/4).
    final notificationId = await _resolveNotificationId(contactPeerId);
    final resolvedPayload = payload ?? contactPeerId;
    final metadata = contentKind == null
        ? null
        : ConversationNotificationContentMetadata(
            kind: contentKind,
            eventIdentity: contentEventIdentity?.trim().isEmpty == true
                ? null
                : contentEventIdentity?.trim(),
            generation: _notificationGenerationFactory(),
          );
    final nativePayload = metadata == null
        ? resolvedPayload
        : encodeConversationNotificationPayload(
            routePayload: resolvedPayload,
            conversationKey: contactPeerId,
            metadata: metadata,
          );
    Future<void> show() => _plugin.show(
      notificationId,
      senderUsername,
      messageText,
      mknoonConversationNotificationDetails(
        conversationKey: contactPeerId,
        silent: silent,
        autoCancel: metadata == null,
      ),
      payload: nativePayload,
    );

    if (metadata == null) {
      await show();
    } else {
      final contentRegistry = await _resolveNotificationContentRegistry();
      await contentRegistry.replaceContent(
        conversationKey: contactPeerId,
        notificationId: notificationId,
        metadata: metadata,
        retireCurrent: () => _plugin.cancel(notificationId),
        replace: show,
      );
    }

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
  Future<void> cancelConversationNotification(
    String conversationKey, {
    ConversationNotificationContentKind? onlyIfContentKind,
    ConversationNotificationContentCancellationPredicate? shouldCancelContent,
  }) async {
    final notificationId = await _lookupNotificationId(conversationKey);
    if (notificationId == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONVERSATION_NOTIFICATION_CANCEL_SKIPPED',
        details: {'reason': 'unallocated'},
      );
      return;
    }
    ConversationNotificationContentRegistry? contentRegistry;
    if (onlyIfContentKind != null) {
      contentRegistry = await _resolveNotificationContentRegistry();
      final cancelled = await contentRegistry.cancelContentIfKind(
        conversationKey: conversationKey,
        notificationId: notificationId,
        kind: onlyIfContentKind,
        shouldCancel: shouldCancelContent,
        cancel: () => _dismissNotificationById(
          notificationId,
          reason: 'conversation_read',
          propagateFailure: true,
        ),
      );
      if (!cancelled) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONVERSATION_NOTIFICATION_CANCEL_SKIPPED',
          details: {'reason': 'content_kind_mismatch_or_unknown'},
        );
      }
      return;
    }
    await _dismissNotificationById(
      notificationId,
      reason: 'conversation_read',
      propagateFailure: true,
    );
  }

  @override
  Future<ConversationNotificationContentMetadata?>
  lookupConversationNotificationContentMetadata(String conversationKey) async {
    final notificationId = await _lookupNotificationId(conversationKey);
    if (notificationId == null) return null;
    final registry = await _resolveNotificationContentRegistry();
    return registry.lookupContentMetadata(
      conversationKey: conversationKey,
      notificationId: notificationId,
    );
  }

  @override
  Future<bool> cancelConversationNotificationGeneration(
    String conversationKey,
    String generation,
  ) async {
    final notificationId = await _lookupNotificationId(conversationKey);
    if (notificationId == null) return false;
    final registry = await _resolveNotificationContentRegistry();
    final cancelled = await registry.cancelContentIfGeneration(
      conversationKey: conversationKey,
      notificationId: notificationId,
      generation: generation,
      cancel: () => _dismissNotificationById(
        notificationId,
        reason: 'conversation_acknowledged',
        propagateFailure: true,
      ),
    );
    if (!cancelled) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONVERSATION_NOTIFICATION_CANCEL_SKIPPED',
        details: {'reason': 'content_generation_mismatch_or_unknown'},
      );
    }
    return cancelled;
  }

  @override
  Future<bool> replaceConversationNotificationGeneration(
    String conversationKey,
    String expectedGeneration,
    CanonicalConversationNotificationReplacement replacement,
  ) async {
    final notificationId = await _lookupNotificationId(conversationKey);
    if (notificationId == null) return false;
    final generation = _notificationGenerationFactory();
    final metadata = ConversationNotificationContentMetadata(
      kind: replacement.contentKind,
      eventIdentity: replacement.eventIdentity.trim().isEmpty
          ? null
          : replacement.eventIdentity.trim(),
      generation: generation,
    );
    final payload = encodeConversationNotificationPayload(
      routePayload: replacement.routePayload,
      conversationKey: conversationKey,
      metadata: metadata,
    );
    final registry = await _resolveNotificationContentRegistry();
    final replaced = await registry.replaceContentIfGeneration(
      conversationKey: conversationKey,
      notificationId: notificationId,
      expectedGeneration: expectedGeneration,
      metadata: metadata,
      retireCurrent: () => _plugin.cancel(notificationId),
      replace: () => _plugin.show(
        notificationId,
        replacement.senderUsername,
        replacement.messageText,
        mknoonConversationNotificationDetails(
          conversationKey: conversationKey,
          silent: true,
          autoCancel: false,
        ),
        payload: payload,
      ),
    );
    if (!replaced) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONVERSATION_NOTIFICATION_REBUILD_SKIPPED',
        details: {'reason': 'content_generation_mismatch_or_unknown'},
      );
    }
    return replaced;
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

  Future<ConversationNotificationContentRegistry>
  _resolveNotificationContentRegistry() async {
    var registry = _notificationContentRegistry;
    if (registry != null) return registry;
    final injected = _notificationContentRegistryResolver;
    if (injected != null) {
      registry = await injected();
    } else {
      registry = _notificationIdRegistry;
      if (registry == null) {
        final resolvedRegistry = await _notificationIdRegistryResolver();
        _notificationIdRegistry = resolvedRegistry;
        registry = resolvedRegistry;
      }
    }
    _notificationContentRegistry = registry;
    return registry;
  }

  Future<int?> _lookupNotificationId(String conversationKey) async {
    try {
      final injectedLookup = _notificationIdLookup;
      if (injectedLookup != null) {
        return await injectedLookup(conversationKey);
      }
      // An allocation-only injected resolver cannot prove whether an id was
      // previously published, so exact cancellation fails closed.
      if (_notificationIdResolver != null) return null;
      var registry = _notificationIdRegistry;
      if (registry == null) {
        registry = await _notificationIdRegistryResolver();
        _notificationIdRegistry = registry;
      }
      return await registry.lookup(conversationKey);
    } catch (error) {
      final lookupError = error is NotificationIdAllocationException
          ? error
          : NotificationIdAllocationException(
              operation: 'registry_lookup',
              errorType: error.runtimeType.toString(),
            );
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_ID_LOOKUP_UNAVAILABLE',
        details: {
          'operation': lookupError.operation,
          'errorType': lookupError.errorType,
        },
      );
      throw lookupError;
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
