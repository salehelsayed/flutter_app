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

  test('introduction send receives a fresh bounded phase after contacts', () {
    var now = DateTime.utc(2026, 7, 27, 12);
    final deadline = intro_campaign.IntroCampaignDeadline(
      campaignDeadline: now.add(const Duration(minutes: 24)),
      now: () => now,
    );

    deadline.beginPhase('fixture_contacts', const Duration(minutes: 7));
    now = now.add(const Duration(minutes: 6, seconds: 50));
    expect(deadline.remaining(), const Duration(seconds: 10));

    deadline.beginPhase('fixture_introduction', const Duration(minutes: 4));
    expect(deadline.remaining(), const Duration(minutes: 4));

    final source = File(
      'integration_test/scripts/run_intro_accept_notification_android.dart',
    ).readAsStringSync();
    final contactsPhase = source.indexOf("'fixture_contacts'");
    final contactsAction = source.indexOf('_setupContacts,', contactsPhase);
    final introductionPhase = source.indexOf(
      "'fixture_introduction'",
      contactsAction,
    );
    final introductionAction = source.indexOf(
      '_sendIntroduction,',
      introductionPhase,
    );
    expect(contactsPhase, greaterThan(0));
    expect(contactsAction, greaterThan(contactsPhase));
    expect(introductionPhase, greaterThan(contactsAction));
    expect(introductionAction, greaterThan(introductionPhase));
    expect(source, contains('_contactFixtureBudget = Duration(minutes: 7)'));
    expect(
      source,
      contains('_introductionFixtureBudget = Duration(minutes: 4)'),
    );
    expect(
      source,
      isNot(contains("await _runPhase('fixture',")),
      reason: 'one slow contact setup must not consume the send receipt cap',
    );
  });

  test('redirect observation uses the existing acceptance phase budget', () {
    final source = File(
      'integration_test/scripts/run_intro_accept_notification_android.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<({String finalPeer, String statusContext})> '
      '_waitForRedirectMarker(',
    );
    final end = source.indexOf(
      'Future<void> _assertNoNavigationErrors()',
      start,
    );

    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final method = source.substring(start, end);
    expect(method, contains('final waitBudget = deadline.remaining();'));
    expect(
      method,
      isNot(contains('ceiling:')),
      reason: 'a nested tap timeout must not truncate the bounded phase',
    );
  });

  test('runner and adapter share one absolute campaign deadline', () {
    final runner = File(
      'integration_test/scripts/run_intro_accept_notification_android.dart',
    ).readAsStringSync();
    final adapter = File(
      'integration_test/scripts/run_intro_accept_notification_sims.dart',
    ).readAsStringSync();

    expect(runner, contains("'fixture_contacts'"));
    expect(runner, contains("'fixture_introduction'"));
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
