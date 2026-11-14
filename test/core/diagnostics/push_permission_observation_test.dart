import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/request_push_permission_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationSettings _settings(AuthorizationStatus status) =>
    NotificationSettings(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDiagnostics diagnostics;
  late bool priorFlow;
  setUp(() async {
    priorFlow = flowEventLoggingEnabled;
    flowEventLoggingEnabled = false;
    directory = await Directory.systemTemp.createTemp(
      'permission-observation-',
    );
    diagnostics = await AppDiagnostics.installForTesting(directory: directory);
  });
  tearDown(() async {
    flowEventLoggingEnabled = priorFlow;
    await diagnostics.dispose();
    await directory.delete(recursive: true);
  });
  Future<List<Map<String, dynamic>>> records() async {
    final preview = await diagnostics.exportPreview();
    expect(preview, isNot(contains('PRIVATE_PERMISSION')));
    final events = ((jsonDecode(preview) as Map)['events'] as List)
        .cast<Map<String, dynamic>>()
        .where((e) => e['feature'] == 'push')
        .toList();
    for (final event in events) {
      expect(event['values'], isEmpty);
      expect(event.containsKey('traceId'), isFalse);
      expect(event.containsKey('attemptId'), isFalse);
    }
    return events;
  }

  Future<void> expectSequence(List<(String, String, String)> expected) async {
    final events = await records();
    expect(
      events.map((e) => (e['stage'], e['outcome'], e['reason'])),
      expected,
    );
  }

  test(
    'started precedes the existing request and no completion is invented while waiting',
    () async {
      final gate = Completer<NotificationSettings>();
      var requestCalls = 0;
      var osCalls = 0;
      final pending = requestPushPermission(
        requestPermissionFn: () {
          requestCalls++;
          return gate.future;
        },
        osNotificationsEnabledFn: () async {
          osCalls++;
          return true;
        },
      );
      expect(requestCalls, 1);
      expect(osCalls, 0);
      final before = await records();
      // Settle the original operation even on RED so no fixture-owned work leaks.
      gate.complete(_settings(AuthorizationStatus.authorized));
      expect(await pending, isTrue);
      expect(before.map((e) => (e['stage'], e['outcome'], e['reason'])), [
        ('preflight', 'started', 'none'),
      ]);
      expect(osCalls, 1);
      await expectSequence([
        ('preflight', 'started', 'none'),
        ('preflight', 'ok', 'none'),
      ]);
    },
  );
  for (final status in AuthorizationStatus.values) {
    test(
      '$status observes the existing posting result with no extra OS read',
      () async {
        var requests = 0;
        var reads = 0;
        final granted =
            status == AuthorizationStatus.authorized ||
            status == AuthorizationStatus.provisional;
        expect(
          await requestPushPermission(
            requestPermissionFn: () async {
              requests++;
              return _settings(status);
            },
            osNotificationsEnabledFn: () async {
              reads++;
              return true;
            },
          ),
          granted,
        );
        expect(requests, 1);
        expect(reads, granted ? 1 : 0);
        await expectSequence([
          ('preflight', 'started', 'none'),
          (
            'preflight',
            granted ? 'ok' : 'rejected',
            granted ? 'none' : 'permission_denied',
          ),
        ]);
      },
    );
  }
  test(
    'OS posting refusal narrows authorized result without changing policy',
    () async {
      var reads = 0;
      expect(
        await requestPushPermission(
          requestPermissionFn: () async =>
              _settings(AuthorizationStatus.authorized),
          osNotificationsEnabledFn: () async {
            reads++;
            return false;
          },
        ),
        isFalse,
      );
      expect(reads, 1);
      await expectSequence([
        ('preflight', 'started', 'none'),
        ('preflight', 'rejected', 'permission_denied'),
      ]);
    },
  );
  test(
    'escaping requester error is observed then rethrown unchanged',
    () async {
      final error = StateError('PRIVATE_PERMISSION_REQUEST_ERROR');
      var osReads = 0;
      await expectLater(
        requestPushPermission(
          requestPermissionFn: () async {
            throw error;
          },
          osNotificationsEnabledFn: () async {
            osReads++;
            return true;
          },
        ),
        throwsA(same(error)),
      );
      expect(osReads, 0);
      await expectSequence([
        ('preflight', 'started', 'none'),
        ('preflight', 'failed', 'unknown'),
      ]);
    },
  );
  test(
    'caught OS error has its own observation while existing policy stays fail-open',
    () async {
      var reads = 0;
      expect(
        await requestPushPermission(
          requestPermissionFn: () async =>
              _settings(AuthorizationStatus.authorized),
          osNotificationsEnabledFn: () async {
            reads++;
            throw StateError('PRIVATE_PERMISSION_OS_ERROR');
          },
        ),
        isTrue,
      );
      expect(reads, 1);
      await expectSequence([
        ('preflight', 'started', 'none'),
        ('verify', 'failed', 'unknown'),
        ('preflight', 'ok', 'none'),
      ]);
    },
  );
  test(
    'read-only OS failure also remains fail-open and never claims a request',
    () async {
      var reads = 0;
      expect(
        await readPushPermission(
          readSettingsFn: () async => _settings(AuthorizationStatus.authorized),
          osNotificationsEnabledFn: () async {
            reads++;
            throw StateError('PRIVATE_PERMISSION_OS_ERROR');
          },
        ),
        isTrue,
      );
      expect(reads, 1);
      await expectSequence([('verify', 'failed', 'unknown')]);
    },
  );
  for (final unavailable in [false, true]) {
    test(
      '${unavailable ? 'unavailable' : 'opted-out'} observation cannot change permission or escaping errors',
      () async {
        if (unavailable) {
          var writes = 0;
          diagnostics = await AppDiagnostics.installForTesting(
            directory: directory,
            persist: (_, _) async {
              writes++;
              throw StateError('PRIVATE_PERMISSION_OBSERVER');
            },
          );
          expect(writes, greaterThan(0));
          expect(
            diagnostics.record(
              feature: 'runtime',
              stage: 'snapshot',
              outcome: 'ok',
            ),
            isFalse,
          );
        } else {
          await diagnostics.setEnabled(false);
        }
        var calls = 0;
        expect(
          await requestPushPermission(
            requestPermissionFn: () async {
              calls++;
              return _settings(AuthorizationStatus.authorized);
            },
            osNotificationsEnabledFn: () async => false,
          ),
          isFalse,
        );
        final error = StateError('PRIVATE_PERMISSION_REQUEST_ERROR');
        await expectLater(
          requestPushPermission(
            requestPermissionFn: () async {
              calls++;
              throw error;
            },
          ),
          throwsA(same(error)),
        );
        expect(calls, 2);
        expect(await records(), isEmpty);
      },
    );
  }
}
