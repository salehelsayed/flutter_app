import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    log.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          log.add(call);
          switch (call.method) {
            case 'initialize':
              return true;
            case 'getNotificationAppLaunchDetails':
              return <String, Object?>{
                'notificationLaunchedApp': true,
                'notificationResponse': <String, Object?>{
                  'notificationId': 7,
                  'actionId': null,
                  'input': null,
                  'notificationResponseType':
                      NotificationResponseType.selectedNotification.index,
                  'payload': 'peer-123',
                },
              };
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('initialize wires the plugin, channel, and launch payload', () async {
    final service = FlutterNotificationService();

    await service.initialize();

    expect(log.map((call) => call.method).toList(), <String>[
      'initialize',
      'createNotificationChannel',
      'getNotificationAppLaunchDetails',
    ]);

    final initializeArgs = log[0].arguments as Map;
    expect(initializeArgs['defaultIcon'], '@mipmap/ic_launcher');

    final channelArgs = log[1].arguments as Map;
    expect(channelArgs['id'], mknoonMessagesChannelId);
    expect(channelArgs['name'], mknoonMessagesChannelName);
    expect(channelArgs['description'], mknoonMessagesChannelDescription);
    expect(channelArgs['importance'], Importance.high.value);
  });

  test(
    'consumeInitialPayload dismisses the launch notification once',
    () async {
      final service = FlutterNotificationService();

      await service.initialize();

      expect(await service.consumeInitialPayload(), 'peer-123');
      expect(await service.consumeInitialPayload(), isNull);

      final cancelCall = log.lastWhere((call) => call.method == 'cancel');
      final cancelArgs = cancelCall.arguments as Map;
      expect(cancelArgs['id'], 7);
    },
  );

  test(
    'onNotificationTap forwards non-empty payloads and dismisses by id',
    () async {
      final service = FlutterNotificationService();
      final tapped = <String>[];
      service.onNotificationTap = tapped.add;

      await service.initialize();
      await _sendNotificationResponse(payload: 'peer-456');

      expect(tapped, <String>['peer-456']);
      final cancelCall = log.lastWhere((call) => call.method == 'cancel');
      final cancelArgs = cancelCall.arguments as Map;
      expect(cancelArgs['id'], 99);
    },
  );

  test(
    'onNotificationTap ignores null and empty payloads but still dismisses',
    () async {
      final service = FlutterNotificationService();
      final tapped = <String>[];
      service.onNotificationTap = tapped.add;

      await service.initialize();
      await _sendNotificationResponse(payload: null);
      await _sendNotificationResponse(payload: '');

      expect(tapped, isEmpty);
      final cancelCalls = log.where((call) => call.method == 'cancel').toList();
      expect(cancelCalls, hasLength(2));
      for (final call in cancelCalls) {
        final args = call.arguments as Map;
        expect(args['id'], 99);
      }
    },
  );

  test('showNotification forwards title, body, payload, and details', () async {
    final service = FlutterNotificationService();

    await service.initialize();
    await service.showNotification(
      title: 'Hello',
      body: 'World',
      payload: 'payload-123',
    );

    final showCall = log.last;
    expect(showCall.method, 'show');

    final args = showCall.arguments as Map;
    expect(args['title'], 'Hello');
    expect(args['body'], 'World');
    expect(args['payload'], 'payload-123');
    expect(args['id'], isA<int>());

    final platformSpecifics = args['platformSpecifics'] as Map;
    expect(platformSpecifics['channelId'], mknoonMessagesChannelId);
    expect(platformSpecifics['channelName'], mknoonMessagesChannelName);
    expect(
      platformSpecifics['channelDescription'],
      mknoonMessagesChannelDescription,
    );
  });

  test(
    'showMessageNotification forwards conversation payload and details',
    () async {
      final service = FlutterNotificationService();

      await service.initialize();
      await service.showMessageNotification(
        contactPeerId: 'peer-789',
        senderUsername: 'Alice',
        messageText: 'Ping',
      );

      final showCall = log.last;
      expect(showCall.method, 'show');

      final args = showCall.arguments as Map;
      expect(args['title'], 'Alice');
      expect(args['body'], 'Ping');
      expect(args['payload'], 'peer-789');
      expect(args['id'], isA<int>());

      final platformSpecifics = args['platformSpecifics'] as Map;
      expect(platformSpecifics['channelId'], mknoonMessagesChannelId);
      expect(platformSpecifics['channelName'], mknoonMessagesChannelName);
    },
  );

  test(
    'showMessageNotification forwards explicit group anchor payload overrides',
    () async {
      final service = FlutterNotificationService();

      await service.initialize();
      await service.showMessageNotification(
        contactPeerId: 'group:group-789',
        senderUsername: 'Team Chat',
        messageText: 'Alice: Ping',
        payload: 'group:group-789|message:msg-789',
      );

      final showCall = log.last;
      expect(showCall.method, 'show');

      final args = showCall.arguments as Map;
      expect(args['title'], 'Team Chat');
      expect(args['body'], 'Alice: Ping');
      expect(args['payload'], 'group:group-789|message:msg-789');
      expect(args['id'], 'group:group-789'.hashCode);
    },
  );

  test('clearDeliveredNotifications forwards cancelAll', () async {
    final service = FlutterNotificationService();

    await service.initialize();
    await service.clearDeliveredNotifications();

    expect(log.last.method, 'cancelAll');
  });
}

Future<void> _sendNotificationResponse({required String? payload}) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        const MethodChannel('dexterous.com/flutter/local_notifications').name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('didReceiveNotificationResponse', <String, Object?>{
            'notificationId': 99,
            'actionId': null,
            'input': null,
            'notificationResponseType':
                NotificationResponseType.selectedNotification.index,
            'payload': payload,
          }),
        ),
        (_) {},
      );
}
