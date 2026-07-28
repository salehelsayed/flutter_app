import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

// 164 (cold-start-1, BOTH Firebase-gated push-wiring sites): deferring Firebase
// past initState empties Firebase.apps for the whole pre-runApp region, which
// would silently break TWO push wires unless re-armed:
//   (A) the foreground-push / open-app LISTENERS (_setupPushListeners), and
//   (B) the push-TOKEN coordinator (pushRegistrationCoordinator), whose
//       Firebase.apps.isNotEmpty gate would otherwise build it null.
// These host wiring-locks are the lowest tier that can fail for the real reason
// (real Firebase is unavailable host-side); the behavioral closure is the
// device-proof TC-164-08c (foreground push) + TC-164-08e (token register).
void main() {
  test('TC-164-02 (A) push listeners are re-armed post-ready with an unconditional '
      'idempotence latch', () async {
    expect(app.MyApp.navigatorKey, isNotNull);

    final applicationRootSource = await File(
      'lib/app/application_root.dart',
    ).readAsString();

    // The runtime-services-ready completion path re-invokes push registration.
    expect(
      applicationRootSource,
      contains(
        '_ensureRuntimeServicesReady().then((_) => _setupPushListeners())',
      ),
      reason:
          'on a normal launch the initState _setupPushListeners() no-ops '
          '(Firebase.apps empty); it must be re-armed once Firebase is ready',
    );

    // _setupPushListeners still early-returns on Firebase.apps.isEmpty (so the
    // re-arm is the first effective registration on a normal launch)...
    expect(
      applicationRootSource,
      contains('if (widget.isDesktop || Firebase.apps.isEmpty) return;'),
      reason: 'the empty-Firebase.apps early-return is unchanged',
    );

    // ...and now carries an unconditional _pushListenersArmed idempotence latch
    // so the initState call + the re-arm cannot double-register onMessage /
    // onMessageOpenedApp.
    expect(
      applicationRootSource,
      contains('_pushListenersArmed'),
      reason:
          'a double onMessage.listen would duplicate foreground-push handling '
          'and routing',
    );
  });

  test('TC-164-02 (B) the push-token coordinator stays non-null off the empty-'
      'Firebase.apps path with a lazy token-refresh stream', () async {
    expect(app.MyApp.navigatorKey, isNotNull);

    final productionSource = await File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsString();

    // Scope to the coordinator construction block. Terminator: the next
    // declaration after the block — `final groupConversationTracker`
    // (was `final conversationTracker` until the CV-26 FDC-04 re-warm
    // wiring moved that construction ABOVE the coordinator, be440b1e).
    final start = productionSource.indexOf(
      'final PushRegistrationCoordinator? pushRegistrationCoordinator =',
    );
    expect(start, isNonNegative);
    final end = productionSource.indexOf(
      'final groupConversationTracker',
      start,
    );
    expect(end, greaterThan(start));
    final coordinatorBlock = productionSource.substring(start, end);

    // (B1) the Firebase.apps.isNotEmpty clause is dropped from the gate, so the
    // coordinator is non-null on a normal launch despite deferred Firebase.
    // Scope to the gate CONDITION only (up to the ternary `?`) so an
    // explanatory comment mentioning the historical clause cannot false-trip.
    final gateEnd = productionSource.indexOf(
      '? PushRegistrationCoordinator(',
      start,
    );
    expect(gateEnd, greaterThan(start));
    final gate = productionSource.substring(start, gateEnd);
    expect(
      gate,
      isNot(contains('Firebase.apps.isNotEmpty')),
      reason:
          'leaving this clause would build the coordinator null post-deferral '
          '→ no onTokenRefresh subscription, no startup registerPushToken()',
    );

    // (B2) the token-refresh stream is NOT the bare eager
    // FirebaseMessaging.instance.onTokenRefresh (which would touch
    // FirebaseMessaging.instance at construction, before Firebase init →
    // throw). It is wrapped in a lazy Stream.multi.
    expect(
      coordinatorBlock,
      isNot(
        contains(
          'tokenRefreshStream: FirebaseMessaging.instance.onTokenRefresh',
        ),
      ),
      reason:
          'an eager FirebaseMessaging.instance read at construction throws '
          'before the deferred Firebase init',
    );
    expect(
      coordinatorBlock,
      contains('Stream<String>.multi('),
      reason:
          'the token-refresh stream must defer the FirebaseMessaging.instance '
          'touch to listen-time (post-ready, inside ensureStarted)',
    );
  });

  // 191 (Fix D1): the pre-191 `ensureFirebaseReady` latched
  // `firebaseInitialized = true` at main.dart:401 BEFORE the try, so a single
  // thrown `Firebase.initializeApp()` (a transient cold-start failure)
  // permanently marked Firebase "ready" and no later call ever retried — the
  // process stayed deaf to push for its whole lifetime. The fix delegates to an
  // extracted `FirebaseReadiness` unit that latches ONLY on success (retryable).
  test('191: ensureFirebaseReady latches on success only '
      '(FirebaseReadiness delegation present)', () async {
    expect(app.MyApp.navigatorKey, isNotNull);

    final productionSource = await File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsString();

    // (1) main() delegates Firebase init to the extracted retryable unit.
    expect(
      productionSource,
      contains('FirebaseReadiness('),
      reason:
          'ensureFirebaseReady must delegate to the extracted FirebaseReadiness '
          'unit (latch-after-success), not inline a latch-before-try',
    );
    expect(
      productionSource,
      contains('firebaseReadiness.ensureReady()'),
      reason:
          'ensureFirebaseReady() must delegate to FirebaseReadiness.ensureReady()',
    );

    // (2) the latch-before-try bug shape is gone: no eager
    // `firebaseInitialized = true` consumed before Firebase.initializeApp().
    expect(
      productionSource,
      isNot(contains('firebaseInitialized = true;')),
      reason:
          'the pre-191 latch-before-try (firebaseInitialized = true before the '
          'Firebase.initializeApp() try) permanently deafened push on one '
          'transient init failure — it must be gone',
    );
  });

  // 191 (Fix D2): the two pre-191 arm points (initState _setupPushListeners()
  // and the _ensureRuntimeServicesReady().then re-arm) both no-op when
  // Firebase.apps is empty and the memoized runtime-ready future collapses them
  // to one effective attempt — so a retried/late Firebase init can leave push
  // permanently disarmed with no telemetry. The fix delegates the arm to an
  // observable `PushListenerArmer` (emits PUSH_LISTENERS_ARMED once) and adds a
  // THIRD arm point that rides Firebase first-success readiness.
  test(
    '191: listener arm rides Firebase readiness and emits PUSH_LISTENERS_ARMED',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final applicationRootSource = await File(
        'lib/app/application_root.dart',
      ).readAsString();

      // (1) the arm is delegated to the observable, unit-locked armer.
      expect(
        applicationRootSource,
        contains('PushListenerArmer('),
        reason:
            'the push-listener arm must delegate to the observable '
            'PushListenerArmer unit (which emits PUSH_LISTENERS_ARMED once)',
      );

      // (2) a THIRD arm point rides FirebaseReadiness — the only event that
      // flips Firebase.apps non-empty — so a retried/late init still arms,
      // independent of the _ensureRuntimeServicesReady timing.
      expect(
        applicationRootSource,
        contains('firebaseReadiness'),
        reason:
            'a third arm point must ride the FirebaseReadiness instance passed '
            'into MyApp so a retried/late Firebase init still arms the listeners',
      );
      expect(
        applicationRootSource,
        contains('addOnReadyListener'),
        reason:
            '_MyAppState must register _setupPushListeners on Firebase readiness '
            '(the third arm point) via FirebaseReadiness.addOnReadyListener',
      );

      // The 164 idempotence contract is preserved (belt-and-suspenders with the
      // armer latch): the widget-level guard + _pushListenersArmed latch stay.
      expect(
        applicationRootSource,
        contains('if (widget.isDesktop || Firebase.apps.isEmpty) return;'),
        reason: 'the 164 empty-Firebase.apps early-return must be preserved',
      );
    },
  );
}
