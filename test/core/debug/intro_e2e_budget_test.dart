import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/scripts/run_intro_accept_notification_android.dart'
    as intro_campaign;

void main() {
  test('allocates budget by phase', () {
    var now = DateTime.utc(2026, 7, 27, 12);
    final deadline = intro_campaign.IntroCampaignDeadline(
      campaignDeadline: now.add(const Duration(minutes: 10)),
      now: () => now,
    );

    deadline.beginPhase('fixture', const Duration(minutes: 3));
    now = now.add(const Duration(minutes: 2));
    expect(deadline.remaining(), const Duration(minutes: 1));

    deadline.beginPhase('b_accept', const Duration(minutes: 4));
    expect(deadline.remaining(), const Duration(minutes: 4));

    now = now.add(const Duration(minutes: 1));
    expect(
      deadline.remaining(ceiling: const Duration(minutes: 6)),
      const Duration(minutes: 3),
      reason: 'a second wait in one phase must not receive a fresh budget',
    );

    now = now.add(const Duration(minutes: 3));
    expect(deadline.remaining(), Duration.zero);
    expect(deadline.phaseName, 'b_accept');
  });

  test('campaign deadline clamps a later phase allocation', () {
    var now = DateTime.utc(2026, 7, 27, 12);
    final deadline = intro_campaign.IntroCampaignDeadline(
      campaignDeadline: now.add(const Duration(minutes: 5)),
      now: () => now,
    );

    now = now.add(const Duration(minutes: 4));
    deadline.beginPhase('c_accept', const Duration(minutes: 6));

    expect(deadline.remaining(), const Duration(minutes: 1));
  });

  test('runner and adapter share one absolute campaign deadline', () {
    final runner = File(
      'integration_test/scripts/run_intro_accept_notification_android.dart',
    ).readAsStringSync();
    final adapter = File(
      'integration_test/scripts/run_intro_accept_notification_sims.dart',
    ).readAsStringSync();

    expect(runner, contains("await _runPhase('fixture'"));
    expect(runner, contains("'b_accept',\n        _acceptanceBudget"));
    expect(runner, contains("'c_accept',\n        _acceptanceBudget"));
    expect(runner, contains('deadline.remaining(),'));
    expect(runner, isNot(contains('Duration(seconds: 240)')));
    expect(runner, isNot(contains('Duration(seconds: 360)')));

    expect(adapter, contains("'--campaign-deadline-epoch-ms'"));
    expect(
      adapter,
      contains('activeChild.waitUntil(scenarioDeadline)'),
      reason: 'the adapter must supervise the deadline passed to the runner',
    );
  });
}
