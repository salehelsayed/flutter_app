import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/request_push_permission_use_case.dart';

// ---------------------------------------------------------------------------
// Helper to build NotificationSettings with a given authorization status
// ---------------------------------------------------------------------------
NotificationSettings _makeSettings(AuthorizationStatus status) {
  return NotificationSettings(
    authorizationStatus: status,
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
}

void main() {
  setUp(() {
    flowEventLoggingEnabled = false;
  });

  group('requestPushPermission', () {
    test('returns true when authorizationStatus is authorized', () async {
      final result = await requestPushPermission(
        requestPermissionFn: () async =>
            _makeSettings(AuthorizationStatus.authorized),
      );

      expect(result, isTrue);
    });

    test('returns true when authorizationStatus is provisional', () async {
      final result = await requestPushPermission(
        requestPermissionFn: () async =>
            _makeSettings(AuthorizationStatus.provisional),
      );

      expect(result, isTrue);
    });

    test('returns false when authorizationStatus is denied', () async {
      final result = await requestPushPermission(
        requestPermissionFn: () async =>
            _makeSettings(AuthorizationStatus.denied),
      );

      expect(result, isFalse);
    });

    test('returns false when authorizationStatus is notDetermined', () async {
      final result = await requestPushPermission(
        requestPermissionFn: () async =>
            _makeSettings(AuthorizationStatus.notDetermined),
      );

      expect(result, isFalse);
    });
  });
}
