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
          contains('MKNOON_RUNNER_BUNDLE_IDENTIFIER = com.mknoon.app;'),
        );
        expect(
          pbxproj,
          contains(
            'PRODUCT_BUNDLE_IDENTIFIER = '
            '"\$(MKNOON_RUNNER_BUNDLE_IDENTIFIER)";',
          ),
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

    test(
      'project configurations import tracked Flutter build metadata',
      () async {
        final metadataConfig = await File(
          'ios/Flutter/BuildMetadata.xcconfig',
        ).readAsString();
        final pbxproj = await File(
          'ios/Runner.xcodeproj/project.pbxproj',
        ).readAsString();

        expect(metadataConfig.trim(), '#include "Generated.xcconfig"');
        expect(
          pbxproj,
          contains(
            'B17D000173A2000000000001 /* BuildMetadata.xcconfig */ = '
            '{isa = PBXFileReference; lastKnownFileType = text.xcconfig; '
            'name = BuildMetadata.xcconfig; '
            'path = Flutter/BuildMetadata.xcconfig;',
          ),
        );
        expect(
          RegExp(
            r'baseConfigurationReference = B17D000173A2000000000001 '
            r'/\* BuildMetadata\.xcconfig \*/;',
          ).allMatches(pbxproj).length,
          3,
        );
      },
    );

    test(
      'Runner and extensions derive versions from Flutter metadata',
      () async {
        final pbxproj = await File(
          'ios/Runner.xcodeproj/project.pbxproj',
        ).readAsString();

        String configurationBlock(String id) {
          final start = pbxproj.indexOf('\t\t$id /*');
          expect(start, isNonNegative, reason: 'missing configuration $id');
          final end = pbxproj.indexOf('\n\t\t};', start);
          expect(end, isNonNegative, reason: 'unterminated configuration $id');
          return pbxproj.substring(start, end);
        }

        const runnerConfigurations = <String>[
          '97C147061CF9000F007C117D',
          '97C147071CF9000F007C117D',
          '249021D4217E4FDB00AE95B9',
        ];
        const extensionConfigurations = <String>[
          '698216D52F5E3A0A00B87A6B',
          '698216D62F5E3A0A00B87A6B',
          '698216D72F5E3A0A00B87A6B',
          '6F73B01373A0000000000001',
          '6F73B01473A0000000000001',
          '6F73B01573A0000000000001',
        ];

        for (final id in runnerConfigurations) {
          expect(
            configurationBlock(id),
            contains(r'CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";'),
            reason: id,
          );
        }
        for (final id in extensionConfigurations) {
          final block = configurationBlock(id);
          expect(
            block,
            contains(r'CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";'),
            reason: id,
          );
          expect(
            block,
            contains(r'MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)";'),
            reason: id,
          );
        }

        expect(pbxproj, isNot(contains('CURRENT_PROJECT_VERSION = 105;')));
        expect(pbxproj, isNot(contains('CURRENT_PROJECT_VERSION = 107;')));
      },
    );

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

    test(
      'foreground push fallback is migration-gated before display',
      () async {
        final mainDart = await File('lib/main.dart').readAsString();

        final handlerIndex = mainDart.indexOf('_handleForegroundRemotePush');
        final gateIndex = mainDart.indexOf(
          'push_foreground_notification_display',
          handlerIndex,
        );
        final fallbackIndex = mainDart.indexOf(
          'showForegroundPushFallbackNotificationIfNeeded',
          handlerIndex,
        );

        expect(handlerIndex, isNonNegative);
        expect(gateIndex, isNonNegative);
        expect(fallbackIndex, isNonNegative);
        expect(gateIndex, lessThan(fallbackIndex));
      },
    );
  });
}
