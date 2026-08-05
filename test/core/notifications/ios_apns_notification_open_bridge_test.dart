import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app/app/application_root.dart';
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

  test('typed initial consume reports empty and does not route', () async {
    final routed = <Map<String, dynamic>>[];
    final events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(events.add);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final disposition = await bridge
        .consumeInitialNotificationOpenWithDisposition((payload) async {
          routed.add(payload);
        });

    expect(disposition, IosApnsInitialNotificationOpenDisposition.empty);
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
  });

  test(
    'atomic initial consume uses combined native handoff and awaits routing',
    () async {
      final releaseRoute = Completer<void>();
      final calls = <String>[];
      final routed = <Map<String, dynamic>>[];
      final routeMap = <String, dynamic>{
        'type': 'new_message',
        'sender_id': 'peer-atomic-open',
        'message_id': 'msg-atomic-open',
      };

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return routeMap;
          });

      final consume = bridge
          .consumeInitialNotificationOpenAndMarkReadyWithDisposition((
            payload,
          ) async {
            routed.add(payload);
            await releaseRoute.future;
          });
      await Future<void>.delayed(Duration.zero);

      expect(calls, <String>['consumeInitialNotificationOpenAndMarkReady']);
      expect(routed, <Map<String, dynamic>>[routeMap]);

      releaseRoute.complete();
      expect(await consume, IosApnsInitialNotificationOpenDisposition.routed);
    },
  );

  test(
    'failed route retries retained atomic payload without consuming native twice',
    () async {
      const routeMap = <String, dynamic>{
        'type': 'new_message',
        'sender_id': 'peer-retained-open',
        'message_id': 'msg-retained-open',
      };
      var nativeConsumeCalls = 0;
      var routeAttempts = 0;
      final routedPayloads = <Map<String, dynamic>>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(
              call.method,
              IosApnsNotificationOpenBridge
                  .consumeInitialNotificationOpenAndMarkReadyMethod,
            );
            nativeConsumeCalls += 1;
            return routeMap;
          });

      final gate = IosApnsInitialNotificationOpenGate(
        attempt: () =>
            bridge.consumeInitialNotificationOpenAndMarkReadyWithDisposition((
              payload,
            ) async {
              routeAttempts += 1;
              routedPayloads.add(payload);
              if (routeAttempts == 1) {
                throw StateError('route preparation not ready');
              }
            }),
      );

      expect(
        await gate.consume(),
        IosApnsInitialNotificationOpenDisposition.failed,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        await gate.consume(),
        IosApnsInitialNotificationOpenDisposition.routed,
      );
      expect(
        await gate.consume(),
        IosApnsInitialNotificationOpenDisposition.routed,
      );

      expect(nativeConsumeCalls, 1);
      expect(routeAttempts, 2);
      expect(routedPayloads, <Map<String, dynamic>>[routeMap, routeMap]);
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
      final firstConsume = await bridge
          .consumeInitialNotificationOpenWithDisposition((payload) async {
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
      final secondConsume = await bridge
          .consumeInitialNotificationOpenWithDisposition((payload) async {
            routed.add(payload);
          });

      expect(firstReady, isFalse);
      expect(firstConsume, IosApnsInitialNotificationOpenDisposition.failed);
      expect(secondReady, isTrue);
      expect(secondConsume, IosApnsInitialNotificationOpenDisposition.routed);
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

  test('typed initial consume reports malformed payload as failed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'not-a-map');

    final disposition = await bridge
        .consumeInitialNotificationOpenWithDisposition((_) async {});

    expect(disposition, IosApnsInitialNotificationOpenDisposition.failed);
  });

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
