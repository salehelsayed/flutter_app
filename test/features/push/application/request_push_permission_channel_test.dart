import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/notifications/local_notification_support.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/push_registration_coordinator.dart';
import 'package:flutter_app/features/push/application/push_registration_health_notifier.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart';
import 'package:flutter_app/features/push/application/request_push_permission_use_case.dart';
import 'package:flutter_app/features/push/presentation/widgets/push_registration_health_warning.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationSettings _authorizedSettings() => const NotificationSettings(
  authorizationStatus: AuthorizationStatus.authorized,
  alert: AppleNotificationSetting.enabled,
  announcement: AppleNotificationSetting.enabled,
  badge: AppleNotificationSetting.enabled,
  carPlay: AppleNotificationSetting.disabled,
  lockScreen: AppleNotificationSetting.enabled,
  notificationCenter: AppleNotificationSetting.enabled,
  showPreviews: AppleShowPreviewSetting.always,
  timeSensitive: AppleNotificationSetting.disabled,
  criticalAlert: AppleNotificationSetting.disabled,
  sound: AppleNotificationSetting.enabled,
  providesAppNotificationSettings: AppleNotificationSetting.disabled,
);

Map<String, Object?> _channelReply(String id, Importance importance) => {
  'id': id,
  'name': id,
  'description': null,
  'groupId': null,
  'showBadge': true,
  'importance': importance.value,
  'playSound': true,
  'soundSource': null,
  'enableLights': false,
  'enableVibration': true,
  'vibrationPattern': null,
  'ledColor': 0,
  'audioAttributesUsage': 5,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  var primaryImportance = Importance.none;
  List<Map<String, Object?>>? channels;
  final calls = <String>[];

  setUp(() {
    flowEventLoggingEnabled = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    primaryImportance = Importance.none;
    channels = null;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'areNotificationsEnabled' => true,
            'getNotificationChannels' =>
              channels ??
                  [
                    _channelReply(mknoonMessagesChannelId, primaryImportance),
                    _channelReply(
                      mknoonMessagesSilentChannelId,
                      Importance.low,
                    ),
                  ],
            _ => throw StateError(
              'Unexpected notification call: ${call.method}',
            ),
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'NOTIFY-004 request rejects a blocked Messages channel despite global grant',
    () async {
      expect(
        await requestPushPermission(
          requestPermissionFn: () async => _authorizedSettings(),
        ),
        isFalse,
      );
      expect(calls, ['areNotificationsEnabled', 'getNotificationChannels']);
    },
  );

  test(
    'NOTIFY-004 read sees a blocked Messages channel without requesting permission',
    () async {
      expect(
        await readPushPermission(
          readSettingsFn: () async => _authorizedSettings(),
        ),
        isFalse,
      );
      expect(calls, ['areNotificationsEnabled', 'getNotificationChannels']);
    },
  );

  for (final importance in [Importance.low, Importance.high]) {
    test(
      'keeps a postable Messages channel at ${importance.name} granted',
      () async {
        primaryImportance = importance;
        expect(
          await readPushPermission(
            readSettingsFn: () async => _authorizedSettings(),
          ),
          isTrue,
        );
      },
    );
  }

  test(
    'a blocked silent channel does not disable the primary Messages channel',
    () async {
      channels = [
        _channelReply(mknoonMessagesChannelId, Importance.high),
        _channelReply(mknoonMessagesSilentChannelId, Importance.none),
      ];
      expect(
        await readPushPermission(
          readSettingsFn: () async => _authorizedSettings(),
        ),
        isTrue,
      );
    },
  );

  test(
    'a not-yet-created Messages channel preserves granted permission',
    () async {
      channels = [];
      expect(
        await readPushPermission(
          readSettingsFn: () async => _authorizedSettings(),
        ),
        isTrue,
      );
    },
  );

  test('iOS ignores Android channel state', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      await readPushPermission(
        readSettingsFn: () async => _authorizedSettings(),
      ),
      isTrue,
    );
    expect(calls, isEmpty);
  });

  testWidgets(
    'NOTIFY-004 resume shows the existing Settings notice and reopening the channel clears it',
    (tester) async {
      primaryImportance = Importance.high;
      final notifier = PushRegistrationHealthNotifier();
      var requests = 0;
      var registrations = 0;
      var settingsOpens = 0;
      final coordinator = PushRegistrationCoordinator(
        requestPermission: () {
          requests++;
          return requestPushPermission(
            requestPermissionFn: () async => _authorizedSettings(),
          );
        },
        readPermission: () => readPushPermission(
          readSettingsFn: () async => _authorizedSettings(),
        ),
        registerPushToken: () async {
          registrations++;
          return RegisterPushTokenResult.success;
        },
        tokenRefreshStream: const Stream.empty(),
        healthNotifier: notifier,
      );
      addTearDown(coordinator.dispose);
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PushRegistrationHealthWarning(
              healthListenable: notifier,
              onRetry: () {},
              onDismiss: () {},
              onOpenNotificationSettings: () => settingsOpens++,
            ),
          ),
        ),
      );
      await tester.runAsync(coordinator.ensureStarted);
      await tester.pumpAndSettle();
      expect(registrations, 1);
      expect(find.text('Notifications are off'), findsNothing);

      primaryImportance = Importance.none;
      await tester.runAsync(coordinator.refreshOnResume);
      await tester.pumpAndSettle();
      expect(find.text('Notifications are off'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(registrations, 1);
      expect(requests, 1);
      await tester.tap(
        find.byKey(const ValueKey('push-registration-health-action')),
      );
      expect(settingsOpens, 1);

      primaryImportance = Importance.high;
      await tester.runAsync(coordinator.refreshOnResume);
      await tester.pumpAndSettle();
      expect(find.text('Notifications are off'), findsNothing);
      expect(registrations, 2);
      expect(requests, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
