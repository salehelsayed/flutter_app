import 'package:flutter/services.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

typedef IosApnsNotificationOpenHandler =
    Future<void> Function(Map<String, dynamic> payload);

class IosApnsNotificationOpenBridge {
  static const channelName = 'mknoon/ios_notification_open';
  static const notificationOpenedMethod = 'notificationOpened';
  static const consumeInitialNotificationOpenMethod =
      'consumeInitialNotificationOpen';
  static const markNotificationOpenBridgeReadyMethod =
      'markNotificationOpenBridgeReady';

  final MethodChannel _channel;

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
    try {
      final rawPayload = await _channel.invokeMethod<dynamic>(
        consumeInitialNotificationOpenMethod,
      );
      if (rawPayload == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'IOS_APNS_NOTIFICATION_BRIDGE_CONSUME_EMPTY',
          details: {},
        );
        return false;
      }
      return _routePayload(
        rawPayload: rawPayload,
        event: 'IOS_APNS_INITIAL_NOTIFICATION_OPENED',
        phase: consumeInitialNotificationOpenMethod,
        onNotificationOpen: onNotificationOpen,
      );
    } catch (error) {
      _emitOpenError(phase: consumeInitialNotificationOpenMethod, error: error);
      return false;
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
