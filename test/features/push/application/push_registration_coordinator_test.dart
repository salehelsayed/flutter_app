import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/push_registration_coordinator.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart';

void main() {
  setUp(() {
    flowEventLoggingEnabled = false;
  });

  group('PushRegistrationCoordinator', () {
    test('permission denied stops the flow with no retries', () {
      fakeAsync((async) {
        final refreshController = StreamController<String>.broadcast(
          sync: true,
        );
        var permissionCalls = 0;
        var registerCalls = 0;

        final coordinator = PushRegistrationCoordinator(
          requestPermission: () async {
            permissionCalls++;
            return false;
          },
          registerPushToken: () async {
            registerCalls++;
            return RegisterPushTokenResult.noToken;
          },
          tokenRefreshStream: refreshController.stream,
          retryDelay: const Duration(seconds: 30),
        );

        coordinator.ensureStarted();
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();

        expect(permissionCalls, equals(1));
        expect(registerCalls, equals(0));

        coordinator.dispose();
        refreshController.close();
      });
    });

    test(
      'first attempt noToken retries later and succeeds with the latest token',
      () {
        fakeAsync((async) {
          final refreshController = StreamController<String>.broadcast(
            sync: true,
          );
          var attempt = 0;
          var latestToken = 'token-before-retry';
          final registeredTokens = <String>[];

          final coordinator = PushRegistrationCoordinator(
            requestPermission: () async => true,
            registerPushToken: () async {
              attempt++;
              if (attempt == 1) {
                return RegisterPushTokenResult.noToken;
              }
              registeredTokens.add(latestToken);
              return RegisterPushTokenResult.success;
            },
            tokenRefreshStream: refreshController.stream,
            retryDelay: const Duration(seconds: 15),
          );

          coordinator.ensureStarted();
          async.flushMicrotasks();
          expect(attempt, equals(1));
          expect(registeredTokens, isEmpty);

          latestToken = 'token-after-retry';
          async.elapse(const Duration(seconds: 15));
          async.flushMicrotasks();

          expect(attempt, equals(2));
          expect(registeredTokens, equals(['token-after-retry']));

          coordinator.dispose();
          refreshController.close();
        });
      },
    );

    test('token refresh triggers re-registration', () {
      fakeAsync((async) {
        final refreshController = StreamController<String>.broadcast(
          sync: true,
        );
        var registerCalls = 0;

        final coordinator = PushRegistrationCoordinator(
          requestPermission: () async => true,
          registerPushToken: () async {
            registerCalls++;
            return RegisterPushTokenResult.success;
          },
          tokenRefreshStream: refreshController.stream,
        );

        coordinator.ensureStarted();
        async.flushMicrotasks();
        expect(registerCalls, equals(1));

        refreshController.add('refreshed-token');
        async.flushMicrotasks();

        expect(registerCalls, equals(2));

        coordinator.dispose();
        refreshController.close();
      });
    });

    test('retryNow retries registration after prior noToken or failed', () {
      fakeAsync((async) {
        final refreshController = StreamController<String>.broadcast(
          sync: true,
        );
        final results = <RegisterPushTokenResult>[
          RegisterPushTokenResult.failed,
          RegisterPushTokenResult.success,
        ];
        var registerCalls = 0;

        final coordinator = PushRegistrationCoordinator(
          requestPermission: () async => true,
          registerPushToken: () async {
            registerCalls++;
            return results.removeAt(0);
          },
          tokenRefreshStream: refreshController.stream,
          retryDelay: const Duration(minutes: 1),
        );

        coordinator.ensureStarted();
        async.flushMicrotasks();
        expect(registerCalls, equals(1));

        coordinator.retryNow();
        async.flushMicrotasks();

        expect(registerCalls, equals(2));

        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();
        expect(registerCalls, equals(2));

        coordinator.dispose();
        refreshController.close();
      });
    });

    test('ensureStarted does not attach duplicate token refresh listeners', () {
      fakeAsync((async) {
        final refreshController = StreamController<String>.broadcast(
          sync: true,
        );
        var registerCalls = 0;

        final coordinator = PushRegistrationCoordinator(
          requestPermission: () async => true,
          registerPushToken: () async {
            registerCalls++;
            return RegisterPushTokenResult.success;
          },
          tokenRefreshStream: refreshController.stream,
        );

        coordinator.ensureStarted();
        coordinator.ensureStarted();
        async.flushMicrotasks();
        expect(registerCalls, equals(1));

        refreshController.add('fresh-token');
        async.flushMicrotasks();

        expect(registerCalls, equals(2));

        coordinator.dispose();
        refreshController.close();
      });
    });
  });
}
