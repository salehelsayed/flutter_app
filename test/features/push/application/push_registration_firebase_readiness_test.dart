import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/firebase_readiness.dart';
import 'package:flutter_app/features/push/application/push_registration_coordinator.dart';
import 'package:flutter_app/features/push/application/push_registration_health_notifier.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart';
import 'package:flutter_app/features/push/application/request_push_permission_use_case.dart';
import 'package:flutter_app/features/push/domain/push_registration_health.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => flowEventLoggingEnabled = false);

  test(
    'default permission consumer reports the observed Firebase no-app code',
    () async {
      await expectLater(
        requestPushPermission(),
        throwsA(
          isA<FirebaseException>().having((e) => e.code, 'code', 'no-app'),
        ),
      );
    },
  );

  for (final explicitRetry in [true, false]) {
    test(
      '${explicitRetry ? 'explicit' : 'scheduled'} retry initializes Firebase before consumers',
      () {
        fakeAsync((async) {
          var initCalls = 0;
          var allowInitialization = false;
          final readiness = FirebaseReadiness(
            initialize: () async {
              initCalls++;
              if (!allowInitialization) {
                throw PlatformException(code: 'firebase-init-unavailable');
              }
            },
          );
          // Startup is best-effort and has already failed before the coordinator.
          readiness.ensureReady();
          async.flushMicrotasks();
          expect(initCalls, 1);
          expect(readiness.isReady, isFalse);
          var streamSubscriptions = 0;
          var permissionCalls = 0;
          var registrations = 0;
          final refresh = StreamController<String>.broadcast(
            sync: true,
            onListen: () => streamSubscriptions++,
          );
          final health = PushRegistrationHealthNotifier(failureThreshold: 1);
          final coordinator = PushRegistrationCoordinator(
            ensureReady: () async {
              await readiness.ensureReady();
              return readiness.isReady;
            },
            requestPermission: () {
              permissionCalls++;
              // The production consumer throws the actual no-app exception if
              // initialization ordering regresses; no hand-written substitute.
              return readiness.isReady
                  ? Future.value(true)
                  : requestPushPermission();
            },
            registerPushToken: () async {
              registrations++;
              return RegisterPushTokenResult.success;
            },
            tokenRefreshStream: refresh.stream,
            healthNotifier: health,
          );
          coordinator.ensureStarted();
          async.flushMicrotasks();
          expect(initCalls, 2);
          expect(streamSubscriptions, 0);
          expect(permissionCalls, 0);
          expect(registrations, 0);
          expect(health.value.phase, PushRegistrationHealthPhase.retrying);
          expect(health.value.warningVisible, isTrue);
          expect(async.pendingTimers, hasLength(1));

          allowInitialization = true;
          if (explicitRetry) {
            coordinator.retryNow();
          } else {
            async.elapse(const Duration(seconds: 15));
          }
          async.flushMicrotasks();
          expect(initCalls, 3);
          expect(streamSubscriptions, 1);
          expect(permissionCalls, 1);
          expect(registrations, 1);
          expect(health.value.phase, PushRegistrationHealthPhase.healthy);
          expect(health.value.warningVisible, isFalse);
          expect(async.pendingTimers, isEmpty);

          refresh.add('fixture-token-refresh');
          async.flushMicrotasks();
          expect(initCalls, 3);
          expect(streamSubscriptions, 1);
          expect(
            permissionCalls,
            1,
            reason: 'automatic refresh must not re-prompt',
          );
          expect(registrations, 2);
          coordinator.dispose();
          health.dispose();
          refresh.close();
        });
      },
    );
  }

  for (final fence in ['dispose', 'disable', 'account_cutover']) {
    for (final failure in [false, true]) {
      test(
        '$fence while Firebase initializes (failure=$failure) blocks late consumers',
        () {
          fakeAsync((async) {
            final initialized = Completer<bool>();
            var enabled = true;
            var subscriptions = 0;
            var permissionCalls = 0;
            var registrations = 0;
            final refresh = StreamController<String>.broadcast(
              onListen: () => subscriptions++,
            );
            final health = PushRegistrationHealthNotifier();
            final coordinator = PushRegistrationCoordinator(
              ensureReady: () => initialized.future,
              isEnabled: () => enabled,
              requestPermission: () async {
                permissionCalls++;
                return true;
              },
              registerPushToken: () async {
                registrations++;
                return RegisterPushTokenResult.success;
              },
              tokenRefreshStream: refresh.stream,
              healthNotifier: health,
            );
            coordinator.ensureStarted();
            async.flushMicrotasks();
            expect(subscriptions, 0);
            if (fence == 'dispose') coordinator.dispose();
            if (fence == 'disable') enabled = false;
            if (fence == 'account_cutover') {
              coordinator.beginAccountBindingCutover();
            }
            final fencedHealth = health.value;
            if (failure) {
              initialized.completeError(
                StateError('fixture initialization failed'),
              );
            } else {
              initialized.complete(true);
            }
            async.flushMicrotasks();
            expect(subscriptions, 0);
            expect(permissionCalls, 0);
            expect(registrations, 0);
            expect(health.value, fencedHealth);
            expect(async.pendingTimers, isEmpty);
            coordinator.dispose();
            health.dispose();
            refresh.close();
          });
        },
      );
    }
  }
}
