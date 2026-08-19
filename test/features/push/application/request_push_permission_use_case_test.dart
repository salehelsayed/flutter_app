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
  final capturedEvents = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> eventsNamed(String event) => capturedEvents
      .where((payload) => payload['event'] == event)
      .toList(growable: false);

  Map<String, dynamic> detailsOf(Map<String, dynamic> payload) =>
      (payload['details'] as Map).cast<String, dynamic>();

  setUp(() {
    flowEventLoggingEnabled = false;
    capturedEvents.clear();
    // The sink fires regardless of `flowEventLoggingEnabled`.
    debugSetFlowEventSink(capturedEvents.add);
  });

  tearDown(() => debugSetFlowEventSink(null));

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
}
