import 'package:flutter/services.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/utils/cold_start_notif_anchor.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

typedef IosApnsNotificationOpenHandler =
    Future<void> Function(Map<String, dynamic> payload);

enum IosApnsInitialNotificationOpenDisposition { empty, routed, failed }

class IosApnsNotificationOpenBridge {
  static const channelName = 'mknoon/ios_notification_open';
  static const notificationOpenedMethod = 'notificationOpened';
  static const consumeInitialNotificationOpenMethod =
      'consumeInitialNotificationOpen';
  static const consumeInitialNotificationOpenAndMarkReadyMethod =
      'consumeInitialNotificationOpenAndMarkReady';
  static const markNotificationOpenBridgeReadyMethod =
      'markNotificationOpenBridgeReady';

  final MethodChannel _channel;
  Map<String, dynamic>? _retainedInitialPayload;

  IosApnsNotificationOpenBridge({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  void register(IosApnsNotificationOpenHandler onNotificationOpen) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != notificationOpenedMethod) {
        throw MissingPluginException(
          'No implementation found for method ${call.method} on $channelName',
        );
      }
      await _routePayload(
        rawPayload: call.arguments,
        event: 'IOS_APNS_NOTIFICATION_OPENED',
        phase: notificationOpenedMethod,
        onNotificationOpen: onNotificationOpen,
      );
    });

    emitFlowEvent(
      layer: 'FL',
      event: 'IOS_APNS_NOTIFICATION_BRIDGE_REGISTERED',
      details: {},
    );
  }

  Future<bool> markNotificationOpenBridgeReady() async {
    try {
      await _channel.invokeMethod<void>(markNotificationOpenBridgeReadyMethod);
      emitFlowEvent(
        layer: 'FL',
        event: 'IOS_APNS_NOTIFICATION_BRIDGE_READY',
        details: {},
      );
      return true;
    } catch (error) {
      _emitOpenError(
        phase: markNotificationOpenBridgeReadyMethod,
        error: error,
      );
      return false;
    }
  }

  Future<bool> consumeInitialNotificationOpen(
    IosApnsNotificationOpenHandler onNotificationOpen,
  ) async {
    return await consumeInitialNotificationOpenWithDisposition(
          onNotificationOpen,
        ) ==
        IosApnsInitialNotificationOpenDisposition.routed;
  }

  Future<IosApnsInitialNotificationOpenDisposition>
  consumeInitialNotificationOpenWithDisposition(
    IosApnsNotificationOpenHandler onNotificationOpen,
  ) => _consumeInitialNotificationOpenWithDisposition(
    method: consumeInitialNotificationOpenMethod,
    onNotificationOpen: onNotificationOpen,
  );

  Future<IosApnsInitialNotificationOpenDisposition>
  consumeInitialNotificationOpenAndMarkReadyWithDisposition(
    IosApnsNotificationOpenHandler onNotificationOpen,
  ) => _consumeInitialNotificationOpenWithDisposition(
    method: consumeInitialNotificationOpenAndMarkReadyMethod,
    onNotificationOpen: onNotificationOpen,
  );

  Future<IosApnsInitialNotificationOpenDisposition>
  _consumeInitialNotificationOpenWithDisposition({
    required String method,
    required IosApnsNotificationOpenHandler onNotificationOpen,
  }) async {
    try {
      var initialPayload = _retainedInitialPayload;
      if (initialPayload == null) {
        final rawPayload = await _channel.invokeMethod<dynamic>(method);
        if (rawPayload == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'IOS_APNS_NOTIFICATION_BRIDGE_CONSUME_EMPTY',
            details: {},
          );
          return IosApnsInitialNotificationOpenDisposition.empty;
        }
        initialPayload = _normalizePayload(rawPayload);
        if (initialPayload == null) {
          _emitOpenError(
            phase: method,
            error: StateError('APNs notification-open payload was not a map'),
          );
          return IosApnsInitialNotificationOpenDisposition.failed;
        }

        // The combined native operation transfers custody by clearing its
        // launch slot before replying. Retain that valid map until route
        // preparation succeeds so a failed Dart attempt can retry without
        // asking native for an already-consumed payload.
        _retainedInitialPayload = initialPayload;

        // FDC-S1 Method 5(d): on iOS a cold notif-tap is delivered here (the
        // pending APNs open consumed at launch), NOT via FCM getInitialMessage.
        // Record only on custody transfer; retries must not duplicate the
        // cold-start correlation observation.
        ColdStartNotifAnchor.instance.recordNotifTap(
          NotificationRouteTarget.messageIdFromRemoteMessageData(
            initialPayload,
          ),
        );
      }
      final routed = await _routePayload(
        rawPayload: initialPayload,
        event: 'IOS_APNS_INITIAL_NOTIFICATION_OPENED',
        phase: method,
        onNotificationOpen: onNotificationOpen,
      );
      if (routed && identical(_retainedInitialPayload, initialPayload)) {
        _retainedInitialPayload = null;
      }
      return routed
          ? IosApnsInitialNotificationOpenDisposition.routed
          : IosApnsInitialNotificationOpenDisposition.failed;
    } catch (error) {
      _emitOpenError(phase: method, error: error);
      return IosApnsInitialNotificationOpenDisposition.failed;
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }

  Future<bool> _routePayload({
    required Object? rawPayload,
    required String event,
    required String phase,
    required IosApnsNotificationOpenHandler onNotificationOpen,
  }) async {
    final payload = _normalizePayload(rawPayload);
    if (payload == null) {
      _emitOpenError(
        phase: phase,
        error: StateError('APNs notification-open payload was not a map'),
      );
      return false;
    }

    emitFlowEvent(
      layer: 'FL',
      event: event,
      details: {'dataKeys': payload.keys.toList(growable: false)},
    );

    try {
      await onNotificationOpen(payload);
      return true;
    } catch (error) {
      _emitOpenError(phase: phase, error: error);
      return false;
    }
  }

  Map<String, dynamic>? _normalizePayload(Object? value) {
    if (value is! Map) {
      return null;
    }

    return value.map(
      (key, nestedValue) =>
          MapEntry(key.toString(), _normalizeValue(nestedValue)),
    );
  }

  Object? _normalizeValue(Object? value) {
    if (value is Map) {
      return value.map(
        (key, nestedValue) =>
            MapEntry(key.toString(), _normalizeValue(nestedValue)),
      );
    }
    if (value is Iterable) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    return value;
  }

  void _emitOpenError({required String phase, required Object error}) {
    emitFlowEvent(
      layer: 'FL',
      event: 'IOS_APNS_NOTIFICATION_OPEN_ERROR',
      details: {'phase': phase, 'error': error.toString()},
    );
  }
}
