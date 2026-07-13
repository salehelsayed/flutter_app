import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final List<MethodCall> log = <MethodCall>[];
  late Directory notificationIdDirectory;

  FlutterNotificationService buildService({
    DurableConversationNotificationIdRegistry? registry,
  }) {
    final resolvedRegistry =
        registry ??
        DurableConversationNotificationIdRegistry(
          directory: notificationIdDirectory,
        );
    return FlutterNotificationService(
      notificationIdRegistryResolver: () async => resolvedRegistry,
    );
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    log.clear();
    notificationIdDirectory = Directory.systemTemp.createTempSync(
      'flutter-notification-service-id-registry-',
    );

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
    if (notificationIdDirectory.existsSync()) {
      notificationIdDirectory.deleteSync(recursive: true);
    }
  });

  test('initialize wires the plugin, channel, and launch payload', () async {
    final service = buildService();

    await service.initialize();

    expect(log.map((call) => call.method).toList(), <String>[
      'initialize',
      'createNotificationChannel',
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
      final service = buildService();

      await service.initialize();

      expect(await service.consumeInitialPayload(), 'peer-123');
      expect(await service.consumeInitialPayload(), isNull);

      final cancelCall = log.lastWhere((call) => call.method == 'cancel');
      final cancelArgs = cancelCall.arguments as Map;
      expect(cancelArgs['id'], 7);
      expect(log.where((call) => call.method == 'cancelAll'), isEmpty);
    },
  );

  test(
    'onNotificationTap forwards non-empty payloads and dismisses by id',
    () async {
      final service = buildService();
      final tapped = <String>[];
      service.onNotificationTap = tapped.add;

      await service.initialize();
      await _sendNotificationResponse(payload: 'peer-456');

      expect(tapped, <String>['peer-456']);
      final cancelCall = log.lastWhere((call) => call.method == 'cancel');
      final cancelArgs = cancelCall.arguments as Map;
      expect(cancelArgs['id'], 99);
      expect(log.where((call) => call.method == 'cancelAll'), isEmpty);
    },
  );

  test(
    'onNotificationTap ignores null and empty payloads but still dismisses',
    () async {
      final service = buildService();
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
    final service = buildService();

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
      final service = buildService();

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
      final service = buildService();

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
      expect(
        args['id'],
        deterministicConversationNotificationId('group:group-789'),
      );
      final platformSpecifics = args['platformSpecifics'] as Map;
      expect(
        platformSpecifics['category'],
        AndroidNotificationCategory.message.name,
      );
    },
  );

  test('showMessageNotification silent:true uses the silent channel and the '
      'per-conversation notification id', () async {
    final service = buildService();

    await service.initialize();
    await service.showMessageNotification(
      contactPeerId: 'peer-silent',
      senderUsername: 'Alice',
      messageText: 'follow-up',
      silent: true,
    );

    final showCall = log.last;
    expect(showCall.method, 'show');

    final args = showCall.arguments as Map;
    // Reuses the per-conversation id so the OS updates in place.
    expect(args['id'], deterministicConversationNotificationId('peer-silent'));

    final platformSpecifics = args['platformSpecifics'] as Map;
    expect(platformSpecifics['channelId'], mknoonMessagesSilentChannelId);
  });

  test('notification id is per-conversation and stable across a burst for both '
      'direct and group (silent updates reuse the same id)', () async {
    final service = buildService();
    await service.initialize();

    // Direct burst: different per-message payload, SAME notification id.
    await service.showMessageNotification(
      contactPeerId: 'peer-1',
      senderUsername: 'Alice',
      messageText: 'first',
      payload: 'peer-1',
    );
    final firstDirectId = (log.last.arguments as Map)['id'];
    await service.showMessageNotification(
      contactPeerId: 'peer-1',
      senderUsername: 'Alice',
      messageText: 'second',
      payload: 'peer-1',
      silent: true,
    );
    final secondDirectId = (log.last.arguments as Map)['id'];
    expect(firstDirectId, deterministicConversationNotificationId('peer-1'));
    expect(secondDirectId, firstDirectId);

    // Group burst: DIFFERENT routePayload (different embedded messageId),
    // SAME notification id — proves the per-message id does not leak in.
    await service.showMessageNotification(
      contactPeerId: 'group:g1',
      senderUsername: 'Team',
      messageText: 'g-first',
      payload: 'group:g1|message:a',
    );
    final firstGroupId = (log.last.arguments as Map)['id'];
    await service.showMessageNotification(
      contactPeerId: 'group:g1',
      senderUsername: 'Team',
      messageText: 'g-second',
      payload: 'group:g1|message:b',
      silent: true,
    );
    final secondGroupId = (log.last.arguments as Map)['id'];
    expect(firstGroupId, deterministicConversationNotificationId('group:g1'));
    expect(secondGroupId, firstGroupId);
    expect((log.last.arguments as Map)['payload'], 'group:g1|message:b');
  });

  test(
    'forced collisions keep direct, group, and announcement payloads on distinct ids',
    () async {
      final fallbackIds = <String, int>{
        'peer-collision': 701,
        'group:discussion-collision': 702,
        'group:announcement-collision': 703,
      };
      final registry = DurableConversationNotificationIdRegistry(
        directory: notificationIdDirectory,
        candidateGenerator: (key, probe) =>
            probe == 0 ? 700 : fallbackIds[key]! + probe - 1,
      );
      final service = buildService(registry: registry);
      await service.initialize();

      await service.showMessageNotification(
        contactPeerId: 'peer-collision',
        senderUsername: 'Direct',
        messageText: 'direct',
      );
      await service.showMessageNotification(
        contactPeerId: 'group:discussion-collision',
        senderUsername: 'Group',
        messageText: 'group',
        payload: 'group:discussion-collision|message:g-1',
      );
      await service.showMessageNotification(
        contactPeerId: 'group:announcement-collision',
        senderUsername: 'Announcement',
        messageText: 'announcement',
        payload: 'group:announcement-collision|message:a-1',
      );

      final ids = log
          .where((call) => call.method == 'show')
          .map((call) => (call.arguments as Map)['id'] as int)
          .toList();
      expect(ids.toSet(), hasLength(3));
      expect(ids.first, 700);
    },
  );

  test('generic anchored group payloads coalesce on the group card', () async {
    final service = buildService();
    await service.initialize();

    await service.showNotification(
      title: 'Announcements',
      body: 'first',
      payload: 'group:announcement-1|message:first',
    );
    final first = log.last.arguments as Map;
    await service.showNotification(
      title: 'Announcements',
      body: 'second',
      payload: 'group:announcement-1|message:second',
    );
    final second = log.last.arguments as Map;

    expect(first['id'], second['id']);
    expect(second['payload'], 'group:announcement-1|message:second');
  });

  test(
    'allocation storage failure never reaches the plugin show call',
    () async {
      final blocked = File('${notificationIdDirectory.path}/blocked')
        ..writeAsStringSync('not a directory');
      final service = buildService(
        registry: DurableConversationNotificationIdRegistry(
          directory: Directory(blocked.path),
        ),
      );
      await service.initialize();

      await expectLater(
        service.showMessageNotification(
          contactPeerId: 'peer-private',
          senderUsername: 'Alice',
          messageText: 'message',
        ),
        throwsA(isA<NotificationIdAllocationException>()),
      );

      expect(log.where((call) => call.method == 'show'), isEmpty);
    },
  );

  test('clearDeliveredNotifications forwards cancelAll', () async {
    final service = buildService();

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
