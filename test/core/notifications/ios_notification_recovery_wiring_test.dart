import 'dart:io';

import 'package:flutter_app/app/application_root.dart';
import 'package:flutter_app/core/notifications/ios_apns_notification_open_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'strict initial APNs route adapter surfaces false for custody retry',
    () async {
      var attempts = 0;
      await ensureIosInitialNotificationOpenRouted(() async {
        attempts += 1;
        return true;
      });
      await expectLater(
        ensureIosInitialNotificationOpenRouted(() async {
          attempts += 1;
          return false;
        }),
        throwsStateError,
      );
      expect(attempts, 2);
    },
  );

  test(
    'cold boundary ingests arrivals after runtime readiness and before settle',
    () async {
      final trace = <String>[];
      final stagedEvents = <String>[];
      final endedScopes = <String?>[];
      final endedCompleteness = <bool>[];

      Future<bool> ingest({required String source}) async {
        trace.add('ingest:$source:${stagedEvents.join(',')}');
        stagedEvents.clear();
        return source != 'cold_start_after_begin';
      }

      await ingest(source: 'runtime_ready');
      stagedEvents.add('arrived-after-runtime');
      final boundary = IosNotificationColdStartRecoveryBoundary<String>(
        beginMutation: () async {
          trace.add('begin:cold-scope');
          return 'cold-scope';
        },
        ingestStaged: ingest,
        endMutation:
            (scope, {required canonicalStateComplete, required source}) async {
              trace.add('end:$source');
              endedScopes.add(scope);
              endedCompleteness.add(canonicalStateComplete);
            },
      );

      final handle = await boundary.begin();
      stagedEvents.add('arrived-during-cold-work');
      await boundary.settle(
        recoveryHandle: handle,
        canonicalStateComplete: true,
      );

      expect(trace, <String>[
        'ingest:runtime_ready:',
        'begin:cold-scope',
        'ingest:cold_start_after_begin:arrived-after-runtime',
        'ingest:cold_start_before_settle:arrived-during-cold-work',
        'end:cold_start',
      ]);
      expect(endedScopes, <String?>['cold-scope']);
      expect(
        endedCompleteness,
        <bool>[false],
        reason:
            'the cold after-begin pass, not the earlier runtime-ready pass, '
            'owns completeness',
      );
    },
  );

  test(
    'overlapping cold flows settle only their opaque native scope',
    () async {
      var nextScope = 0;
      final endedScopes = <String?>[];
      final endedCompleteness = <bool>[];
      final boundary = IosNotificationColdStartRecoveryBoundary<String>(
        beginMutation: () async => 'scope-${++nextScope}',
        ingestStaged: ({required source}) async => true,
        endMutation:
            (scope, {required canonicalStateComplete, required source}) async {
              endedScopes.add(scope);
              endedCompleteness.add(canonicalStateComplete);
            },
      );

      final first = await boundary.begin();
      final second = await boundary.begin();
      await boundary.settle(
        recoveryHandle: first,
        canonicalStateComplete: false,
      );
      await boundary.settle(
        recoveryHandle: second,
        canonicalStateComplete: true,
      );

      expect(endedScopes, <String?>['scope-1', 'scope-2']);
      expect(endedCompleteness, <bool>[false, true]);
    },
  );

  test(
    'native initial-open gate retries failure and memoizes terminal outcomes',
    () async {
      var attempts = 0;
      final retryThenEmpty = IosApnsInitialNotificationOpenGate(
        attempt: () async {
          attempts += 1;
          return attempts == 1
              ? IosApnsInitialNotificationOpenDisposition.failed
              : IosApnsInitialNotificationOpenDisposition.empty;
        },
      );

      expect(
        await retryThenEmpty.consume(),
        IosApnsInitialNotificationOpenDisposition.failed,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        await retryThenEmpty.consume(),
        IosApnsInitialNotificationOpenDisposition.empty,
      );
      expect(
        await retryThenEmpty.consume(),
        IosApnsInitialNotificationOpenDisposition.empty,
      );
      expect(
        attempts,
        2,
        reason: 'empty is terminal and consumed exactly once',
      );

      var routedAttempts = 0;
      final routed = IosApnsInitialNotificationOpenGate(
        attempt: () async {
          routedAttempts += 1;
          return IosApnsInitialNotificationOpenDisposition.routed;
        },
      );
      expect(
        await routed.consume(),
        IosApnsInitialNotificationOpenDisposition.routed,
      );
      expect(
        await routed.consume(),
        IosApnsInitialNotificationOpenDisposition.routed,
      );
      expect(
        routedAttempts,
        1,
        reason: 'routed success is terminal and consumed exactly once',
      );
    },
  );

  test(
    'native initial APNs consumption is memoized and handed to cold startup',
    () {
      final source = File('lib/app/application_root.dart').readAsStringSync();

      final setupStart = source.indexOf(
        'void _setupIosApnsNotificationOpenBridge() {',
      );
      final setupEnd = source.indexOf(
        'Future<void> _routeRemoteNotificationOpen(',
        setupStart,
      );
      expect(setupStart, isNonNegative);
      expect(setupEnd, greaterThan(setupStart));
      final setup = source.substring(setupStart, setupEnd);
      expect(
        setup.indexOf(
          '_iosApnsNotificationOpenBridge.register(_routeRemoteNotificationOpen)',
        ),
        lessThan(setup.indexOf('_ensureIosApnsNotificationOpenBridgeReady()')),
        reason: 'warm notificationOpened delivery remains registered eagerly',
      );
      expect(
        setup,
        contains('_initialIosApnsNotificationOpenGate.consume()'),
        reason: 'overlapping StartupRouter flows cannot consume twice',
      );
      expect(
        setup,
        contains(
          'widget.iosNotificationRecoveryCoordinator == null\n'
          '          ? _consumeInitialIosApnsNotificationOpenAfterLegacyReady\n'
          '          : _consumeInitialIosApnsNotificationOpenAndMarkReady',
        ),
        reason:
            'production must use one native capture-clear-arm operation while '
            'the legacy path retains its separate readiness call',
      );
      final legacyGuard = setup.indexOf(
        'if (widget.iosNotificationRecoveryCoordinator == null) {',
      );
      final eagerReady = setup.indexOf(
        'unawaited(_ensureIosApnsNotificationOpenBridgeReady()',
      );
      expect(legacyGuard, isNonNegative);
      expect(eagerReady, greaterThan(legacyGuard));
      expect(
        setup.indexOf('await _ensureIosApnsNotificationOpenBridgeReady()'),
        lessThan(
          setup.indexOf('consumeInitialNotificationOpenWithDisposition('),
        ),
      );
      expect(
        setup,
        contains('_iosApnsNotificationOpenBridgeReady = null'),
        reason: 'a failed readiness attempt must remain retryable',
      );
      expect(
        setup,
        contains('consumeInitialNotificationOpenAndMarkReadyWithDisposition('),
      );
      expect(
        RegExp(
          r'consumeInitialNotificationOpen(?:AndMarkReady)?WithDisposition\('
          r'\s*_routeInitialIosApnsNotificationOpen,',
        ).allMatches(setup),
        hasLength(2),
        reason:
            'both initial APNs paths must surface route failure to the retrying '
            'custody gate; the warm wrapper remains best-effort',
      );

      final strictRouteStart = source.indexOf(
        'Future<void> _routeInitialIosApnsNotificationOpen(',
      );
      final strictRouteEnd = source.indexOf(
        'Future<bool> _tryRouteRemoteNotificationOpen(',
        strictRouteStart,
      );
      expect(strictRouteStart, isNonNegative);
      expect(strictRouteEnd, greaterThan(strictRouteStart));
      final strictRoute = source.substring(strictRouteStart, strictRouteEnd);
      expect(
        strictRoute,
        contains('await ensureIosInitialNotificationOpenRouted('),
      );
      expect(
        strictRoute,
        contains('() => _tryRouteRemoteNotificationOpen(data)'),
      );

      final appDelegate = File(
        'ios/Runner/AppDelegate.swift',
      ).readAsStringSync();
      final atomicCaseStart = appDelegate.indexOf(
        'case "consumeInitialNotificationOpenAndMarkReady":',
      );
      final atomicCaseEnd = appDelegate.indexOf('default:', atomicCaseStart);
      expect(atomicCaseStart, isNonNegative);
      expect(atomicCaseEnd, greaterThan(atomicCaseStart));
      final atomicCase = appDelegate.substring(atomicCaseStart, atomicCaseEnd);
      final capture = atomicCase.indexOf(
        'let payload = pendingIosNotificationOpen',
      );
      final clear = atomicCase.indexOf('pendingIosNotificationOpen = nil');
      final arm = atomicCase.indexOf('iosNotificationOpenBridgeReady = true');
      final reply = atomicCase.indexOf('result(payload)');
      expect(capture, isNonNegative);
      expect(clear, greaterThan(capture));
      expect(arm, greaterThan(clear));
      expect(reply, greaterThan(arm));

      final routerWiringStart = source.indexOf(
        'onIosNotificationColdStartRecoveryStarted:',
      );
      final routerWiringEnd = source.indexOf(
        'onIosNotificationColdStartRecoverySettled:',
        routerWiringStart,
      );
      expect(routerWiringStart, isNonNegative);
      expect(routerWiringEnd, greaterThan(routerWiringStart));
      expect(
        source.substring(routerWiringStart, routerWiringEnd),
        contains('consumeInitialIosApnsNotificationOpen:'),
      );
      expect(
        source.substring(routerWiringStart, routerWiringEnd),
        contains('_consumeInitialIosApnsNotificationOpenOnce'),
      );
    },
  );

  test(
    'runtime, cold start, and resume use explicit iOS mutation boundaries',
    () {
      final source = File('lib/app/application_root.dart').readAsStringSync();

      final startupStart = source.indexOf(
        'runtimeStartupLatch = AccountMigrationRuntimeStartupLatch(',
      );
      final startupEnd = source.indexOf(
        '_setPresenceUseCase = SetPresenceUseCase(',
        startupStart,
      );
      expect(startupStart, isNonNegative);
      expect(startupEnd, greaterThan(startupStart));
      final startup = source.substring(startupStart, startupEnd);
      expect(startup, contains('onStarted: () async {'));
      expect(startup, contains('iosNotificationRecoveryCoordinator == null'));
      expect(
        startup,
        contains(
          "unawaited(_ingestStagedPushEnvelopes(source: 'runtime_ready'))",
        ),
        reason: 'off-iOS retains the pre-existing fire-and-forget path',
      );
      expect(
        startup.indexOf('_beginIosNotificationCanonicalMutation('),
        lessThan(startup.indexOf('_tryIngestStagedPushEnvelopes(')),
      );
      expect(
        startup.indexOf('_tryIngestStagedPushEnvelopes('),
        lessThan(startup.indexOf('_endIosNotificationCanonicalMutation(')),
      );
      expect(startup, contains('canonicalStateComplete: false'));

      final coldBoundary = source.substring(
        source.indexOf('final class IosNotificationColdStartRecoveryBoundary'),
        source.indexOf('class MyApp extends StatefulWidget'),
      );
      expect(coldBoundary, contains("source: 'cold_start_after_begin'"));
      expect(coldBoundary, contains("source: 'cold_start_before_settle'"));
      expect(
        coldBoundary.indexOf("source: 'cold_start_before_settle'"),
        lessThan(coldBoundary.lastIndexOf('await _endMutation(')),
      );
      expect(coldBoundary, contains('_activeFlows.remove(recoveryHandle)'));

      final coldCompositionStart = source.indexOf(
        '_iosNotificationColdStartRecoveryBoundary =',
      );
      final coldCompositionEnd = source.indexOf(
        'runtimeStartupLatch = AccountMigrationRuntimeStartupLatch(',
        coldCompositionStart,
      );
      final coldComposition = source.substring(
        coldCompositionStart,
        coldCompositionEnd,
      );
      expect(coldComposition, contains('globallyExhaustive: true'));
      expect(
        coldComposition,
        contains('allowClearedAccountPeerReactivation: true'),
      );
      expect(source, isNot(contains('_iosColdStartStagedIngressComplete')));

      final resumeStart = source.indexOf('Future<void> _onResumed() async {');
      final resumeEnd = source.indexOf(
        'void _setupPushListeners()',
        resumeStart,
      );
      expect(resumeStart, isNonNegative);
      expect(resumeEnd, greaterThan(resumeStart));
      final resume = source.substring(resumeStart, resumeEnd);
      final boundary = resume.indexOf(
        '_beginIosNotificationCanonicalMutation(',
      );
      final ingest = resume.indexOf('_tryIngestStagedPushEnvelopes(');
      final ownership = resume.indexOf(
        'await _hasPendingDroppedPushRecovery()',
      );
      final canonicalDrain = resume.indexOf('final resumeResult = await ');
      final directProjection = resume.indexOf(
        'await widget.retryDirectNotificationProjection?.call()',
      );
      final droppedRepoll = resume.indexOf(
        'await _droppedPushRecoveryRepollLatch.drain(',
      );
      final recovery = resume.lastIndexOf(
        '_endIosNotificationCanonicalMutation(',
      );
      expect(boundary, isNonNegative);
      expect(ingest, greaterThan(boundary));
      expect(ownership, greaterThan(ingest));
      expect(canonicalDrain, greaterThan(ownership));
      expect(directProjection, greaterThan(canonicalDrain));
      expect(droppedRepoll, greaterThan(directProjection));
      expect(recovery, greaterThan(droppedRepoll));
      expect(resume, contains('if (awaitIosCanonicalDrains) {'));
      expect(
        resume,
        contains(
          "unawaited(_ingestStagedPushEnvelopes(source: 'app_resumed'))",
        ),
        reason: 'off-iOS resume remains fire-and-forget',
      );
    },
  );

  test(
    'foreground and account activation recover after their canonical work',
    () {
      final source = File('lib/app/application_root.dart').readAsStringSync();

      final foregroundStart = source.indexOf(
        'Future<void> _handleForegroundRemotePush(RemoteMessage message) async {',
      );
      final foregroundEnd = source.indexOf(
        'Future<ConversationNotificationSnapshot?>',
        foregroundStart,
      );
      expect(foregroundStart, isNonNegative);
      expect(foregroundEnd, greaterThan(foregroundStart));
      final foreground = source.substring(foregroundStart, foregroundEnd);
      expect(
        foreground.indexOf('await handleForegroundRemoteMessage('),
        lessThan(
          foreground.indexOf(
            'await showForegroundPushFallbackNotificationIfNeeded(',
          ),
        ),
      );
      expect(
        foreground.indexOf(
          'await showForegroundPushFallbackNotificationIfNeeded(',
        ),
        lessThan(foreground.indexOf('_endIosNotificationCanonicalMutation(')),
      );
      expect(foreground, contains('result.canonicalStateComplete'));
      expect(foreground, contains('result.needsNotification'));
      expect(
        foreground,
        contains('widget.iosNotificationRecoveryCoordinator == null'),
        reason: 'exact multi-page drains are iOS recovery-only',
      );

      final accountStart = source.indexOf(
        'Future<void> _handleAccountMigrationReceiverActivated() async {',
      );
      final accountEnd = source.indexOf(
        '@override\n  Widget build(',
        accountStart,
      );
      expect(accountStart, isNonNegative);
      expect(accountEnd, greaterThan(accountStart));
      final account = source.substring(accountStart, accountEnd);
      expect(
        account.indexOf('_beginIosNotificationCanonicalMutation('),
        lessThan(
          account.indexOf(
            'await activateAccountMigrationReceiverNotificationState(',
          ),
        ),
      );
      expect(
        account.indexOf(
          'await activateAccountMigrationReceiverNotificationState(',
        ),
        lessThan(account.indexOf('_endIosNotificationCanonicalMutation(')),
      );
    },
  );

  test('production composes one iOS-only owner and exact account clear', () {
    final source = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    final composition = source.indexOf(
      'final iosNotificationRecoveryCoordinator =',
    );
    expect(composition, isNonNegative);
    expect(source, contains('!kIsWeb && Platform.isIOS'));
    expect(
      source.substring(composition),
      contains(
        'loadCanonicalState: () => dbLoadCanonicalNotificationBadgeState(db)',
      ),
    );
    expect(
      source.substring(composition),
      contains('iosNotificationRecoveryEnabled\n        ?'),
    );
    expect(
      source.substring(composition),
      contains(
        'onNotificationUpdated: iosNotificationRecoveryCoordinator?.reconcile',
      ),
    );
    expect(
      source.substring(composition),
      contains(
        'onConversationCleared: iosNotificationRecoveryCoordinator == null',
      ),
    );
    expect(
      source.substring(composition),
      contains('iosNotificationRecoveryCoordinator:'),
    );

    final cutover = source.indexOf('clearLocalStalePushToken: () async {');
    expect(cutover, isNonNegative);
    final clear = source.indexOf(
      'await iosNotificationRecoveryCoordinator?.clearAccount();',
      cutover,
    );
    final token = source.indexOf('await pushTokenStore.clearToken();', cutover);
    expect(clear, greaterThan(cutover));
    expect(token, greaterThan(clear));
  });
}
