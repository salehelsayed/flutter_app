import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/headless_missed_call_notification.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';

/// 408: post the missed-call card from the killed-app isolate.
///
/// A call that arrives while the app is dead has no FlutterNotificationService
/// and no widget tree. Plan 406 gave that path its history row, but the user
/// still got no card for it — exactly the case where one matters most,
/// because there is no app to come back to and see. This isolate initializes
/// its own plugin, the way the background push handler already does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final log = <MethodCall>[];
  const contactPeerId = '12D3KooWTestPeerId1234567890';

  void installHandler({Object? failOn}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          log.add(call);
          if (failOn != null && call.method == failOn) {
            throw PlatformException(code: 'boom');
          }
          // The plugin's own mappers dereference these replies unguarded, so
          // a bare null throws inside the plugin instead of exercising the
          // code under test.
          return switch (call.method) {
            'initialize' => true,
            'getNotificationAppLaunchDetails' => <String, Object?>{
              'notificationLaunchedApp': false,
            },
            _ => null,
          };
        });
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    log.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('TC-408-01 the first post initializes the plugin and creates every '
      'channel', () async {
    installHandler();
    final notifier = HeadlessMissedCallNotification();

    await notifier.show(
      contactAccountPeerId: contactPeerId,
      title: 'Alice',
      body: 'Missed voice call',
    );

    final methods = log.map((call) => call.method).toList();
    expect(methods.first, 'initialize');
    expect(
      methods.where((m) => m == 'createNotificationChannel').length,
      mknoonNotificationChannels.length,
      reason:
          'a channel that was never created posts nothing at all on Android '
          '8+, and this isolate has its own plugin instance',
    );
    expect(methods.last, 'show');
  });

  test('TC-408-02 the card publishes on the calls channel under the '
      'call-scoped id', () async {
    installHandler();

    await HeadlessMissedCallNotification().show(
      contactAccountPeerId: contactPeerId,
      title: 'Alice',
      body: 'Missed voice call',
    );

    final show = log.lastWhere((call) => call.method == 'show');
    final args = show.arguments as Map;
    expect(
      args['id'],
      deterministicConversationNotificationId('call:$contactPeerId'),
      reason: 'the same id the foreground path uses, so the two converge',
    );
    expect(args['title'], 'Alice');
    expect(args['body'], 'Missed voice call');
    expect(args['payload'], contactPeerId);
    expect(
      ((args['platformSpecifics'] as Map)['channelId']),
      mknoonCallsChannelId,
    );
  });

  test('TC-408-03 a second card does not re-initialize the plugin', () async {
    installHandler();
    final notifier = HeadlessMissedCallNotification();

    await notifier.show(
      contactAccountPeerId: contactPeerId,
      title: 'Alice',
      body: 'Missed voice call',
    );
    log.clear();
    await notifier.show(
      contactAccountPeerId: contactPeerId,
      title: 'Alice',
      body: 'Missed voice call',
    );

    expect(log.map((call) => call.method), <String>['show']);
  });

  test(
    'TC-408-04 a failing platform is reported to the caller, not hidden',
    () async {
      installHandler(failOn: 'show');

      // Swallowing here as well made MissedCallNotifier report
      // MISSED_CALL_NOTIFICATION_SHOWN for a card that was never drawn
      // (device 2026-09-05 22:00:41Z, MissingPluginException).
      await expectLater(
        HeadlessMissedCallNotification().show(
          contactAccountPeerId: contactPeerId,
          title: 'Alice',
          body: 'Missed voice call',
        ),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test('TC-408-05 a failing initialize is reported too', () async {
    installHandler(failOn: 'initialize');

    // Swallowing here as well made MissedCallNotifier report
    // MISSED_CALL_NOTIFICATION_SHOWN for a card that was never drawn.
    await expectLater(
      HeadlessMissedCallNotification().show(
        contactAccountPeerId: contactPeerId,
        title: 'Alice',
        body: 'Missed voice call',
      ),
      throwsA(isA<PlatformException>()),
    );
  });
}
