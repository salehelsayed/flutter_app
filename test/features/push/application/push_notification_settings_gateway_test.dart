import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/features/push/application/push_notification_settings_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mknoon/push_notification_settings');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'Android opens the app notification settings platform destination',
    () async {
      MethodCall? observedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            observedCall = call;
            return true;
          });
      const gateway = PlatformPushNotificationSettingsGateway(isAndroid: true);

      expect(await gateway.openNotificationSettings(), isTrue);
      expect(observedCall?.method, 'openAppNotificationSettings');
      expect(observedCall?.arguments, isNull);
    },
  );

  test('non-Android behavior is a safe no-op', () async {
    var launchCalls = 0;
    final gateway = PlatformPushNotificationSettingsGateway(
      isAndroid: false,
      openAndroidNotificationSettings: () async {
        launchCalls++;
        return true;
      },
    );

    expect(await gateway.openNotificationSettings(), isFalse);
    expect(launchCalls, 0);
  });

  test('Android platform failures fail closed', () async {
    final gateway = PlatformPushNotificationSettingsGateway(
      isAndroid: true,
      openAndroidNotificationSettings: () async {
        throw PlatformException(code: 'settings_unavailable');
      },
    );

    expect(await gateway.openNotificationSettings(), isFalse);
  });

  test('production MainActivity binds the exact settings channel', () {
    final source = File(
      'android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('PushNotificationSettingsLauncher.METHOD_CHANNEL'));
    expect(source, contains('PushNotificationSettingsLauncher.OPEN_METHOD'));
    expect(
      source,
      contains('PushNotificationSettingsLauncher.open(applicationContext)'),
    );
  });
}
