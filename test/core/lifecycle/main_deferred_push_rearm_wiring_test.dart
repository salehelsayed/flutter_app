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
  test(
    'TC-164-02 (A) push listeners are re-armed post-ready with an unconditional '
    'idempotence latch',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();

      // The runtime-services-ready completion path re-invokes push registration.
      expect(
        mainSource,
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
        mainSource,
        contains('if (widget.isDesktop || Firebase.apps.isEmpty) return;'),
        reason: 'the empty-Firebase.apps early-return is unchanged',
      );

      // ...and now carries an unconditional _pushListenersArmed idempotence latch
      // so the initState call + the re-arm cannot double-register onMessage /
      // onMessageOpenedApp.
      expect(
        mainSource,
        contains('_pushListenersArmed'),
        reason:
            'a double onMessage.listen would duplicate foreground-push handling '
            'and routing',
      );
    },
  );

  test(
    'TC-164-02 (B) the push-token coordinator stays non-null off the empty-'
    'Firebase.apps path with a lazy token-refresh stream',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();

      // Scope to the coordinator construction block.
      final start = mainSource.indexOf(
        'final PushRegistrationCoordinator? pushRegistrationCoordinator =',
      );
      expect(start, isNonNegative);
      final end = mainSource.indexOf('final conversationTracker', start);
      expect(end, greaterThan(start));
      final coordinatorBlock = mainSource.substring(start, end);

      // (B1) the Firebase.apps.isNotEmpty clause is dropped from the gate, so the
      // coordinator is non-null on a normal launch despite deferred Firebase.
      // Scope to the gate CONDITION only (up to the ternary `?`) so an
      // explanatory comment mentioning the historical clause cannot false-trip.
      final gateEnd = mainSource.indexOf('? PushRegistrationCoordinator(', start);
      expect(gateEnd, greaterThan(start));
      final gate = mainSource.substring(start, gateEnd);
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
          contains('tokenRefreshStream: FirebaseMessaging.instance.onTokenRefresh'),
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
    },
  );
}
