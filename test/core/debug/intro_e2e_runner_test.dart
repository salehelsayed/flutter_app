import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/scripts/run_intro_accept_notification_android.dart'
    as intro_campaign;
import '../../../integration_test/scripts/run_intro_accept_notification_sims.dart'
    as intro_sims;

void main() {
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
