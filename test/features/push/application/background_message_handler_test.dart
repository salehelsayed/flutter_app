import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/notifications/recent_background_notification_gate.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    flowEventLoggingEnabled = false;
    log.clear();

    final backgroundGate = RecentBackgroundNotificationGate(
      filePath:
          '${Directory.systemTemp.path}/background-handler-gate-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    debugSetRecentBackgroundNotificationGate(backgroundGate);
    addTearDown(backgroundGate.clear);

    final remoteGate = RecentRemoteNotificationGate(
      filePath:
          '${Directory.systemTemp.path}/background-handler-remote-gate-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    debugSetRecentRemoteNotificationGate(remoteGate);
    addTearDown(remoteGate.clear);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    debugResetRecentBackgroundNotificationGate();
    debugResetRecentRemoteNotificationGate();
    debugResetBackgroundPushNotificationResolver();
  });

  group('firebaseMessagingBackgroundHandler', () {
    test('completes without error for valid RemoteMessage', () async {
      const message = RemoteMessage(
        messageId: 'msg-123',
        data: {'type': 'inbox', 'peerId': '12D3KooW...'},
      );

      // Should not throw
      await firebaseMessagingBackgroundHandler(message);
    });

    test(
      'shows a fallback notification for routable data-only pushes',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'msg-fallback-1',
          data: {'type': 'new_message', 'sender_id': '12D3KooWTestPeer'},
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(
          log.map((call) => call.method).toList(),
          containsAll(<String>[
            'initialize',
            'createNotificationChannel',
            'show',
          ]),
        );

        final channelCall = log.firstWhere(
          (call) => call.method == 'createNotificationChannel',
        );
        final channelArgs = channelCall.arguments as Map;
        expect(channelArgs['id'], mknoonMessagesChannelId);

        final showCall = log.firstWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        expect(showArgs['title'], backgroundPushDefaultTitle);
        expect(showArgs['body'], backgroundPushDefaultBody);
        expect(showArgs['payload'], '12D3KooWTestPeer');
        final platformSpecifics = showArgs['platformSpecifics'] as Map;
        expect(platformSpecifics['channelId'], mknoonMessagesChannelId);
        expect(platformSpecifics['channelName'], mknoonMessagesChannelName);
        expect(
          platformSpecifics['channelDescription'],
          mknoonMessagesChannelDescription,
        );
        expect(platformSpecifics['playSound'], isTrue);
      },
    );

    test(
      'uses injected preview resolver before showing notification',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        debugSetBackgroundPushNotificationResolver((message) async {
          return const BackgroundPushNotificationFallback(
            title: 'Alice',
            body: 'Hello secret',
            payload: 'peer-alice',
          );
        });

        const message = RemoteMessage(
          messageId: 'msg-decrypt-1',
          data: {
            'type': 'new_message',
            'sender_id': 'peer-alice',
            'message_id': 'msg-decrypt-1',
            'kem': 'kem',
            'ciphertext': 'ciphertext',
            'nonce': 'nonce',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        final showCall = log.firstWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        expect(showArgs['title'], 'Alice');
        expect(showArgs['body'], 'Hello secret');
        expect(showArgs['payload'], 'peer-alice');
      },
    );

    test('suppresses a repeated background fallback for the same push', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final gate = RecentBackgroundNotificationGate(
        filePath:
            '${Directory.systemTemp.path}/background-fallback-dedupe-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      debugSetRecentBackgroundNotificationGate(gate);
      addTearDown(gate.clear);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == 'initialize') {
              return true;
            }
            return null;
          });

      final message = RemoteMessage(
        messageId: 'msg-fallback-dedupe-1',
        sentTime: DateTime.utc(2026, 4, 4, 12),
        data: {'type': 'new_message', 'sender_id': '12D3KooWTestPeer'},
      );

      await firebaseMessagingBackgroundHandler(message);
      await firebaseMessagingBackgroundHandler(message);

      expect(log.where((call) => call.method == 'show'), hasLength(1));
    });

    test('handles RemoteMessage with null messageId', () async {
      const message = RemoteMessage(data: {'type': 'inbox'});

      await firebaseMessagingBackgroundHandler(message);
    });

    test('handles RemoteMessage with empty data map', () async {
      const message = RemoteMessage(messageId: 'msg-456');

      await firebaseMessagingBackgroundHandler(message);
    });

    test(
      'records a recent remote notification target even when FCM already carries a visible notification',
      () async {
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/background-handler-visible-push-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);

        const message = RemoteMessage(
          notification: RemoteNotification(title: 'Alice', body: 'Hey!'),
          data: {'type': 'new_message', 'sender_id': '12D3KooWVisiblePeer'},
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: '12D3KooWVisiblePeer',
          ),
          isTrue,
        );
      },
    );

    test(
      'shows iOS local fallback for chat pushes when Flutter surfaces only the data payload',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        IOSFlutterLocalNotificationsPlugin.registerWith();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          data: {
            'type': 'new_message',
            'sender_id': '12D3KooWVisiblePeer',
            'title': 'Alice',
            'body': 'Hey!',
            'message_id': 'msg-visible-chat-1',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        final showCall = log.firstWhere((call) => call.method == 'show');
        final showArgs = showCall.arguments as Map;
        final platformSpecifics = showArgs['platformSpecifics'] as Map;
        expect(platformSpecifics['presentSound'], isTrue);
        expect(platformSpecifics['presentAlert'], isTrue);
        expect(platformSpecifics['presentBadge'], isTrue);
      },
    );
  });
}
