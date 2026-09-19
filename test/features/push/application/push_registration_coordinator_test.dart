import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/push_registration_coordinator.dart';
import 'package:flutter_app/features/push/application/push_registration_health_notifier.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart';
import 'package:flutter_app/features/push/domain/push_registration_health.dart';
import 'package:flutter_app/features/push/infrastructure/push_registration_health_store.dart';

void main() {
  setUp(() {
    flowEventLoggingEnabled = false;
  });

  group('PushRegistrationCoordinator', () {
    test(
      'explicit retry refreshes revoked permission and later restoration',
      () {
        fakeAsync((async) {
          final refresh = StreamController<String>.broadcast(sync: true);
          final notifier = PushRegistrationHealthNotifier();
          var permissionGranted = true;
          var permissionCalls = 0;
          var registerCalls = 0;
          final coordinator = PushRegistrationCoordinator(
            requestPermission: () async {
              permissionCalls++;
              return permissionGranted;
            },
            registerPushToken: () async {
              registerCalls++;
              return RegisterPushTokenResult.success;
            },
            tokenRefreshStream: refresh.stream,
            healthStore: _MemoryHealthStore(),
            healthNotifier: notifier,
          );
          coordinator.ensureStarted();
          async.flushMicrotasks();
          expect(notifier.value.phase, PushRegistrationHealthPhase.healthy);
          refresh.add('updated-token');
          async.flushMicrotasks();
          expect(registerCalls, 2);
          expect(
            permissionCalls,
            1,
            reason: 'automatic token refresh does not request permission again',
          );

          permissionGranted = false;
          coordinator.retryNow();
          async.flushMicrotasks();
          expect(permissionCalls, 2);
          expect(registerCalls, 2);
          expect(
            notifier.value.phase,
            PushRegistrationHealthPhase.permissionDenied,
          );
          expect(
            notifier.value.action,
            PushRegistrationHealthAction.openNotificationSettings,
          );
          expect(async.pendingTimers, isEmpty);

          permissionGranted = true;
          coordinator.retryNow();
          async.flushMicrotasks();
          expect(permissionCalls, 3);
          expect(registerCalls, 3);
          expect(notifier.value.phase, PushRegistrationHealthPhase.healthy);
          expect(notifier.value.warningVisible, isFalse);
          coordinator.dispose();
          notifier.dispose();
          refresh.close();
        });
      },
    );

    test(
      'explicit retry after revocation cannot join an older permission grant',
      () {
        fakeAsync((async) {
          final firstRegistration = Completer<RegisterPushTokenResult>();
          final notifier = PushRegistrationHealthNotifier();
          var permissionGranted = true;
          var permissionCalls = 0;
          var registerCalls = 0;
          final coordinator = PushRegistrationCoordinator(
            requestPermission: () async {
              permissionCalls++;
              return permissionGranted;
            },
            registerPushToken: () {
              registerCalls++;
              return firstRegistration.future;
            },
            tokenRefreshStream: const Stream.empty(),
            healthNotifier: notifier,
          );
          coordinator.ensureStarted();
          async.flushMicrotasks();
          expect(permissionCalls, 1);
          expect(registerCalls, 1);
          permissionGranted = false;
          var retryCompleted = false;
          coordinator.retryNow().then((_) => retryCompleted = true);
          async.flushMicrotasks();
          expect(retryCompleted, isFalse);
          firstRegistration.complete(RegisterPushTokenResult.success);
          async.flushMicrotasks();
          expect(retryCompleted, isTrue);
          expect(permissionCalls, 2);
          expect(registerCalls, 1);
          expect(
            notifier.value.phase,
            PushRegistrationHealthPhase.permissionDenied,
          );
          expect(async.pendingTimers, isEmpty);
          coordinator.dispose();
          notifier.dispose();
        });
      },
    );

    test(
      'explicit retry after restoration cannot join an older permission denial',
      () {
        fakeAsync((async) {
          final oldPermission = Completer<bool>();
          final notifier = PushRegistrationHealthNotifier();
          var permissionCalls = 0;
          var registerCalls = 0;
          final coordinator = PushRegistrationCoordinator(
            requestPermission: () {
              permissionCalls++;
              return permissionCalls == 1
                  ? oldPermission.future
                  : Future.value(true);
            },
            registerPushToken: () async {
              registerCalls++;
              return RegisterPushTokenResult.success;
            },
            tokenRefreshStream: const Stream.empty(),
            healthNotifier: notifier,
          );
          coordinator.ensureStarted();
          async.flushMicrotasks();
          var retryCompleted = false;
          coordinator.retryNow().then((_) => retryCompleted = true);
          async.flushMicrotasks();
          expect(retryCompleted, isFalse);
          oldPermission.complete(false);
          async.flushMicrotasks();
          expect(retryCompleted, isTrue);
          expect(permissionCalls, 2);
          expect(registerCalls, 1);
          expect(notifier.value.phase, PushRegistrationHealthPhase.healthy);
          expect(notifier.value.warningVisible, isFalse);
          expect(async.pendingTimers, isEmpty);
          coordinator.dispose();
          notifier.dispose();
        });
      },
    );

    test(
      'binding retry preserves a requested permission restoration check',
      () {
        fakeAsync((async) {
          final store = _ScopedMemoryHealthStore((
            accountPeerId: 'account-a',
            installationId: 'installation-1',
          ));
          final notifier = PushRegistrationHealthNotifier();
          var permissionGranted = false;
          var permissionCalls = 0;
          var registerCalls = 0;
          final coordinator = PushRegistrationCoordinator(
            requestPermission: () async {
              permissionCalls++;
              return permissionGranted;
            },
            registerPushToken: () async {
              registerCalls++;
              return RegisterPushTokenResult.success;
            },
            tokenRefreshStream: const Stream.empty(),
            retryDelay: const Duration(seconds: 10),
            healthStore: store,
            healthNotifier: notifier,
          );
          coordinator.ensureStarted();
          async.flushMicrotasks();
          expect(
            notifier.value.phase,
            PushRegistrationHealthPhase.permissionDenied,
          );
          expect(async.pendingTimers, isEmpty);

          permissionGranted = true;
          store.throwOnResolve = true;
          coordinator.retryNow();
          async.flushMicrotasks();
          expect(permissionCalls, 1);
          expect(registerCalls, 0);
          store.throwOnResolve = false;
          async.elapse(const Duration(seconds: 10));
          async.flushMicrotasks();
          expect(permissionCalls, 2);
          expect(registerCalls, 1);
          expect(notifier.value.phase, PushRegistrationHealthPhase.healthy);
          expect(notifier.value.warningVisible, isFalse);
          expect(async.pendingTimers, isEmpty);
          coordinator.dispose();
          notifier.dispose();
        });
      },
    );

    for (final fence in ['cutover', 'dispose', 'disabled']) {
      test(
        'late binding failure after $fence cannot schedule stale recovery',
        () {
          fakeAsync((async) {
            final resolution = Completer<PushRegistrationHealthBinding>();
            final store = _ScopedMemoryHealthStore((
              accountPeerId: 'account-a',
              installationId: 'installation-1',
            ))..resolveOverride = () => resolution.future;
            var enabled = true;
            var registerCalls = 0;
            final coordinator = PushRegistrationCoordinator(
              requestPermission: () async => true,
              registerPushToken: () async {
                registerCalls++;
                return RegisterPushTokenResult.success;
              },
              tokenRefreshStream: const Stream.empty(),
              retryDelay: const Duration(seconds: 10),
              healthStore: store,
              isEnabled: () => enabled,
            );
            coordinator.ensureStarted();
            async.flushMicrotasks();
            switch (fence) {
              case 'cutover':
                coordinator.beginAccountBindingCutover();
              case 'dispose':
                coordinator.dispose();
              case 'disabled':
                enabled = false;
            }
            resolution.completeError(StateError('identity became unavailable'));
            async.flushMicrotasks();
            expect(async.pendingTimers, isEmpty);
            async.elapse(const Duration(minutes: 1));
            async.flushMicrotasks();
            expect(registerCalls, 0);
            expect(store.writes, isEmpty);
            coordinator.dispose();
          });
        },
      );
    }

    test(
      'initial binding failure retries without another lifecycle trigger',
      () {
        fakeAsync((async) {
          final store = _ScopedMemoryHealthStore((
            accountPeerId: 'account-a',
            installationId: 'installation-1',
          ))..throwOnResolve = true;
          final notifier = PushRegistrationHealthNotifier();
          var permissionCalls = 0;
          var registerCalls = 0;
          final coordinator = PushRegistrationCoordinator(
            requestPermission: () async {
              permissionCalls++;
              return true;
            },
            registerPushToken: () async {
              registerCalls++;
              return RegisterPushTokenResult.success;
            },
            tokenRefreshStream: const Stream.empty(),
            retryDelay: const Duration(seconds: 10),
            healthStore: store,
            healthNotifier: notifier,
          );
          coordinator.ensureStarted();
          async.flushMicrotasks();
          expect(permissionCalls, 0);
          expect(registerCalls, 0);
          expect(store.writes, isEmpty);
          expect(notifier.record, isNull);

          store.throwOnResolve = false;
          async.elapse(const Duration(seconds: 10));
          async.flushMicrotasks();
          expect(permissionCalls, 1);
          expect(registerCalls, 1);
          expect(notifier.value.phase, PushRegistrationHealthPhase.healthy);
          expect(async.pendingTimers, isEmpty);
          coordinator.dispose();
          notifier.dispose();
        });
      },
    );

    test('binding outage cannot strand an existing registration warning', () {
      fakeAsync((async) {
        final store = _ScopedMemoryHealthStore((
          accountPeerId: 'account-a',
          installationId: 'installation-1',
        ));
        final notifier = PushRegistrationHealthNotifier();
        var registerCalls = 0;
        final coordinator = PushRegistrationCoordinator(
          requestPermission: () async => true,
          registerPushToken: () async => ++registerCalls <= 3
              ? RegisterPushTokenResult.failed
              : RegisterPushTokenResult.success,
          tokenRefreshStream: const Stream.empty(),
          retryDelay: const Duration(seconds: 10),
          healthStore: store,
          healthNotifier: notifier,
        );
        coordinator.ensureStarted();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();
        expect(registerCalls, 3);
        expect(notifier.value.warningVisible, isTrue);
        final failedRecord = notifier.record;
        final writesBeforeOutage = store.writes.length;

        store.throwOnResolve = true;
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(registerCalls, 3);
        expect(notifier.record, failedRecord);
        expect(store.writes.length, writesBeforeOutage);

        store.throwOnResolve = false;
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(registerCalls, 4);
        expect(notifier.value.phase, PushRegistrationHealthPhase.healthy);
        expect(notifier.value.warningVisible, isFalse);
        expect(store.records[store.binding], notifier.record);
        expect(async.pendingTimers, isEmpty);
        coordinator.dispose();
        notifier.dispose();
      });
    });

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

    test(
      'refresh during an in-flight registration registers the latest token',
      () {
        fakeAsync((async) {
          final refreshController = StreamController<String>.broadcast(
            sync: true,
          );
          final firstAttempt = Completer<RegisterPushTokenResult>();
          var currentToken = 'isolated-old-token';
          final registeredTokens = <String>[];
          final coordinator = PushRegistrationCoordinator(
            requestPermission: () async => true,
            registerPushToken: () {
              registeredTokens.add(currentToken);
              return registeredTokens.length == 1
                  ? firstAttempt.future
                  : Future.value(RegisterPushTokenResult.success);
            },
            tokenRefreshStream: refreshController.stream,
          );
          coordinator.ensureStarted();
          async.flushMicrotasks();
          expect(registeredTokens, ['isolated-old-token']);

          for (final token in ['isolated-new-token', 'isolated-latest-token']) {
            currentToken = token;
            refreshController.add(token);
            async.flushMicrotasks();
          }
          expect(registeredTokens, ['isolated-old-token']);
          firstAttempt.complete(RegisterPushTokenResult.success);
          async.flushMicrotasks();
          expect(registeredTokens, [
            'isolated-old-token',
            'isolated-latest-token',
          ]);
          expect(async.pendingTimers, isEmpty);
          coordinator.dispose();
          refreshController.close();
        });
      },
    );

    test('account migration block does not schedule registration retry', () {
      fakeAsync((async) {
        final refreshController = StreamController<String>.broadcast(
          sync: true,
        );
        var registerCalls = 0;

        final coordinator = PushRegistrationCoordinator(
          requestPermission: () async => true,
          registerPushToken: () async {
            registerCalls++;
            return RegisterPushTokenResult.accountMigrationBlocked;
          },
          tokenRefreshStream: refreshController.stream,
          retryDelay: const Duration(seconds: 15),
        );

        coordinator.ensureStarted();
        async.flushMicrotasks();
        expect(registerCalls, equals(1));

        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();

        expect(registerCalls, equals(1));

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

    test('permission denial is an immediate durable live warning', () {
      fakeAsync((async) {
        final refreshController = StreamController<String>.broadcast(
          sync: true,
        );
        final store = _MemoryHealthStore();
        final notifier = PushRegistrationHealthNotifier();
        final phases = <PushRegistrationHealthPhase?>[];
        notifier.addListener(() => phases.add(notifier.value.phase));
        final coordinator = PushRegistrationCoordinator(
          requestPermission: () async => false,
          registerPushToken: () async => RegisterPushTokenResult.success,
          tokenRefreshStream: refreshController.stream,
          healthStore: store,
          healthNotifier: notifier,
          now: () => DateTime.utc(2026, 8, 1, 8),
        );

        coordinator.ensureStarted();
        async.flushMicrotasks();

        expect(phases, contains(PushRegistrationHealthPhase.checking));
        expect(
          notifier.value.phase,
          PushRegistrationHealthPhase.permissionDenied,
        );
        expect(notifier.value.warningVisible, isTrue);
        expect(
          notifier.value.action,
          PushRegistrationHealthAction.openNotificationSettings,
        );
        expect(
          store.record?.reason,
          PushRegistrationHealthReason.permissionDenied,
        );

        coordinator.dispose();
        notifier.dispose();
        refreshController.close();
      });
    });

    test('transient failures warn at three and success clears live', () {
      fakeAsync((async) {
        final refreshController = StreamController<String>.broadcast(
          sync: true,
        );
        final store = _MemoryHealthStore();
        var hour = 8;
        final notifier = PushRegistrationHealthNotifier(
          now: () => DateTime.utc(2026, 8, 1, hour),
        );
        final results = <RegisterPushTokenResult>[
          RegisterPushTokenResult.noToken,
          RegisterPushTokenResult.failed,
          RegisterPushTokenResult.failed,
          RegisterPushTokenResult.success,
        ];
        final coordinator = PushRegistrationCoordinator(
          requestPermission: () async => true,
          registerPushToken: () async => results.removeAt(0),
          tokenRefreshStream: refreshController.stream,
          retryDelay: const Duration(days: 2),
          healthStore: store,
          healthNotifier: notifier,
          now: () => DateTime.utc(2026, 8, 1, hour),
        );

        coordinator.ensureStarted();
        async.flushMicrotasks();
        expect(store.record?.consecutiveFailures, 1);
        expect(notifier.value.warningVisible, isFalse);

        hour++;
        coordinator.retryNow();
        async.flushMicrotasks();
        expect(store.record?.consecutiveFailures, 2);
        expect(notifier.value.warningVisible, isFalse);

        hour++;
        coordinator.retryNow();
        async.flushMicrotasks();
        expect(store.record?.consecutiveFailures, 3);
        expect(notifier.value.warningVisible, isTrue);
        expect(notifier.value.action, PushRegistrationHealthAction.retry);

        hour++;
        coordinator.retryNow();
        async.flushMicrotasks();
        expect(store.record?.phase, PushRegistrationHealthPhase.healthy);
        expect(store.record?.consecutiveFailures, 0);
        expect(store.record?.lastSuccessAt, DateTime.utc(2026, 8, 1, 11));
        expect(notifier.value.warningVisible, isFalse);

        coordinator.dispose();
        notifier.dispose();
        refreshController.close();
      });
    });

    test('one unresolved transient failure becomes visible after 24 hours', () {
      fakeAsync((async) {
        var now = DateTime.utc(2026, 8, 1, 8);
        final notifier = PushRegistrationHealthNotifier(now: () => now);
        notifier.publish(
          PushRegistrationHealthRecord.retrying(
            reason: PushRegistrationHealthReason.noToken,
            consecutiveFailures: 1,
            firstFailureAt: now,
            lastAttemptAt: now,
          ),
        );
        expect(notifier.value.warningVisible, isFalse);

        now = now.add(const Duration(hours: 24));
        async.elapse(const Duration(hours: 24));
        async.flushMicrotasks();

        expect(notifier.value.warningVisible, isTrue);
        expect(notifier.value.action, PushRegistrationHealthAction.retry);
        notifier.dispose();
      });
    });

    test('24-hour threshold uses the last success when one exists', () {
      fakeAsync((async) {
        final refreshController = StreamController<String>.broadcast(
          sync: true,
        );
        var now = DateTime.utc(2026, 8, 1, 8);
        final notifier = PushRegistrationHealthNotifier(now: () => now);
        final results = <RegisterPushTokenResult>[
          RegisterPushTokenResult.success,
          RegisterPushTokenResult.failed,
        ];
        final coordinator = PushRegistrationCoordinator(
          requestPermission: () async => true,
          registerPushToken: () async => results.removeAt(0),
          tokenRefreshStream: refreshController.stream,
          retryDelay: const Duration(days: 2),
          healthStore: _MemoryHealthStore(),
          healthNotifier: notifier,
          now: () => now,
        );

        coordinator.ensureStarted();
        async.flushMicrotasks();
        expect(notifier.value.phase, PushRegistrationHealthPhase.healthy);

        now = now.add(const Duration(hours: 23));
        coordinator.retryNow();
        async.flushMicrotasks();
        expect(notifier.record?.consecutiveFailures, 1);
        expect(notifier.value.warningVisible, isFalse);

        now = now.add(const Duration(hours: 1));
        async.elapse(const Duration(hours: 1));
        async.flushMicrotasks();

        expect(notifier.value.warningVisible, isTrue);
        expect(notifier.value.action, PushRegistrationHealthAction.retry);

        coordinator.dispose();
        notifier.dispose();
        refreshController.close();
      });
    });

    test('concurrent triggers cannot regress one successful attempt', () {
      fakeAsync((async) {
        final refreshController = StreamController<String>.broadcast(
          sync: true,
        );
        final terminalResult = Completer<RegisterPushTokenResult>();
        final notifier = PushRegistrationHealthNotifier();
        var registerCalls = 0;
        final coordinator = PushRegistrationCoordinator(
          requestPermission: () async => true,
          registerPushToken: () {
            registerCalls++;
            return terminalResult.future;
          },
          tokenRefreshStream: refreshController.stream,
          healthStore: _MemoryHealthStore(),
          healthNotifier: notifier,
        );

        coordinator.ensureStarted();
        async.flushMicrotasks();
        expect(registerCalls, 1);
        expect(notifier.value.phase, PushRegistrationHealthPhase.checking);

        refreshController.add('new-token');
        coordinator.retryNow();
        async.flushMicrotasks();
        expect(registerCalls, 1);

        terminalResult.complete(RegisterPushTokenResult.success);
        async.flushMicrotasks();
        expect(notifier.value.phase, PushRegistrationHealthPhase.healthy);
        expect(notifier.value.warningVisible, isFalse);

        coordinator.dispose();
        notifier.dispose();
        refreshController.close();
      });
    });

    test('migration block is neutral and restores prior durable health', () {
      fakeAsync((async) {
        final refreshController = StreamController<String>.broadcast(
          sync: true,
        );
        final prior = PushRegistrationHealthRecord.retrying(
          reason: PushRegistrationHealthReason.registrationFailed,
          consecutiveFailures: 3,
          firstFailureAt: DateTime.utc(2026, 7, 31),
          lastAttemptAt: DateTime.utc(2026, 7, 31, 1),
        );
        final store = _MemoryHealthStore()..record = prior;
        final notifier = PushRegistrationHealthNotifier(
          now: () => DateTime.utc(2026, 8, 1, 8),
        );
        var registerCalls = 0;
        final coordinator = PushRegistrationCoordinator(
          requestPermission: () async => true,
          registerPushToken: () async {
            registerCalls++;
            return RegisterPushTokenResult.accountMigrationBlocked;
          },
          tokenRefreshStream: refreshController.stream,
          retryDelay: const Duration(seconds: 10),
          healthStore: store,
          healthNotifier: notifier,
          now: () => DateTime.utc(2026, 8, 1, 8),
        );

        coordinator.ensureStarted();
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();

        expect(registerCalls, 1);
        expect(store.record, prior);
        expect(notifier.value.warningVisible, isTrue);

        coordinator.dispose();
        notifier.dispose();
        refreshController.close();
      });
    });

    test(
      'secure-store failure never changes registration outcome or live state',
      () {
        fakeAsync((async) {
          final refreshController = StreamController<String>.broadcast(
            sync: true,
          );
          final store = _MemoryHealthStore()..throwOnMutation = true;
          final notifier = PushRegistrationHealthNotifier();
          var registerCalls = 0;
          final coordinator = PushRegistrationCoordinator(
            requestPermission: () async => true,
            registerPushToken: () async {
              registerCalls++;
              return RegisterPushTokenResult.success;
            },
            tokenRefreshStream: refreshController.stream,
            retryDelay: const Duration(seconds: 10),
            healthStore: store,
            healthNotifier: notifier,
          );

          coordinator.ensureStarted();
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 1));
          async.flushMicrotasks();

          expect(registerCalls, 1);
          expect(notifier.value.phase, PushRegistrationHealthPhase.healthy);
          expect(notifier.value.warningVisible, isFalse);

          coordinator.dispose();
          notifier.dispose();
          refreshController.close();
        });
      },
    );

    test(
      'secure-store failure preserves failed reason and scheduled retry',
      () {
        fakeAsync((async) {
          final refreshController = StreamController<String>.broadcast(
            sync: true,
          );
          final store = _MemoryHealthStore()..throwOnMutation = true;
          final notifier = PushRegistrationHealthNotifier();
          final results = <RegisterPushTokenResult>[
            RegisterPushTokenResult.failed,
            RegisterPushTokenResult.success,
          ];
          final coordinator = PushRegistrationCoordinator(
            requestPermission: () async => true,
            registerPushToken: () async => results.removeAt(0),
            tokenRefreshStream: refreshController.stream,
            retryDelay: const Duration(seconds: 10),
            healthStore: store,
            healthNotifier: notifier,
          );

          coordinator.ensureStarted();
          async.flushMicrotasks();
          expect(
            notifier.value.reason,
            PushRegistrationHealthReason.registrationFailed,
          );

          async.elapse(const Duration(seconds: 10));
          async.flushMicrotasks();
          expect(notifier.value.phase, PushRegistrationHealthPhase.healthy);
          expect(results, isEmpty);

          coordinator.dispose();
          notifier.dispose();
          refreshController.close();
        });
      },
    );

    test(
      'same-process account cutover hydrates only the new binding health',
      () async {
        final refreshController = StreamController<String>.broadcast();
        final accountA = (
          accountPeerId: 'account-a',
          installationId: 'installation-1',
        );
        final accountB = (
          accountPeerId: 'account-b',
          installationId: 'installation-1',
        );
        final accountAHealth = PushRegistrationHealthRecord.retrying(
          reason: PushRegistrationHealthReason.noToken,
          consecutiveFailures: 3,
          firstFailureAt: DateTime.utc(2026, 8, 1, 7),
          lastAttemptAt: DateTime.utc(2026, 8, 1, 8),
        );
        final store = _ScopedMemoryHealthStore(accountA)
          ..records[accountA] = accountAHealth;
        final notifier = PushRegistrationHealthNotifier();
        final results = <RegisterPushTokenResult>[
          RegisterPushTokenResult.accountMigrationBlocked,
          RegisterPushTokenResult.failed,
        ];
        final coordinator = PushRegistrationCoordinator(
          requestPermission: () async => true,
          registerPushToken: () async => results.removeAt(0),
          tokenRefreshStream: refreshController.stream,
          retryDelay: const Duration(days: 1),
          healthStore: store,
          healthNotifier: notifier,
          now: () => DateTime.utc(2026, 8, 1, 9),
        );

        await coordinator.ensureStarted();
        expect(store.records[accountA], accountAHealth);
        expect(notifier.record, accountAHealth);

        store.binding = accountB;
        await coordinator.retryNow();

        expect(store.records[accountA], accountAHealth);
        expect(store.records[accountB]?.consecutiveFailures, 1);
        expect(
          store.records[accountB]?.reason,
          PushRegistrationHealthReason.registrationFailed,
        );
        expect(notifier.record, store.records[accountB]);
        expect(results, isEmpty);

        coordinator.dispose();
        notifier.dispose();
        await refreshController.close();
      },
    );

    test(
      'account A completion after B cutover is fenced and retried for B',
      () async {
        final refreshController = StreamController<String>.broadcast();
        final accountA = (
          accountPeerId: 'account-a',
          installationId: 'installation-1',
        );
        final accountB = (
          accountPeerId: 'account-b',
          installationId: 'installation-1',
        );
        final store = _ScopedMemoryHealthStore(accountA);
        final notifier = PushRegistrationHealthNotifier();
        final firstAttempt = Completer<RegisterPushTokenResult>();
        final firstAttemptStarted = Completer<void>();
        var registerCalls = 0;
        final coordinator = PushRegistrationCoordinator(
          requestPermission: () async => true,
          registerPushToken: () {
            registerCalls++;
            if (registerCalls == 1) {
              firstAttemptStarted.complete();
              return firstAttempt.future;
            }
            return Future.value(RegisterPushTokenResult.success);
          },
          tokenRefreshStream: refreshController.stream,
          healthStore: store,
          healthNotifier: notifier,
          now: () => DateTime.utc(2026, 8, 1, 9),
        );

        final startup = coordinator.ensureStarted();
        await firstAttemptStarted.future;
        coordinator.beginAccountBindingCutover();
        store.binding = accountB;
        final cutover = coordinator.completeAccountBindingCutover();

        firstAttempt.complete(RegisterPushTokenResult.success);
        await Future.wait([startup, cutover]);

        expect(registerCalls, 2);
        expect(
          store.writes.where(
            (write) =>
                write.binding == accountA &&
                write.record.phase == PushRegistrationHealthPhase.healthy,
          ),
          isEmpty,
        );
        expect(
          store.records[accountB]?.phase,
          PushRegistrationHealthPhase.healthy,
        );
        expect(notifier.value.phase, PushRegistrationHealthPhase.healthy);

        coordinator.dispose();
        notifier.dispose();
        await refreshController.close();
      },
    );
  });
}

final class _MemoryHealthStore implements PushRegistrationHealthStorage {
  PushRegistrationHealthRecord? record;
  bool throwOnMutation = false;

  @override
  Future<void> clear() async {
    if (throwOnMutation) throw StateError('secure write failed');
    record = null;
  }

  @override
  Future<PushRegistrationHealthRecord?> read() async => record;

  @override
  Future<void> write(PushRegistrationHealthRecord value) async {
    if (throwOnMutation) throw StateError('secure write failed');
    record = value;
  }
}

final class _ScopedMemoryHealthStore
    implements BindingScopedPushRegistrationHealthStorage {
  _ScopedMemoryHealthStore(this.binding);

  PushRegistrationHealthBinding binding;
  bool throwOnResolve = false;
  Future<PushRegistrationHealthBinding> Function()? resolveOverride;
  final Map<PushRegistrationHealthBinding, PushRegistrationHealthRecord>
  records = {};
  final List<
    ({
      PushRegistrationHealthBinding binding,
      PushRegistrationHealthRecord record,
    })
  >
  writes = [];

  @override
  Future<PushRegistrationHealthBinding> resolveBinding() async {
    final override = resolveOverride;
    if (override != null) return override();
    if (throwOnResolve) throw StateError('identity temporarily unavailable');
    return binding;
  }

  @override
  Future<PushRegistrationHealthRecord?> read() async =>
      readForBinding(await resolveBinding());

  @override
  Future<void> write(PushRegistrationHealthRecord record) async {
    await writeForBinding(await resolveBinding(), record);
  }

  @override
  Future<void> clear() async {
    await clearForBinding(await resolveBinding());
  }

  @override
  Future<PushRegistrationHealthRecord?> readForBinding(
    PushRegistrationHealthBinding binding,
  ) async => records[binding];

  @override
  Future<void> writeForBinding(
    PushRegistrationHealthBinding binding,
    PushRegistrationHealthRecord record,
  ) async {
    writes.add((binding: binding, record: record));
    records[binding] = record;
  }

  @override
  Future<void> clearForBinding(PushRegistrationHealthBinding binding) async {
    records.remove(binding);
  }
}
