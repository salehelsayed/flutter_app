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

    debugSetBackgroundAccountMigrationNetworkGate(({
      String? peerId,
      required String operation,
    }) async {
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    debugSetFlowEventSink(null);
    debugResetRecentBackgroundNotificationGate();
    debugResetRecentRemoteNotificationGate();
    debugResetBackgroundPushNotificationResolver();
    debugResetBackgroundPushNotificationDisplayEligibilityResolver();
    debugResetBackgroundAccountMigrationNetworkGate();
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
      'suppresses background fallback when account migration runtime gate blocks',
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

        final gateCalls = <String>[];
        debugSetBackgroundAccountMigrationNetworkGate(({
          String? peerId,
          required String operation,
        }) async {
          gateCalls.add(operation);
          return false;
        });

        const message = RemoteMessage(
          messageId: 'msg-migration-blocked-1',
          data: {'type': 'new_message', 'sender_id': '12D3KooWTestPeer'},
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(gateCalls, <String>['push_background_notification_display']);
        expect(log.where((call) => call.method == 'show'), isEmpty);
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
      'GIRD-006 does not mark remote announcement when group fallback display fails',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/gird006-background-display-failure-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              if (call.method == 'show') {
                throw PlatformException(
                  code: 'display_failed',
                  message: 'blocked by OS notification state',
                );
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'fcm-gird006-display-fail',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-display-fail',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'group:group-gird006|message:msg-gird006-display-fail',
            messageId: 'msg-gird006-display-fail',
          ),
          isFalse,
          reason:
              'A failed local fallback must not suppress the later listener notification.',
        );
      },
    );

    test(
      'suppresses group background fallback when display eligibility denies it',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async =>
              const PushFallbackNotificationDisplayEligibility.suppressed(
                'group_missing',
              ),
        );
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/background-group-display-denied-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'fcm-session03-denied',
          data: {
            'type': 'group_message',
            'groupId': 'group-session03',
            'message_id': 'msg-session03-denied',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(log.where((call) => call.method == 'show'), isEmpty);
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'group:group-session03|message:msg-session03-denied',
            messageId: 'msg-session03-denied',
          ),
          isFalse,
        );
        final suppressionEvent = events.lastWhere(
          (event) =>
              event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
        );
        expect(
          suppressionEvent['details'],
          containsPair('reason', 'group_missing'),
        );
        expect(
          suppressionEvent['details'],
          containsPair(
            'payload',
            'group:group-session03|message:msg-session03-denied',
          ),
        );
      },
    );

    test(
      'GIRD-006 marks remote announcement after successful group fallback display',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/gird006-background-display-success-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(gate.clear);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'fcm-gird006-display-success',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-display-success',
          },
        );

        await firebaseMessagingBackgroundHandler(message);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'group:group-gird006|message:msg-gird006-display-success',
            messageId: 'msg-gird006-display-success',
          ),
          isTrue,
        );
      },
    );

    test(
      'GIRD-006 coalesces duplicate group background fallback by logical message id',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const message = RemoteMessage(
          messageId: 'fcm-gird006-transport-a',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-duplicate',
          },
        );
        const duplicateTransportMessage = RemoteMessage(
          messageId: 'fcm-gird006-transport-b',
          data: {
            'type': 'group_message',
            'groupId': 'group-gird006',
            'message_id': 'msg-gird006-duplicate',
          },
        );

        await firebaseMessagingBackgroundHandler(message);
        await firebaseMessagingBackgroundHandler(duplicateTransportMessage);

        expect(log.where((call) => call.method == 'show'), hasLength(1));
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
        expect(showArgs['title'], backgroundPushDefaultTitle);
        expect(showArgs['body'], backgroundPushDefaultBody);
        final platformSpecifics = showArgs['platformSpecifics'] as Map;
        expect(platformSpecifics['presentSound'], isTrue);
        expect(platformSpecifics['presentAlert'], isTrue);
        expect(platformSpecifics['presentBadge'], isTrue);
      },
    );

    // 118 Phase 7 (VERIFICATION/CHARACTERIZATION): confirm the FCM background
    // path is uncorrupted by the live-direct routing + foreground tone debounce.
    test(
      'background direct fallback stays audible and per-conversation — the '
      'foreground tone debounce never reaches the FCM isolate (OQ-4)',
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

        // A suspended burst of two distinct messages from the SAME sender.
        const first = RemoteMessage(
          messageId: 'm-burst-a',
          data: {'type': 'new_message', 'sender_id': '12D3KooWPeerBurst'},
        );
        const second = RemoteMessage(
          messageId: 'm-burst-b',
          data: {'type': 'new_message', 'sender_id': '12D3KooWPeerBurst'},
        );

        await firebaseMessagingBackgroundHandler(first);
        await firebaseMessagingBackgroundHandler(second);

        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(2));

        final id0 = (shows[0].arguments as Map)['id'];
        final id1 = (shows[1].arguments as Map)['id'];
        // Direct background notifications coalesce per conversation.
        expect(id0, '12D3KooWPeerBurst'.hashCode);
        expect(id1, id0);

        // Always audible (mknoonMessagesNotificationDetails) — the silent
        // variant is foreground/live-only.
        final ps0 = (shows[0].arguments as Map)['platformSpecifics'] as Map;
        expect(ps0['channelId'], mknoonMessagesChannelId);
        expect(ps0['playSound'], isTrue);
      },
    );

    test(
      'background GROUP fallback id is per-message so a suspended burst does '
      'NOT coalesce — PRE-EXISTING calm gap flagged for OQ-4, not 118 scope',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        AndroidFlutterLocalNotificationsPlugin.registerWith();
        debugSetBackgroundPushNotificationDisplayEligibilityResolver(
          (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              log.add(call);
              if (call.method == 'initialize') {
                return true;
              }
              return null;
            });

        const first = RemoteMessage(
          messageId: 'fcm-burst-a',
          data: {
            'type': 'group_message',
            'groupId': 'group-burst',
            'message_id': 'gmsg-a',
          },
        );
        const second = RemoteMessage(
          messageId: 'fcm-burst-b',
          data: {
            'type': 'group_message',
            'groupId': 'group-burst',
            'message_id': 'gmsg-b',
          },
        );

        await firebaseMessagingBackgroundHandler(first);
        await firebaseMessagingBackgroundHandler(second);

        final shows = log.where((call) => call.method == 'show').toList();
        expect(shows, hasLength(2));

        final id0 = (shows[0].arguments as Map)['id'];
        final id1 = (shows[1].arguments as Map)['id'];
        // Distinct ids: each group message is its own card in the background.
        // This is a pre-existing gap (the live foreground path coalesces via
        // contactPeerId.hashCode); documented in OQ-4, out of 118 scope.
        expect(id0, isNot(id1));
      },
    );
  });

  // 04-P0 / SI-1 — the background (Android encrypted-DB) producer must honor
  // mute. The is_muted read is unit-tested via the pure `groups`-row helper so
  // it does not require a SQLCipher identity.db fixture.
  group('groupMemberMessageDisplayEligibility (background mute, 04-P0)', () {
    test('suppresses a muted group member with reason "muted"', () {
      final eligibility = groupMemberMessageDisplayEligibility({'is_muted': 1});
      expect(eligibility.shouldDisplay, isFalse);
      expect(eligibility.reason, 'muted');
    });

    test('allows an un-muted group member', () {
      final eligibility = groupMemberMessageDisplayEligibility({'is_muted': 0});
      expect(eligibility.shouldDisplay, isTrue);
      expect(eligibility.reason, 'current_member');
    });

    test('fails open (notifies) when the is_muted column is absent/null', () {
      expect(
        groupMemberMessageDisplayEligibility(<String, Object?>{}).shouldDisplay,
        isTrue,
      );
      expect(
        groupMemberMessageDisplayEligibility({'is_muted': null}).shouldDisplay,
        isTrue,
      );
    });
  });
}
