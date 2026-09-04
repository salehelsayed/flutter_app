import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/core/debug/intro_e2e_runner.dart' as intro_runner;
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart'
    as contact_request;
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/scripts/run_intro_accept_notification_android.dart'
    as intro_campaign;
import '../../../integration_test/scripts/run_intro_accept_notification_sims.dart'
    as intro_sims;

void main() {
  test(
    'poller teardown is idempotent and cancels initial and periodic work',
    () {
      fakeAsync((async) {
        var ticks = 0;
        final lifecycle = intro_runner.IntroE2EPollerLifecycle(
          initialDelay: const Duration(seconds: 2),
          pollInterval: const Duration(seconds: 3),
          tick: () async {
            ticks++;
          },
        )..start();

        final first = lifecycle.dispose();
        final second = lifecycle.dispose();
        expect(identical(first, second), isTrue);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();

        expect(
          ticks,
          0,
          reason: 'neither scheduled timer may poll after dispose',
        );
      });
    },
  );

  test('accepts ActivityManager wait timeout for later identity proof', () {
    expect(intro_campaign.isAndroidActivityStartAccepted('Status: ok'), isTrue);
    expect(
      intro_campaign.isAndroidActivityStartAccepted('Status: timeout'),
      isTrue,
      reason:
          'am start -W can time out while the launched app continues startup; '
          'the following identity-export phase remains the causal proof',
    );
    expect(
      intro_campaign.isAndroidActivityStartAccepted(
        'Error type 3: Activity class does not exist.',
      ),
      isFalse,
    );
  });

  test('host launch timeout accepts only the exact component handoff', () {
    expect(
      intro_campaign.isAndroidActivityStartProvisionallyAccepted(
        'Starting: Intent { cmp=com.mknoon.app/.MainActivity }\n',
        packageName: 'com.mknoon.app',
      ),
      isTrue,
    );
    expect(
      intro_campaign.isAndroidActivityStartProvisionallyAccepted(
        'Starting: Intent { cmp=com.other.app/.MainActivity }\n',
        packageName: 'com.mknoon.app',
      ),
      isFalse,
    );
    expect(
      intro_campaign.isAndroidActivityStartProvisionallyAccepted(
        'Starting: Intent { act=android.intent.action.MAIN }\n',
        packageName: 'com.mknoon.app',
      ),
      isFalse,
    );

    final source = File(
      'integration_test/scripts/run_intro_accept_notification_android.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _launchAll()');
    final end = source.indexOf('Future<void> _collectIdentities()', start);
    final launch = source.substring(start, end);
    expect(launch, contains('propagateTimeout: true'));
    expect(launch, contains('on IntroCommandTimedOut catch (error)'));
    expect(
      launch,
      contains('runAndroidActivityLaunchWithSingleProcessRecovery('),
    );
    expect(launch, contains("['pidof', _appPackage]"));
    expect(launch, isNot(contains('maximumAttempts:')));
  });

  test('launch recovery is single, causal, and bounded', () async {
    final calls = <bool>[];
    var pidReads = 0;
    final recovered = await intro_campaign
        .runAndroidActivityLaunchWithSingleProcessRecovery(
          launch: (waitForLaunch) async {
            calls.add(waitForLaunch);
            if (waitForLaunch) {
              throw const intro_campaign.IntroCommandTimedOut(
                'host wait timed out',
                stdout:
                    'Starting: Intent { cmp=com.mknoon.app/.MainActivity }\n',
              );
            }
            return 'Starting: Intent { cmp=com.mknoon.app/.MainActivity }\n';
          },
          readProcessId: () async {
            pidReads += 1;
            return '';
          },
          packageName: 'com.mknoon.app',
        );

    expect(recovered, isTrue);
    expect(calls, <bool>[true, false]);
    expect(pidReads, 1);

    calls.clear();
    final liveProcess = await intro_campaign
        .runAndroidActivityLaunchWithSingleProcessRecovery(
          launch: (waitForLaunch) async {
            calls.add(waitForLaunch);
            throw const intro_campaign.IntroCommandTimedOut(
              'host wait timed out',
              stdout: 'Starting: Intent { cmp=com.mknoon.app/.MainActivity }\n',
            );
          },
          readProcessId: () async => '4321',
          packageName: 'com.mknoon.app',
        );

    expect(liveProcess, isTrue);
    expect(calls, <bool>[
      true,
    ], reason: 'a live process must not be relaunched');
  });

  test(
    'launch recovery rejects unrelated handoffs and never retries twice',
    () async {
      var calls = 0;
      Future<String> timedOutLaunch(bool waitForLaunch) async {
        calls += 1;
        throw const intro_campaign.IntroCommandTimedOut(
          'host wait timed out',
          stdout: 'Starting: Intent { cmp=com.mknoon.app/.MainActivity }\n',
        );
      }

      await expectLater(
        intro_campaign.runAndroidActivityLaunchWithSingleProcessRecovery(
          launch: timedOutLaunch,
          readProcessId: () async => '',
          packageName: 'com.mknoon.app',
        ),
        throwsA(isA<intro_campaign.IntroCommandTimedOut>()),
      );
      expect(calls, 2);

      calls = 0;
      await expectLater(
        intro_campaign.runAndroidActivityLaunchWithSingleProcessRecovery(
          launch: (waitForLaunch) async {
            calls += 1;
            throw const intro_campaign.IntroCommandTimedOut(
              'wrong component',
              stdout: 'Starting: Intent { cmp=com.other.app/.MainActivity }\n',
            );
          },
          readProcessId: () async => throw StateError('must not read pid'),
          packageName: 'com.mknoon.app',
        ),
        throwsA(isA<intro_campaign.IntroCommandTimedOut>()),
      );
      expect(calls, 1);
    },
  );

  test('waits for notification acceptance event', () {
    const stepId = '252-physical_introducer-b_accept';
    final genericHealthReplay = <String, dynamic>{
      'stepId': stepId,
      'status': 'complete',
      'success': true,
      'introAction': <String, dynamic>{'action': 'none', 'actedOn': <String>[]},
      'introDeliveryCustody': null,
    };
    final acceptance = <String, dynamic>{
      'stepId': stepId,
      'status': 'complete',
      'success': true,
      'introAction': <String, dynamic>{
        'action': 'accept_all',
        'actedOn': <String>['intro-1'],
      },
      'introDeliveryCustody': <String, dynamic>{
        'status': 'confirmed',
        'introductionCount': 1,
      },
    };

    expect(
      intro_campaign.isIntroAcceptanceResult(
        genericHealthReplay,
        stepId: stepId,
      ),
      isFalse,
    );
    expect(
      intro_campaign.isIntroAcceptanceResult(
        acceptance,
        stepId: '252-physical_introducer-c_accept',
      ),
      isFalse,
      reason: 'a late result from another acceptance leg is not causal proof',
    );
    expect(
      intro_campaign.isIntroAcceptanceResult(acceptance, stepId: stepId),
      isTrue,
    );
  });

  test('clears only exact stale acceptance cards before the second leg', () {
    const xml = '''
<hierarchy>
  <node text="Unrelated notification" bounds="[0,10][1080,110]" />
  <node text="Introduction accepted" bounds="[40,120][760,220]" />
  <node text="Introduction accepted" bounds="[40,230][760,330]" />
</hierarchy>
''';

    expect(
      intro_campaign.exactNotificationTitleNodeBounds(
        xml,
        'Introduction accepted',
      ),
      <({int bottom, int left, int right, int top})>[
        (left: 40, top: 120, right: 760, bottom: 220),
        (left: 40, top: 230, right: 760, bottom: 330),
      ],
    );

    final runner = File(
      'integration_test/scripts/run_intro_accept_notification_android.dart',
    ).readAsStringSync();
    final firstLeg = runner.indexOf("legLabel: 'b_accept'");
    final secondLeg = runner.indexOf("legLabel: 'c_accept'");
    final exactDismissal = runner.indexOf(
      'await _dismissExactAcceptanceCards();',
      firstLeg,
    );

    expect(firstLeg, greaterThanOrEqualTo(0));
    expect(exactDismissal, greaterThan(firstLeg));
    expect(exactDismissal, lessThan(secondLeg));
    expect(
      runner,
      isNot(contains('cancelAllNotifications')),
      reason: 'the harness must not clear unrelated owner notifications',
    );
  });

  test('late-event cleanup is idempotent', () async {
    final releaseCleanup = Completer<void>();
    final cleanup = intro_campaign.IntroLateEventCleanup();
    var calls = 0;

    final first = cleanup.run(() {
      calls += 1;
      return releaseCleanup.future;
    });
    final second = cleanup.run(() {
      calls += 1;
      return Future<void>.value();
    });

    expect(calls, 1);
    expect(identical(first, second), isTrue);

    releaseCleanup.complete();
    await Future.wait<void>(<Future<void>>[first, second]);
    await cleanup.run(() {
      calls += 1;
      return Future<void>.value();
    });

    expect(calls, 1);
  });

  test('timed-out child is terminated before cleanup continues', () async {
    final child = _FakeIntroChildProcess();
    final supervisor = intro_sims.IntroChildSupervisor(child);

    await expectLater(
      supervisor.waitUntil(
        DateTime.now().add(const Duration(milliseconds: 10)),
        terminationGrace: const Duration(milliseconds: 5),
      ),
      throwsA(isA<TimeoutException>()),
    );

    expect(child.signals, <ProcessSignal>[
      ProcessSignal.sigterm,
      ProcessSignal.sigkill,
    ]);

    await supervisor.terminate(
      terminationGrace: const Duration(milliseconds: 5),
    );
    expect(
      child.signals,
      <ProcessSignal>[ProcessSignal.sigterm, ProcessSignal.sigkill],
      reason: 'late/finally cleanup must not signal the child twice',
    );
  });

  test('acceptance and cleanup guards are wired into both runners', () {
    final runner = File(
      'integration_test/scripts/run_intro_accept_notification_android.dart',
    ).readAsStringSync();
    final adapter = File(
      'integration_test/scripts/run_intro_accept_notification_sims.dart',
    ).readAsStringSync();
    final resultWaitStart = runner.indexOf(
      'Future<Map<String, dynamic>> _writeConfigAndAwait(',
    );
    final resultWaitEnd = runner.indexOf(
      'Future<String?> _readAppDocumentsFile(',
      resultWaitStart,
    );
    final resultWait = runner.substring(resultWaitStart, resultWaitEnd);

    expect(resultWait, contains('isIntroAcceptanceResult('));
    expect(resultWait, contains('requiresAcceptance'));
    expect(runner, contains('await _cleanupAfterLateEvents();'));
    expect(runner, contains('await _terminateStartedProcess(process);'));
    expect(
      runner.indexOf('await _cleanupAfterLateEvents();'),
      lessThan(runner.indexOf('await directStateGuard?.restoreAll();')),
    );
    expect(adapter, contains('await activeChild?.terminate();'));
    expect(
      adapter.indexOf('await activeChild?.terminate();'),
      lessThan(adapter.indexOf('await stateGuard.restoreAll();')),
    );
  });

  test(
    'generic intro commands are consumed before any host-visible receipt',
    () {
      final source = File(
        'lib/core/debug/intro_e2e_runner.dart',
      ).readAsStringSync();
      final actionStart = source.indexOf('Future<void> runIntroE2EActions({');
      final actionEnd = source.indexOf(
        'Future<void> _runConnectivityRestoreObservation({',
        actionStart,
      );
      final action = source.substring(actionStart, actionEnd);
      final consumeIndex = action.indexOf('await _deleteConfigIfPresent();');
      final runningReceiptIndex = action.indexOf("'status': 'running'");

      expect(actionStart, isNonNegative);
      expect(actionEnd, greaterThan(actionStart));
      expect(consumeIndex, isNonNegative);
      expect(
        consumeIndex,
        lessThan(runningReceiptIndex),
        reason:
            'the host stages the next command after a terminal receipt, so the '
            'current command must be consumed before any receipt is published',
      );
      expect(
        RegExp(r'await _deleteConfigIfPresent\(\);').allMatches(action).length,
        1,
        reason: 'trailing cleanup could delete the next staged command',
      );
    },
  );

  test('consumed generic commands retain their loaded contact fixture', () {
    final source = File(
      'lib/core/debug/intro_e2e_runner.dart',
    ).readAsStringSync();
    final helperStart = source.indexOf(
      'Future<bool> prePopulateContactsFromIntroE2EConfig({',
    );
    final actionStart = source.indexOf(
      'Future<void> runIntroE2EActions({',
      helperStart,
    );
    final actionEnd = source.indexOf(
      'Future<void> _runConnectivityRestoreObservation({',
      actionStart,
    );
    final helper = source.substring(helperStart, actionStart);
    final action = source.substring(actionStart, actionEnd);

    expect(helper, contains('Map<String, dynamic>? configOverride'));
    expect(helper, contains('configOverride ?? await _loadConfig()'));
    expect(action, contains('configOverride: config'));
  });

  test('a no-op introduction action returns before inbox polling', () {
    final source = File(
      'lib/core/debug/intro_e2e_runner.dart',
    ).readAsStringSync();
    final actionStart = source.indexOf(
      'Future<Map<String, dynamic>> _runIntroductionAction({',
    );
    final actionEnd = source.indexOf(
      'Future<Map<String, dynamic>> awaitIntroducerAcceptanceCustodyForIntroE2E',
      actionStart,
    );
    final action = source.substring(actionStart, actionEnd);
    final noOpReturn = action.indexOf("if (action == 'none')");
    final identityLoad = action.indexOf('identityRepo.loadIdentity()');
    final pollLoop = action.indexOf(
      'for (var tick = 0; tick < pollCycles; tick++)',
    );

    expect(noOpReturn, isNonNegative);
    expect(noOpReturn, lessThan(identityLoad));
    expect(noOpReturn, lessThan(pollLoop));
  });

  test('contact-request pacing never delays terminal completion', () {
    expect(
      intro_runner.shouldDelayBetweenIntroE2EContactRequests(
        contactIndex: 0,
        contactCount: 2,
      ),
      isTrue,
    );
    expect(
      intro_runner.shouldDelayBetweenIntroE2EContactRequests(
        contactIndex: 1,
        contactCount: 2,
      ),
      isFalse,
    );
    expect(
      intro_runner.shouldDelayBetweenIntroE2EContactRequests(
        contactIndex: 0,
        contactCount: 1,
      ),
      isFalse,
    );
  });

  test(
    'exact call-wake contact setup retries beyond legacy attempts until an exact success',
    () async {
      var now = DateTime.utc(2026, 1, 1);
      var attempts = 0;
      final exactReceiptRequirements = <bool>[];
      final retryDelays = <Duration>[];

      final result = await intro_runner.retryIntroE2EContactRequest(
        requireExactCallWakeReceipt: true,
        sendAttempt: ({required requireExactCallWakeReceipt}) async {
          attempts++;
          exactReceiptRequirements.add(requireExactCallWakeReceipt);
          return attempts == 9
              ? contact_request.SendContactRequestResult.success
              : contact_request.SendContactRequestResult.sendFailed;
        },
        now: () => now,
        delay: (duration) async {
          retryDelays.add(duration);
          now = now.add(duration);
        },
      );

      expect(result, contact_request.SendContactRequestResult.success);
      expect(attempts, 9);
      expect(exactReceiptRequirements, everyElement(isTrue));
      expect(retryDelays, hasLength(8));
      expect(retryDelays, everyElement(const Duration(seconds: 2)));
    },
  );

  test(
    'exact call-wake contact setup stops at its bounded retry window',
    () async {
      var now = DateTime.utc(2026, 1, 1);
      var attempts = 0;

      final result = await intro_runner.retryIntroE2EContactRequest(
        requireExactCallWakeReceipt: true,
        sendAttempt: ({required requireExactCallWakeReceipt}) async {
          attempts++;
          expect(requireExactCallWakeReceipt, isTrue);
          return contact_request.SendContactRequestResult.sendFailed;
        },
        now: () => now,
        delay: (duration) async => now = now.add(duration),
      );

      expect(result, contact_request.SendContactRequestResult.sendFailed);
      expect(
        attempts,
        60,
        reason: 'a two-second cadence receives a bounded 120-second window',
      );
    },
  );

  test('ordinary contact setup remains bounded to eight attempts', () async {
    var attempts = 0;
    final exactReceiptRequirements = <bool>[];

    final result = await intro_runner.retryIntroE2EContactRequest(
      requireExactCallWakeReceipt: false,
      sendAttempt: ({required requireExactCallWakeReceipt}) async {
        attempts++;
        exactReceiptRequirements.add(requireExactCallWakeReceipt);
        return contact_request.SendContactRequestResult.sendFailed;
      },
      delay: (_) async {},
    );

    expect(result, contact_request.SendContactRequestResult.sendFailed);
    expect(attempts, 8);
    expect(exactReceiptRequirements, everyElement(isFalse));
  });

  test(
    'added-contact requests carry optional call-wake callbacks and opt in to exact receipts',
    () {
      final source = File(
        'lib/core/debug/intro_e2e_runner.dart',
      ).readAsStringSync();
      final actionStart = source.indexOf('Future<void> runIntroE2EActions({');
      final actionEnd = source.indexOf(
        'Future<void> _runConnectivityRestoreObservation({',
        actionStart,
      );
      final pollerStart = source.indexOf('void startIntroE2EPoller({');
      final pollerEnd = source.indexOf(
        'Future<Map<String, dynamic>?> _openConversationIfRequested({',
        pollerStart,
      );
      final helperStart = source.indexOf(
        'Future<void> _sendContactRequestsForAddedContacts({',
      );
      final helperEnd = source.indexOf(
        'bool shouldDelayBetweenIntroE2EContactRequests',
        helperStart,
      );
      final action = source.substring(actionStart, actionEnd);
      final poller = source.substring(pollerStart, pollerEnd);
      final helper = source.substring(helperStart, helperEnd);

      for (final callback in const [
        'ResolveCallWakeHandleForIntroE2EFn? resolveCallWakeHandle',
        'OnCallWakeHandleDistributedForIntroE2EFn? onCallWakeHandleDistributed',
      ]) {
        expect(action, contains(callback));
        expect(poller, contains(callback));
        expect(helper, contains(callback));
      }
      expect(action, contains('resolveCallWakeHandle: resolveCallWakeHandle,'));
      expect(
        action,
        contains('onCallWakeHandleDistributed: onCallWakeHandleDistributed,'),
      );
      expect(poller, contains('resolveCallWakeHandle: resolveCallWakeHandle,'));
      expect(
        poller,
        contains('onCallWakeHandleDistributed: onCallWakeHandleDistributed,'),
      );
      expect(helper, contains('resolveCallWakeHandle: resolveCallWakeHandle,'));
      expect(
        helper,
        contains('onCallWakeHandleDistributed: onCallWakeHandleDistributed,'),
      );
      expect(
        helper,
        contains("config['require_exact_call_wake_receipt'] == true"),
        reason: 'only an explicit config boolean may require receipt proof',
      );
      expect(
        helper,
        contains('requireExactCallWakeReceipt: requireExactCallWakeReceipt,'),
      );
    },
  );

  test('contact setup skips the non-causal full database snapshot', () {
    final source = File(
      'integration_test/scripts/run_intro_accept_notification_android.dart',
    ).readAsStringSync();
    final setupStart = source.indexOf('Future<void> _setupContacts() async');
    final setupEnd = source.indexOf(
      'Future<void> _sendIntroduction() async',
      setupStart,
    );
    final setup = source.substring(setupStart, setupEnd);

    expect(setup, contains("'skip_snapshot': true"));
    expect(setup, isNot(contains("'contact_settle_delay_ms'")));
  });

  test('a stalled intro inbox drain releases its bounded poll', () async {
    final neverCompletes = Completer<void>();

    final completed = await intro_runner.awaitIntroE2EDrainWithin(
      drain: () => neverCompletes.future,
      timeout: const Duration(milliseconds: 10),
    );

    expect(completed, isFalse);
  });

  test('a completed intro inbox drain remains authoritative', () async {
    final completed = await intro_runner.awaitIntroE2EDrainWithin(
      drain: () async {},
      timeout: const Duration(milliseconds: 10),
    );

    expect(completed, isTrue);
  });

  test(
    'a coalesced intro health check cannot consume the fixture phase',
    () async {
      final neverCompletes = Completer<void>();

      final completed = await intro_runner.awaitIntroE2EHealthCheckWithin(
        healthCheck: () => neverCompletes.future,
        timeout: const Duration(milliseconds: 10),
      );

      expect(completed, isFalse);
    },
  );

  test('a completed intro health check remains authoritative', () async {
    final completed = await intro_runner.awaitIntroE2EHealthCheckWithin(
      healthCheck: () async {},
      timeout: const Duration(milliseconds: 10),
    );

    expect(completed, isTrue);

    final source = File(
      'lib/core/debug/intro_e2e_runner.dart',
    ).readAsStringSync();
    final actionStart = source.indexOf('Future<void> runIntroE2EActions({');
    final actionEnd = source.indexOf(
      'Future<void> _runConnectivityRestoreObservation({',
      actionStart,
    );
    final action = source.substring(actionStart, actionEnd);
    expect(action, contains('_performImmediateHealthCheckForIntroE2E('));
    expect(
      action,
      isNot(contains('await p2pService.performImmediateHealthCheck();')),
    );
  });

  test('already acted pending introductions count as idle', () {
    expect(
      intro_runner.hasUnactedIntroE2EIntroduction(
        pendingIntroductionIds: const <String>['intro-1'],
        actedOnIntroductionIds: const <String>['intro-1'],
      ),
      isFalse,
    );
    expect(
      intro_runner.hasUnactedIntroE2EIntroduction(
        pendingIntroductionIds: const <String>['intro-1', 'intro-2'],
        actedOnIntroductionIds: const <String>['intro-1'],
      ),
      isTrue,
    );
  });

  test('acceptance campaign needs one idle poll after its exact intro', () {
    final source = File(
      'integration_test/scripts/run_intro_accept_notification_android.dart',
    ).readAsStringSync();
    final actionStart = source.indexOf(
      'final response = await _writeConfigAndAwait(responder',
    );
    final actionEnd = source.indexOf(
      "final custody = response['introDeliveryCustody'];",
      actionStart,
    );

    expect(actionStart, isNonNegative);
    expect(actionEnd, greaterThan(actionStart));
    expect(
      source.substring(actionStart, actionEnd),
      contains("'idle_cycles_after_seen': 1"),
    );
  });

  test('idempotent intro reads retry only bounded command timeouts', () async {
    var attempts = 0;
    final value = await intro_campaign
        .runIntroIdempotentCommandWithRetries<String>(
          command: () async {
            attempts += 1;
            if (attempts < 3) {
              throw const intro_campaign.IntroCommandTimedOut('wedged adb');
            }
            return 'complete';
          },
          maximumAttempts: 3,
          retryDelay: Duration.zero,
        );

    expect(value, 'complete');
    expect(attempts, 3);

    attempts = 0;
    await expectLater(
      intro_campaign.runIntroIdempotentCommandWithRetries<String>(
        command: () async {
          attempts += 1;
          throw StateError('not retryable');
        },
        maximumAttempts: 3,
        retryDelay: Duration.zero,
      ),
      throwsStateError,
    );
    expect(attempts, 1);
  });

  test('intro result reads survive a bounded ADB transport stall', () {
    expect(
      intro_campaign.introAppDocumentReadCommandCeiling,
      const Duration(seconds: 5),
    );
    expect(intro_campaign.introAppDocumentReadTimeoutAttempts, 12);

    final source = File(
      'integration_test/scripts/run_intro_accept_notification_android.dart',
    ).readAsStringSync();
    final helperStart = source.indexOf(
      'Future<String?> _readAppDocumentsFile(',
    );
    final helperEnd = source.indexOf(
      'Future<void> _writeAppDocumentsFile(',
      helperStart,
    );
    final helper = source.substring(helperStart, helperEnd);

    expect(helper, contains('introAppDocumentReadCommandCeiling'));
    expect(helper, contains('introAppDocumentReadTimeoutAttempts'));
  });

  test('fixture receipt failures identify the exact step and party', () {
    expect(
      intro_campaign.introStepReceiptFailureDetail(
        stepId: '252-emulator_introducer-b-accept-contacts',
        partyRole: 'B',
        detail: 'intro campaign deadline expired during fixture',
      ),
      'step 252-emulator_introducer-b-accept-contacts on B did not produce '
      'a receipt: intro campaign deadline expired during fixture',
    );

    final source = File(
      'integration_test/scripts/run_intro_accept_notification_android.dart',
    ).readAsStringSync();
    final helperStart = source.indexOf(
      'Future<Map<String, dynamic>> _writeConfigAndAwait(',
    );
    final helperEnd = source.indexOf(
      'Future<String?> _readAppDocumentsFile(',
      helperStart,
    );
    final helper = source.substring(helperStart, helperEnd);

    expect(helper, contains('introStepReceiptFailureDetail('));
  });

  test('UIAutomator hierarchy reads use bounded idempotent retries', () {
    final source = File(
      'integration_test/scripts/run_intro_accept_notification_android.dart',
    ).readAsStringSync();
    final helperStart = source.indexOf('Future<String> _uiautomatorDump()');
    final helperEnd = source.indexOf(
      '({int left, int top, int right, int bottom})? _boundsForExactTitleNode',
      helperStart,
    );
    final helper = source.substring(helperStart, helperEnd);

    expect(helper, contains("['uiautomator', 'dump', remotePath]"));
    expect(RegExp(r'timeoutAttempts: 3').allMatches(helper), hasLength(2));
    expect(
      RegExp(
        r'commandCeiling: const Duration\(seconds: 15\)',
      ).allMatches(helper),
      hasLength(2),
    );
  });

  test('notification arrival polling does not require a UI hierarchy', () {
    final source = File(
      'integration_test/scripts/run_intro_accept_notification_android.dart',
    ).readAsStringSync();
    final helperStart = source.indexOf(
      'Future<List<String>> _notificationTitlesOnA()',
    );
    final helperEnd = source.indexOf(
      'Future<({String title, String body})> _extractAcceptanceCopy()',
      helperStart,
    );
    final helper = source.substring(helperStart, helperEnd);

    expect(helper, contains("'dumpsys',\n      'notification'"));
    expect(helper, contains('return titles;'));
    expect(helper, isNot(contains('_uiautomatorDump()')));
  });
}

final class _FakeIntroChildProcess implements intro_sims.IntroChildProcess {
  final Completer<int> _exit = Completer<int>();
  final List<ProcessSignal> signals = <ProcessSignal>[];

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill(ProcessSignal signal) {
    signals.add(signal);
    if (signal == ProcessSignal.sigkill && !_exit.isCompleted) {
      _exit.complete(-9);
    }
    return true;
  }
}
