import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/push/application/firebase_readiness.dart';

// 191 (Fix D1): FirebaseReadiness latches ONLY on a successful initialize, so a
// transient `Firebase.initializeApp()` failure at cold start stays retryable
// instead of permanently deafening push (the pre-191 latch-before-try bug).
void main() {
  test(
    'init throws once → next ensureReady retries and succeeds; '
    'onFirstSuccess fires exactly once',
    () async {
      var attempts = 0;
      var firstSuccessCount = 0;
      final errors = <Object>[];

      final readiness = FirebaseReadiness(
        initialize: () async {
          attempts += 1;
          if (attempts == 1) {
            throw StateError('transient init failure');
          }
        },
        onFirstSuccess: () => firstSuccessCount += 1,
        onError: (error, _) => errors.add(error),
      );

      // Attempt 1 throws inside initialize → swallowed, NOT latched, retryable.
      await readiness.ensureReady();
      expect(readiness.isReady, isFalse);
      expect(attempts, 1);
      expect(firstSuccessCount, 0);
      expect(errors, hasLength(1));

      // Attempt 2 succeeds → latches, fires onFirstSuccess exactly once.
      await readiness.ensureReady();
      expect(readiness.isReady, isTrue);
      expect(attempts, 2);
      expect(firstSuccessCount, 1);

      // Attempt 3 is a no-op (already ready): no re-init, no second success.
      await readiness.ensureReady();
      expect(attempts, 2);
      expect(firstSuccessCount, 1);
    },
  );

  test(
    'success latches: second ensureReady is a no-op '
    '(no double init/background-handler registration)',
    () async {
      var attempts = 0;

      final readiness = FirebaseReadiness(initialize: () async => attempts += 1);

      await readiness.ensureReady();
      await readiness.ensureReady();
      await readiness.ensureReady();

      expect(readiness.isReady, isTrue);
      expect(
        attempts,
        1,
        reason:
            'a consumed success latch must prevent a second '
            'Firebase.initializeApp()/onBackgroundMessage registration',
      );
    },
  );

  test(
    'addOnReadyListener fires once on first success; a listener registered '
    'AFTER readiness runs immediately',
    () async {
      var earlyCount = 0;
      var lateCount = 0;

      final readiness = FirebaseReadiness(initialize: () async {});
      readiness.addOnReadyListener(() => earlyCount += 1);

      expect(earlyCount, 0);
      await readiness.ensureReady();
      expect(earlyCount, 1);

      // A listener added after readiness latched runs synchronously now (the
      // third arm point registering late must still arm the push listeners).
      readiness.addOnReadyListener(() => lateCount += 1);
      expect(lateCount, 1);

      // Idempotent: a further ensureReady never re-fires listeners.
      await readiness.ensureReady();
      expect(earlyCount, 1);
      expect(lateCount, 1);
    },
  );
}
