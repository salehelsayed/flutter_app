// Pins the post-cutover push re-registration chain on the NEW phone.
//
// During a Move Account transfer the registration attempt is gated
// (accountMigrationBlocked) and deliberately schedules NO retry. After the
// activation reroute, the restarted StartupRouter calls ensureStarted() on
// the SAME coordinator instance — which is a no-op once started. The seam
// that actually re-registers push after cutover is retryNow(), invoked from
// handleAppResumed (main.dart wires retryPushRegistrationFn to it). These
// tests document that chain so a refactor that breaks it goes red.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/push_registration_coordinator.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    flowEventLoggingEnabled = false;
  });

  tearDown(() {
    flowEventLoggingEnabled = true;
  });

  test('migration-blocked attempt does not retry until retryNow (post-cutover seam)', () {
    fakeAsync((async) {
      final refreshController = StreamController<String>.broadcast(sync: true);
      var registerCalls = 0;
      final results = <RegisterPushTokenResult>[
        // During the move: gated.
        RegisterPushTokenResult.accountMigrationBlocked,
        // After cutover (app resume → retryNow): allowed.
        RegisterPushTokenResult.success,
      ];
      final coordinator = PushRegistrationCoordinator(
        requestPermission: () async => true,
        registerPushToken: () async {
          registerCalls++;
          return results.length > 1 ? results.removeAt(0) : results.first;
        },
        tokenRefreshStream: refreshController.stream,
        retryDelay: const Duration(seconds: 15),
      );

      coordinator.ensureStarted();
      async.flushMicrotasks();
      expect(registerCalls, 1);

      // accountMigrationBlocked schedules NO retry timer.
      async.elapse(const Duration(minutes: 2));
      expect(registerCalls, 1);

      // The activation reroute calls ensureStarted() again on the SAME
      // instance — a no-op once started. This is the gap that makes
      // retryNow the load-bearing seam.
      coordinator.ensureStarted();
      async.flushMicrotasks();
      expect(registerCalls, 1);

      // App resume after cutover: retryNow re-registers under the new
      // (active) authority.
      coordinator.retryNow();
      async.flushMicrotasks();
      expect(registerCalls, 2);

      coordinator.dispose();
      refreshController.close();
    });
  });
}
