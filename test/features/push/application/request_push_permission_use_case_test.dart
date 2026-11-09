import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/push_registration_coordinator.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final capturedEvents = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> eventsNamed(String event) => capturedEvents
      .where((payload) => payload['event'] == event)
      .toList(growable: false);

  Map<String, dynamic> detailsOf(Map<String, dynamic> payload) =>
      (payload['details'] as Map).cast<String, dynamic>();

  setUp(() {
    // The default OS reader now uses the plugin's platform resolution. Exercise
    // its Android channel instead of relying on the host dart:io no-op.
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => switch (call.method) {
            'areNotificationsEnabled' => true,
            'getNotificationChannels' => <Map<String, Object?>>[],
            _ => throw StateError(
              'Unexpected notification call: ${call.method}',
            ),
          },
        );
    flowEventLoggingEnabled = false;
    capturedEvents.clear();
    // The sink fires regardless of `flowEventLoggingEnabled`.
    debugSetFlowEventSink(capturedEvents.add);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugSetFlowEventSink(null);
  });

  group('requestPushPermission', () {
    // TC-385-05: granted-path preservation through the DEFAULT OS check, with
    // no spurious default-path emissions.
    test('returns true when authorizationStatus is authorized', () async {
      final result = await requestPushPermission(
        requestPermissionFn: () async =>
            _makeSettings(AuthorizationStatus.authorized),
      );

      expect(result, isTrue);
      // The DEFAULT check must actually have run and answered: the RESULT
      // payload carries the raw reading only when it did. Without this, an
      // implementation that runs the verify solely when a fake is injected
      // (production always passes null) leaves every host row green while the
      // fix is inert on device.
      expect(
        detailsOf(
          eventsNamed('PUSH_PERMISSION_REQUEST_RESULT').single,
        )['osEnabled'],
        isTrue,
      );
      expect(eventsNamed('PUSH_PERMISSION_OS_CHECK_FAILED'), isEmpty);
      expect(eventsNamed('PUSH_PERMISSION_OS_STATE_OVERRIDE'), isEmpty);
    });

    // TC-385-06: provisional still counts as granted (iOS semantics).
    test('returns true when authorizationStatus is provisional', () async {
      final result = await requestPushPermission(
        requestPermissionFn: () async =>
            _makeSettings(AuthorizationStatus.provisional),
      );

      expect(result, isTrue);
      expect(
        detailsOf(
          eventsNamed('PUSH_PERMISSION_REQUEST_RESULT').single,
        )['osEnabled'],
        isTrue,
      );
      expect(eventsNamed('PUSH_PERMISSION_OS_CHECK_FAILED'), isEmpty);
      expect(eventsNamed('PUSH_PERMISSION_OS_STATE_OVERRIDE'), isEmpty);
    });

    // TC-385-07: request-denied honesty preserved; the override can only
    // narrow, never widen.
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

    // TC-385-01: the bug. firebase_messaging reports `authorized` off
    // checkSelfPermission while the NotificationManager really has posting
    // disabled; the effective verdict must follow the OS, not the request.
    test(
      'returns false when the request result is authorized but the OS reports '
      'notifications disabled',
      () async {
        final result = await requestPushPermission(
          requestPermissionFn: () async =>
              _makeSettings(AuthorizationStatus.authorized),
          osNotificationsEnabledFn: () async => false,
        );

        expect(result, isFalse);
      },
    );

    // TC-385-02: the override is observable and the RESULT payload is honest
    // in ONE map (status/granted/osEnabled asserted on the same event), with
    // no spurious CHECK_FAILED poisoning the device-tier diagnostic.
    test(
      'emits PUSH_PERMISSION_OS_STATE_OVERRIDE and an honest RESULT when the '
      'OS overrides an authorized request',
      () async {
        await requestPushPermission(
          requestPermissionFn: () async =>
              _makeSettings(AuthorizationStatus.authorized),
          osNotificationsEnabledFn: () async => false,
        );

        final overrides = eventsNamed('PUSH_PERMISSION_OS_STATE_OVERRIDE');
        expect(overrides, hasLength(1));
        final overrideDetails = detailsOf(overrides.single);
        expect(overrideDetails['requestStatus'], 'authorized');
        expect(overrideDetails['osEnabled'], isFalse);

        final results = eventsNamed('PUSH_PERMISSION_REQUEST_RESULT');
        expect(results, hasLength(1));
        final resultDetails = detailsOf(results.single);
        expect(resultDetails['status'], 'authorized');
        expect(resultDetails['granted'], isFalse);
        expect(resultDetails['osEnabled'], isFalse);

        expect(eventsNamed('PUSH_PERMISSION_OS_CHECK_FAILED'), isEmpty);
      },
    );

    // TC-385-03: denied-by-request is discriminated from denied-by-override —
    // the OS check is never consulted when the request itself said no.
    test('does not invoke the OS check or emit the override when the request '
        'itself is denied', () async {
      var osCheckCalls = 0;

      final result = await requestPushPermission(
        requestPermissionFn: () async =>
            _makeSettings(AuthorizationStatus.denied),
        osNotificationsEnabledFn: () async {
          osCheckCalls += 1;
          return true;
        },
      );

      expect(result, isFalse);
      expect(osCheckCalls, 0);
      expect(eventsNamed('PUSH_PERMISSION_OS_STATE_OVERRIDE'), isEmpty);
    });

    // TC-385-04: the OS check fails OPEN behind a BROAD catch. StateError is
    // an Error, not an Exception: `on Exception` would let it escape into the
    // coordinator's 15s exception-retry loop and re-prompt every cycle.
    test(
      'keeps a granted result and emits PUSH_PERMISSION_OS_CHECK_FAILED when '
      'the OS check throws',
      () async {
        final result = await requestPushPermission(
          requestPermissionFn: () async =>
              _makeSettings(AuthorizationStatus.authorized),
          osNotificationsEnabledFn: () async {
            throw StateError('os check broke');
          },
        );

        expect(result, isTrue);
        expect(eventsNamed('PUSH_PERMISSION_OS_CHECK_FAILED'), hasLength(1));
        expect(eventsNamed('PUSH_PERMISSION_OS_STATE_OVERRIDE'), isEmpty);
      },
    );
  });

  group('readPushPermission', () {
    test('reads granted settings and confirms them with the OS', () async {
      var osChecks = 0;
      final result = await readPushPermission(
        readSettingsFn: () async =>
            _makeSettings(AuthorizationStatus.authorized),
        osNotificationsEnabledFn: () async {
          osChecks++;
          return true;
        },
      );
      expect(result, isTrue);
      expect(osChecks, 1);
      expect(detailsOf(eventsNamed('PUSH_PERMISSION_READ_RESULT').single), {
        'status': 'authorized',
        'granted': true,
        'osEnabled': true,
      });
      expect(eventsNamed('PUSH_PERMISSION_REQUEST_BEGIN'), isEmpty);
    });

    test(
      'narrows a granted reading when the OS has notifications off',
      () async {
        final result = await readPushPermission(
          readSettingsFn: () async =>
              _makeSettings(AuthorizationStatus.authorized),
          osNotificationsEnabledFn: () async => false,
        );
        expect(result, isFalse);
      },
    );

    test('returns a denied reading without consulting the OS', () async {
      var osChecks = 0;
      final result = await readPushPermission(
        readSettingsFn: () async => _makeSettings(AuthorizationStatus.denied),
        osNotificationsEnabledFn: () async {
          osChecks++;
          return true;
        },
      );
      expect(result, isFalse);
      expect(osChecks, 0);
      expect(detailsOf(eventsNamed('PUSH_PERMISSION_READ_RESULT').single), {
        'status': 'denied',
        'granted': false,
      });
    });
  });

  group('default platform permission request', () {
    const messagingChannel = MethodChannel(
      'plugins.flutter.io/firebase_messaging',
    );
    late Future<Map<String, int>> Function() firebaseRequest;
    late Future<bool> Function() androidRequest;
    late List<String> calls;
    var authorizationStatus = 0;

    setUpAll(() async {
      setupFirebaseCoreMocks();
      await Firebase.initializeApp();
    });

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls = <String>[];
      authorizationStatus = 0;
      firebaseRequest = () async => <String, int>{
        'authorizationStatus': authorizationStatus,
      };
      androidRequest = () async => false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(messagingChannel, (call) async {
            calls.add('firebase:${call.method}');
            return switch (call.method) {
              'Messaging#requestPermission' => await firebaseRequest(),
              'Messaging#getNotificationSettings' => <String, int>{
                'authorizationStatus': authorizationStatus,
              },
              _ => throw StateError('Unexpected Firebase call: ${call.method}'),
            };
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add('android:${call.method}');
            return switch (call.method) {
              'requestNotificationsPermission' => await androidRequest(),
              'areNotificationsEnabled' => true,
              'getNotificationChannels' => <Map<String, Object?>>[],
              _ => throw StateError(
                'Unexpected notification call: ${call.method}',
              ),
            };
          });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(messagingChannel, null);
    });

    tearDownAll(() {
      TestFirebaseCoreHostApi.setUp(null);
    });

    test('Android startup reports denied without resume when the Firebase '
        'permission callback is lost', () {
      fakeAsync((async) {
        final lostFirebaseReply = Completer<Map<String, int>>();
        firebaseRequest = () => lostFirebaseReply.future;
        var started = false;
        var registrations = 0;
        final coordinator = PushRegistrationCoordinator(
          requestPermission: requestPushPermission,
          registerPushToken: () async {
            registrations++;
            return RegisterPushTokenResult.success;
          },
          tokenRefreshStream: const Stream<String>.empty(),
        );
        coordinator.ensureStarted().then((_) => started = true);
        async.flushMicrotasks();

        try {
          expect(started, isTrue);
          expect(registrations, 0);
          expect(
            detailsOf(
              eventsNamed('PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED').single,
            ),
            <String, Object>{'trigger': 'startup'},
          );
          expect(
            detailsOf(eventsNamed('PUSH_PERMISSION_REQUEST_RESULT').single),
            <String, Object>{'status': 'denied', 'granted': false},
          );
          expect(calls, <String>[
            'android:requestNotificationsPermission',
            'firebase:Messaging#getNotificationSettings',
          ]);
          expect(async.pendingTimers, isEmpty);
        } finally {
          coordinator.dispose();
          lostFirebaseReply.complete(<String, int>{'authorizationStatus': 0});
          async.flushMicrotasks();
        }
      });
    });

    test('Android keeps one slow permission prompt pending until grant', () {
      fakeAsync((async) {
        final nativeReply = Completer<bool>();
        final lostFirebaseReply = Completer<Map<String, int>>();
        androidRequest = () => nativeReply.future;
        firebaseRequest = () => lostFirebaseReply.future;
        var completions = 0;
        var registrations = 0;
        final coordinator = PushRegistrationCoordinator(
          requestPermission: requestPushPermission,
          registerPushToken: () async {
            registrations++;
            return RegisterPushTokenResult.success;
          },
          tokenRefreshStream: const Stream<String>.empty(),
        );
        coordinator.ensureStarted().then((_) => completions++);
        async.flushMicrotasks();
        coordinator.ensureStarted().then((_) => completions++);
        async.flushMicrotasks();

        try {
          async.elapse(const Duration(minutes: 3));
          async.flushMicrotasks();
          expect(completions, 0);
          expect(registrations, 0);
          expect(eventsNamed('PUSH_PERMISSION_REQUEST_RESULT'), isEmpty);
          expect(
            eventsNamed('PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED'),
            isEmpty,
          );
          expect(calls, <String>['android:requestNotificationsPermission']);

          authorizationStatus = 1;
          nativeReply.complete(true);
          async.flushMicrotasks();

          expect(completions, 2);
          expect(registrations, 1);
          expect(
            detailsOf(eventsNamed('PUSH_PERMISSION_REQUEST_RESULT').single),
            <String, Object>{
              'status': 'authorized',
              'granted': true,
              'osEnabled': true,
            },
          );
          expect(
            calls.where(
              (call) => call.endsWith('requestNotificationsPermission'),
            ),
            hasLength(1),
          );
          expect(
            calls,
            isNot(contains('firebase:Messaging#requestPermission')),
          );
          expect(async.pendingTimers, isEmpty);
        } finally {
          coordinator.dispose();
          if (!nativeReply.isCompleted) nativeReply.complete(false);
          lostFirebaseReply.complete(<String, int>{'authorizationStatus': 0});
          async.flushMicrotasks();
        }
      });
    });

    test('iOS retains the Firebase permission requester', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      authorizationStatus = 1;

      expect(await requestPushPermission(), isTrue);
      expect(calls, <String>['firebase:Messaging#requestPermission']);
      expect(
        detailsOf(eventsNamed('PUSH_PERMISSION_REQUEST_RESULT').single),
        <String, Object>{
          'status': 'authorized',
          'granted': true,
          'osEnabled': true,
        },
      );
    });
  });
}
