import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/features/push/application/push_notification_settings_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mknoon/push_notification_settings');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, null);
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
      isIOS: false,
      openAndroidNotificationSettings: () async {
        launchCalls++;
        return true;
      },
    );

    expect(await gateway.openNotificationSettings(), isFalse);
    expect(launchCalls, 0);
  });

  test(
    'iOS opens app settings through the existing permission plugin',
    () async {
      final calls = <MethodCall>[];
      var androidCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissions, (call) async {
            calls.add(call);
            return true;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            androidCalls++;
            return true;
          });
      const gateway = PlatformPushNotificationSettingsGateway(
        isAndroid: false,
        isIOS: true,
      );
      expect(await gateway.openNotificationSettings(), isTrue);
      expect(calls.single.method, 'openAppSettings');
      expect(calls.single.arguments, isNull);
      expect(androidCalls, 0);
    },
  );

  for (final throws in [false, true]) {
    test('iOS settings failure returns false, throws=$throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissions, (_) async {
            if (throws) throw PlatformException(code: 'unavailable');
            return false;
          });
      const gateway = PlatformPushNotificationSettingsGateway(
        isAndroid: false,
        isIOS: true,
      );
      expect(await gateway.openNotificationSettings(), isFalse);
    });
  }

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
