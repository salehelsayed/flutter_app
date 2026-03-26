import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final List<MethodCall> log = <MethodCall>[];

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    log.clear();
  });

  test('ensureMknoonNotificationChannel creates the Android channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          log.add(call);
          return null;
        });

    await ensureMknoonNotificationChannel(FlutterLocalNotificationsPlugin());

    expect(log, hasLength(1));
    expect(log.single.method, 'createNotificationChannel');

    final args = log.single.arguments as Map;
    expect(args['id'], mknoonMessagesChannelId);
    expect(args['name'], mknoonMessagesChannelName);
    expect(args['description'], mknoonMessagesChannelDescription);
    expect(args['importance'], Importance.high.value);
    expect(args['showBadge'], isTrue);
    expect(args['playSound'], isTrue);
  });

  test('ensureMknoonNotificationChannel is a no-op off Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          log.add(call);
          return null;
        });

    await ensureMknoonNotificationChannel(FlutterLocalNotificationsPlugin());

    expect(log, isEmpty);
  });

  test('notification details match the channel contract', () {
    final androidDetails =
        mknoonMessagesNotificationDetails.android as AndroidNotificationDetails;
    final iosDetails =
        mknoonMessagesNotificationDetails.iOS as DarwinNotificationDetails;

    expect(androidDetails.channelId, mknoonMessagesChannelId);
    expect(androidDetails.channelName, mknoonMessagesChannelName);
    expect(androidDetails.channelDescription, mknoonMessagesChannelDescription);
    expect(androidDetails.importance, Importance.high);
    expect(androidDetails.priority, Priority.high);
    expect(androidDetails.playSound, isTrue);

    expect(iosDetails.presentSound, isTrue);
    expect(iosDetails.presentAlert, isTrue);
    expect(iosDetails.presentBadge, isTrue);
  });
}
