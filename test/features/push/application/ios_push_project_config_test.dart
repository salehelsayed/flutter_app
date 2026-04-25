import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS push project config', () {
    test(
      'GoogleService-Info.plist keeps the expected Firebase project and bundle id',
      () async {
        final googleServiceInfo = await File(
          'ios/Runner/GoogleService-Info.plist',
        ).readAsString();
        final pbxproj = await File(
          'ios/Runner.xcodeproj/project.pbxproj',
        ).readAsString();

        expect(googleServiceInfo, contains('<key>PROJECT_ID</key>'));
        expect(googleServiceInfo, contains('<string>mknoon-c6e62</string>'));
        expect(googleServiceInfo, contains('<key>BUNDLE_ID</key>'));
        expect(googleServiceInfo, contains('<string>com.mknoon.app</string>'));
        expect(
          pbxproj,
          contains('PRODUCT_BUNDLE_IDENTIFIER = com.mknoon.app;'),
        );
      },
    );

    test(
      'Info.plist includes fetch and remote-notification background modes',
      () async {
        final infoPlist = await File('ios/Runner/Info.plist').readAsString();

        expect(infoPlist, contains('<string>fetch</string>'));
        expect(infoPlist, contains('<string>remote-notification</string>'));
      },
    );

    test('Runner.entitlements keeps production aps-environment', () async {
      final entitlements = await File(
        'ios/Runner/Runner.entitlements',
      ).readAsString();

      expect(entitlements, contains('<key>aps-environment</key>'));
      expect(entitlements, contains('<string>production</string>'));
    });

    test('AppDelegate forwards APNS token to Firebase Messaging', () async {
      final appDelegate = await File(
        'ios/Runner/AppDelegate.swift',
      ).readAsString();

      expect(appDelegate, contains('import FirebaseMessaging'));
      expect(appDelegate, contains('[PUSH_DIAG] didFinishLaunching'));
      expect(appDelegate, contains('didBecomeActiveNotification'));
      expect(
        appDelegate,
        contains('native_registerForRemoteNotifications_begin'),
      );
      expect(appDelegate, contains('native_notification_settings'));
      expect(
        appDelegate,
        contains('didRegisterForRemoteNotificationsWithDeviceToken'),
      );
      expect(
        appDelegate,
        contains('Messaging.messaging().apnsToken = deviceToken'),
      );
      expect(
        appDelegate,
        contains(
          '[PUSH_DIAG] didRegisterForRemoteNotificationsWithDeviceToken',
        ),
      );
      expect(
        appDelegate,
        contains('didFailToRegisterForRemoteNotificationsWithError'),
      );
    });

    test('main.dart keeps foreground remote presentation quiet', () async {
      final mainDart = await File('lib/main.dart').readAsString();

      expect(
        mainDart,
        matches(
          RegExp(
            r'setForegroundNotificationPresentationOptions\(\s*'
            r'alert:\s*false,\s*'
            r'badge:\s*false,\s*'
            r'sound:\s*false,',
            multiLine: true,
          ),
        ),
      );
    });
  });
}
