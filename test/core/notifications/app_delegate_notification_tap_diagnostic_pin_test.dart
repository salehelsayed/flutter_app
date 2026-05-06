// Pin: AppDelegate.swift keeps iOS notification tap delivery owned by
// FlutterAppDelegate. The explicit delegate install points and didReceive
// override are a defensive native handoff plus hardware-trace aid; physical
// iPhone tap evidence remains the runtime regression catcher.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const diagnosticReason =
      'The iOS AppDelegate tap override and delegate install points are a '
      'defensive native handoff plus hardware-trace aid; iPhone tap evidence '
      'remains required for closure.';

  test('AppDelegate pins iOS notification tap diagnostic forwarding', () {
    final file = File('ios/Runner/AppDelegate.swift');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'AppDelegate.swift is the native iOS tap diagnostic target.',
    );

    final source = file.readAsStringSync();

    expect(
      RegExp(
        r'@objc\s+class\s+AppDelegate\s*:\s*FlutterAppDelegate',
      ).hasMatch(source),
      isTrue,
      reason:
          'AppDelegate must continue subclassing FlutterAppDelegate so the '
          'native tap diagnostic can forward to the Flutter/plugin delegate '
          'pipeline. $diagnosticReason',
    );

    expect(
      source.contains('center.delegate = self'),
      isTrue,
      reason:
          'AppDelegate must remain the UNUserNotificationCenter delegate so '
          'hardware logs classify whether OS taps reach this object. '
          '$diagnosticReason',
    );
    expect(
      source.contains('installNotificationCenterDelegate('),
      isTrue,
      reason:
          'Delegate ownership must be centralized so AppDelegate can re-seat '
          'it after Flutter/Firebase plugin registration. $diagnosticReason',
    );
    expect(
      source.contains(
        'installNotificationCenterDelegate(context: "before_didFinishLaunching_super")',
      ),
      isTrue,
      reason:
          'AppDelegate should own the notification center delegate before '
          'FlutterAppDelegate launch registration. $diagnosticReason',
    );
    expect(
      source.contains(
        'installNotificationCenterDelegate(context: "after_didFinishLaunching_super")',
      ),
      isTrue,
      reason:
          'AppDelegate must re-seat the notification center delegate after '
          'super launch in case plugin setup changed ownership. '
          '$diagnosticReason',
    );
    expect(
      source.contains(
        'installNotificationCenterDelegate(context: "after_implicit_engine_plugin_registration")',
      ),
      isTrue,
      reason:
          'AppDelegate must re-seat the notification center delegate after '
          'implicit engine plugin registration, where Firebase Messaging and '
          'local notification plugins join the lifecycle pipeline. '
          '$diagnosticReason',
    );

    expect(
      RegExp(
        r'override\s+func\s+userNotificationCenter\s*\(\s*_\s+center\s*:\s*UNUserNotificationCenter\s*,\s*didReceive\s+response\s*:\s*UNNotificationResponse\s*,\s*withCompletionHandler\s+completionHandler\s*:\s*@escaping\s*\(\s*\)\s*->\s*Void\s*\)',
        multiLine: true,
      ).hasMatch(source),
      isTrue,
      reason:
          'AppDelegate must expose an explicit didReceive diagnostic hook for '
          'hardware tap tracing. $diagnosticReason',
    );

    expect(
      source.contains('ios_native_un_didReceive'),
      isTrue,
      reason:
          'The native tap log must have a stable marker for hardware and '
          'simulator trace collection. $diagnosticReason',
    );
    expect(source.contains('response.actionIdentifier'), isTrue);
    expect(source.contains('delegateClass'), isTrue);
    expect(source.contains('notification_center_delegate_installed'), isTrue);
    expect(source.contains('previousDelegateClass'), isTrue);
    expect(source.contains('currentDelegateClass'), isTrue);
    expect(source.contains('NotificationId'), isTrue);
    expect(source.contains('payload'), isTrue);
    expect(source.contains('gcm.message_id'), isTrue);
    expect(source.contains('neither'), isTrue);
    expect(
      source.contains('mknoon/ios_notification_open'),
      isTrue,
      reason:
          'APNs-direct taps that are neither Firebase-shaped nor local-FLN '
          'shaped need a dedicated native-to-Dart bridge. '
          '$diagnosticReason',
    );
    expect(
      source.contains('notificationOpened'),
      isTrue,
      reason:
          'Warm APNs-direct taps must be delivered to Dart through the bridge. '
          '$diagnosticReason',
    );
    expect(
      source.contains('consumeInitialNotificationOpen'),
      isTrue,
      reason:
          'Cold-start APNs-direct taps must be consumed once after Dart '
          'registers its route handler. $diagnosticReason',
    );
    expect(
      source.contains('markNotificationOpenBridgeReady'),
      isTrue,
      reason:
          'Dart must be able to mark the bridge ready independently from the '
          'one-shot initial consume call. $diagnosticReason',
    );
    expect(
      source.contains('ios_notification_open_bridge_ready'),
      isTrue,
      reason:
          'Native logs must prove Dart readiness reached AppDelegate. '
          '$diagnosticReason',
    );
    expect(
      source.contains('pendingIosNotificationOpen'),
      isTrue,
      reason:
          'AppDelegate must store APNs-direct tap payloads while Flutter/Dart '
          'is not ready to receive the bridge callback. $diagnosticReason',
    );
    expect(
      RegExp(r'pendingIosNotificationOpen\s*=\s*payload').hasMatch(source),
      isTrue,
      reason:
          'The pending APNs-open map must be the JSON-compatible route payload '
          'copied from userInfo. $diagnosticReason',
    );
    expect(
      source.contains('ios_notification_open_forwarded_warm'),
      isTrue,
      reason:
          'Native logs must prove a warm APNs/remote tap was forwarded to '
          'Dart. $diagnosticReason',
    );
    expect(
      source.contains('ios_notification_open_stored_pending'),
      isTrue,
      reason:
          'Native logs must prove route-shaped taps are retained when Dart is '
          'not ready. $diagnosticReason',
    );
    expect(
      source.contains('ios_notification_open_initial_consumed'),
      isTrue,
      reason:
          'Cold-start APNs-direct taps must be consumed through the initial '
          'open path after the Dart bridge is ready. $diagnosticReason',
    );
    expect(
      source.contains('ios_notification_open_pending_flushed'),
      isFalse,
      reason:
          'Pending cold-start APNs-direct taps must not be reclassified as '
          'warm notificationOpened callbacks during bridge-ready marking. '
          '$diagnosticReason',
    );
    expect(
      source.contains('isFlnNotificationOpenPayload'),
      isTrue,
      reason:
          'The APNs bridge must skip local notification taps so FLN continues '
          'to own that route. $diagnosticReason',
    );
    expect(
      source.contains('isFcmNotificationOpenPayload'),
      isFalse,
      reason:
          'Route-shaped FCM payloads must no longer be skipped natively; Dart '
          'dedupes native/Firebase duplicate opens by message id. '
          '$diagnosticReason',
    );

    expect(
      RegExp(
        r'super\.userNotificationCenter\s*\(\s*center\s*,\s*didReceive:\s*response\s*,\s*withCompletionHandler:\s*completionHandler\s*\)',
        multiLine: true,
      ).hasMatch(source),
      isTrue,
      reason:
          'The diagnostic hook must forward to FlutterAppDelegate so existing '
          'plugin tap routing still runs. $diagnosticReason',
    );

    expect(
      RegExp(r'completionHandler\s*\(\s*\)').hasMatch(source),
      isFalse,
      reason:
          'AppDelegate must not complete the tap directly; super/plugin '
          'forwarding owns the completion handler. $diagnosticReason',
    );
    expect(
      RegExp(r'completionHandler\.call\s*\(').hasMatch(source),
      isFalse,
      reason:
          'AppDelegate must not complete the tap directly; super/plugin '
          'forwarding owns the completion handler. $diagnosticReason',
    );
  });

  test('iOS notification tap UI smoke assets are pinned', () {
    final uiTestFile = File('ios/RunnerUITests/NotificationTapUITests.swift');
    expect(
      uiTestFile.existsSync(),
      isTrue,
      reason:
          'The simulator smoke must keep a real XCTest UI target for tapping '
          'Springboard notifications.',
    );
    final uiTestSource = uiTestFile.readAsStringSync();
    expect(uiTestSource.contains('com.apple.springboard'), isTrue);
    expect(uiTestSource.contains('MKNOON_APNS_TAP_READY'), isTrue);
    expect(uiTestSource.contains('com.mknoon.app'), isTrue);
    expect(uiTestSource.contains('New Message'), isTrue);
    expect(uiTestSource.contains('XCUIDevice.shared.press(.home)'), isTrue);
    expect(uiTestSource.contains('testColdNotificationTap'), isTrue);

    final projectFile = File('ios/Runner.xcodeproj/project.pbxproj');
    final projectSource = projectFile.readAsStringSync();
    expect(projectSource.contains('RunnerUITests'), isTrue);
    expect(projectSource.contains('NotificationTapUITests.swift'), isTrue);
    expect(
      projectSource.contains('com.apple.product-type.bundle.ui-testing'),
      isTrue,
    );

    final schemeFile = File(
      'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
    );
    final schemeSource = schemeFile.readAsStringSync();
    expect(schemeSource.contains('RunnerUITests.xctest'), isTrue);

    final smokeScript = File('scripts/run_ios_notification_tap_ui_smoke.sh');
    expect(
      smokeScript.existsSync(),
      isTrue,
      reason:
          'The APNs tap runtime regression must stay runnable as a simulator '
          'smoke script.',
    );
    final smokeSource = smokeScript.readAsStringSync();
    expect(smokeSource.contains('xcodebuild test'), isTrue);
    expect(
      smokeSource.contains(
        '-only-testing:RunnerUITests/NotificationTapUITests/testNotificationTap',
      ),
      isTrue,
    );
    expect(
      smokeSource.contains(
        'RunnerUITests/NotificationTapUITests/testColdNotificationTap',
      ),
      isTrue,
    );
    expect(smokeSource.contains('push_fixture_to_simulator.sh'), isTrue);
    expect(smokeSource.contains('simctl push'), isTrue);
    expect(smokeSource.contains('log stream'), isTrue);

    final pushHelper = File(
      'scripts/push_fixture_to_simulator.sh',
    ).readAsStringSync();
    expect(pushHelper.contains('xcrun simctl push'), isTrue);

    for (final marker in const [
      'ios_native_un_didReceive',
      'ios_notification_open_forwarded_warm',
      'ios_notification_open_stored_pending',
      'IOS_APNS_NOTIFICATION_OPENED',
      'IOS_APNS_INITIAL_NOTIFICATION_OPENED',
      'IOS_APNS_NOTIFICATION_OPEN_ERROR',
      'NOTIFICATION_TAP_NAV_ERROR',
      'INITIAL_LOCAL_NOTIFICATION_ROUTE_ERROR',
    ]) {
      expect(
        smokeSource.contains(marker),
        isTrue,
        reason: 'The smoke script must assert marker: $marker',
      );
    }
  });
}
