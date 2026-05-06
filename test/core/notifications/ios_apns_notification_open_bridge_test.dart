import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/ios_apns_notification_open_bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(IosApnsNotificationOpenBridge.channelName);
  late IosApnsNotificationOpenBridge bridge;

  setUp(() {
    bridge = IosApnsNotificationOpenBridge(channel: channel);
    debugSetFlowEventSink(null);
  });

  tearDown(() {
    bridge.dispose();
    debugSetFlowEventSink(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'notificationOpened invokes supplied route handler once with route map',
    () async {
      final routed = <Map<String, dynamic>>[];
      final routeMap = <String, dynamic>{
        'aps': {
          'alert': {'title': 'Alice', 'body': 'Hello'},
        },
        'type': 'new_message',
        'sender_id': 'peer-apns-123',
        'message_id': 'msg-apns-123',
      };

      bridge.register((payload) async {
        routed.add(payload);
      });

      await _sendNativeMethodCall(
        channel,
        MethodCall('notificationOpened', routeMap),
      );

      expect(routed, <Map<String, dynamic>>[routeMap]);
    },
  );

  test('register emits bridge registered flow marker', () async {
    final events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(events.add);

    bridge.register((_) async {});

    expect(
      events,
      contains(
        predicate<Map<String, dynamic>>(
          (event) =>
              event['event'] == 'IOS_APNS_NOTIFICATION_BRIDGE_REGISTERED',
        ),
      ),
    );
  });

  test(
    'markNotificationOpenBridgeReady calls native and emits ready marker',
    () async {
      final events = <Map<String, dynamic>>[];
      final calls = <String>[];
      debugSetFlowEventSink(events.add);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return null;
          });

      final ready = await bridge.markNotificationOpenBridgeReady();

      expect(ready, isTrue);
      expect(calls, <String>['markNotificationOpenBridgeReady']);
      expect(
        events,
        contains(
          predicate<Map<String, dynamic>>(
            (event) => event['event'] == 'IOS_APNS_NOTIFICATION_BRIDGE_READY',
          ),
        ),
      );
    },
  );

  test(
    'consumeInitialNotificationOpen routes pending native map once',
    () async {
      final routed = <Map<String, dynamic>>[];
      final routeMap = <String, dynamic>{
        'aps': {
          'alert': {'title': 'Team', 'body': 'Alice: Hello'},
        },
        'type': 'group_message',
        'groupId': 'group-apns-123',
        'message_id': 'msg-group-apns-123',
      };
      var consumeCalls = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'consumeInitialNotificationOpen');
            consumeCalls += 1;
            return consumeCalls == 1 ? routeMap : null;
          });

      await bridge.consumeInitialNotificationOpen((payload) async {
        routed.add(payload);
      });
      await bridge.consumeInitialNotificationOpen((payload) async {
        routed.add(payload);
      });

      expect(consumeCalls, 2);
      expect(routed, <Map<String, dynamic>>[routeMap]);
    },
  );

  test(
    'consumeInitialNotificationOpen with null emits empty marker and does not route',
    () async {
      final routed = <Map<String, dynamic>>[];
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);

      final routedInitial = await bridge.consumeInitialNotificationOpen((
        payload,
      ) async {
        routed.add(payload);
      });

      expect(routedInitial, isFalse);
      expect(routed, isEmpty);
      expect(
        events,
        contains(
          predicate<Map<String, dynamic>>(
            (event) =>
                event['event'] == 'IOS_APNS_NOTIFICATION_BRIDGE_CONSUME_EMPTY',
          ),
        ),
      );
    },
  );

  test(
    'missing native bridge emits error and later retry can route pending map',
    () async {
      final routed = <Map<String, dynamic>>[];
      final events = <Map<String, dynamic>>[];
      final routeMap = <String, dynamic>{
        'type': 'new_message',
        'sender_id': 'peer-late-native',
        'message_id': 'msg-late-native',
      };
      debugSetFlowEventSink(events.add);

      final firstReady = await bridge.markNotificationOpenBridgeReady();
      final firstConsume = await bridge.consumeInitialNotificationOpen((
        payload,
      ) async {
        routed.add(payload);
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'markNotificationOpenBridgeReady') {
              return null;
            }
            if (call.method == 'consumeInitialNotificationOpen') {
              return routeMap;
            }
            fail('unexpected method ${call.method}');
          });

      final secondReady = await bridge.markNotificationOpenBridgeReady();
      final secondConsume = await bridge.consumeInitialNotificationOpen((
        payload,
      ) async {
        routed.add(payload);
      });

      expect(firstReady, isFalse);
      expect(firstConsume, isFalse);
      expect(secondReady, isTrue);
      expect(secondConsume, isTrue);
      expect(routed, <Map<String, dynamic>>[routeMap]);
      expect(
        events
            .where(
              (event) => event['event'] == 'IOS_APNS_NOTIFICATION_OPEN_ERROR',
            )
            .length,
        greaterThanOrEqualTo(1),
      );
    },
  );

  test('malformed payloads emit an error and do not route', () async {
    final routed = <Map<String, dynamic>>[];
    final events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(events.add);

    bridge.register((payload) async {
      routed.add(payload);
    });

    await _sendNativeMethodCall(
      channel,
      const MethodCall('notificationOpened', 'not-a-map'),
    );

    expect(routed, isEmpty);
    expect(
      events,
      contains(
        predicate<Map<String, dynamic>>(
          (event) => event['event'] == 'IOS_APNS_NOTIFICATION_OPEN_ERROR',
        ),
      ),
    );
  });
}

Future<void> _sendNativeMethodCall(MethodChannel channel, MethodCall call) {
  final completer = Completer<void>();
  final data = channel.codec.encodeMethodCall(call);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channel.name, data, (_) {
        completer.complete();
      });
  return completer.future;
}
