import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/scripts/capture_group_reaction_notification_device.dart'
    as fixture_driver;

void main() {
  test('bounded fixture read retries a transient adb reconnect', () async {
    final results = <int>[255, 255, 0];
    var attempts = 0;

    final result = await fixture_driver.retryBoundedFixtureRead<int>(
      attempt: () async => results[attempts++],
      succeeded: (value) => value == 0,
      maximumAttempts: 3,
      retryDelay: Duration.zero,
    );

    expect(result, 0);
    expect(attempts, 3);
  });

  test('bounded fixture read returns the final classified failure', () async {
    var attempts = 0;

    final result = await fixture_driver.retryBoundedFixtureRead<int>(
      attempt: () async {
        attempts += 1;
        return 255;
      },
      succeeded: (value) => value == 0,
      maximumAttempts: 2,
      retryDelay: Duration.zero,
    );

    expect(result, 255);
    expect(attempts, 2);
  });

  test(
    'creator readiness accepts only the current-process sendable event',
    () async {
      final observations = <String>[
        '[FLOW] {"event":"P2P_STATE_CHANGED"}',
        '[FLOW] {"event":"TIME_TO_SENDABLE_BADGE","phase":"cold_start"}',
      ];
      var reads = 0;

      final ready = await fixture_driver.waitForCreatorSendableReadiness(
        readCurrentProcessLog: () async => observations[reads++],
        maximumPolls: 3,
        pollInterval: Duration.zero,
      );

      expect(ready, isTrue);
      expect(reads, 2);
    },
  );

  test(
    'creator readiness times out without treating nearby text as ready',
    () async {
      var reads = 0;

      final ready = await fixture_driver.waitForCreatorSendableReadiness(
        readCurrentProcessLog: () async {
          reads += 1;
          return 'diagnostic mentions TIME_TO_SENDABLE_BADGE without an event';
        },
        maximumPolls: 3,
        pollInterval: Duration.zero,
      );

      expect(ready, isFalse);
      expect(reads, 3);
    },
  );

  test(
    'group fixture waits for a newly completed recovery pass before create',
    () async {
      const completed = '[FLOW] {"event":"GROUP_DRAIN_OFFLINE_INBOX_TIMING"}';
      final observations = <String>[
        completed,
        completed,
        '$completed\n$completed',
      ];
      var reads = 0;

      final ready = await fixture_driver
          .waitForCreatorGroupRecoveryQuiescentWindow(
            readCurrentProcessLog: () async => observations[reads++],
            maximumPolls: 3,
            pollInterval: Duration.zero,
            settleDelay: Duration.zero,
          );

      expect(ready, isTrue);
      expect(reads, 3);
    },
  );

  test(
    'group fixture recovery wait rejects stale and diagnostic-only text',
    () async {
      var reads = 0;

      final ready = await fixture_driver
          .waitForCreatorGroupRecoveryQuiescentWindow(
            readCurrentProcessLog: () async {
              reads += 1;
              return reads == 1
                  ? '[FLOW] {"event":"GROUP_DRAIN_OFFLINE_INBOX_TIMING"}'
                  : 'diagnostic GROUP_DRAIN_OFFLINE_INBOX_TIMING';
            },
            maximumPolls: 2,
            pollInterval: Duration.zero,
            settleDelay: Duration.zero,
          );

      expect(ready, isFalse);
      expect(reads, 3);
    },
  );

  test(
    'invite wait discriminates an empty review from a pending invite',
    () async {
      final dumps = <String>[
        _node(contentDescription: 'Open introductions review'),
        _node(contentDescription: 'Open introductions review, 1 new'),
        _node(text: 'Pending Group Invites'),
      ];
      var reads = 0;
      final openedReviewLabels = <String>[];

      final observed = await fixture_driver.waitForPendingGroupInviteProjection(
        groupName: 'TC292Group',
        readUiDump: () async => dumps[reads++],
        openReview: (label) async => openedReviewLabels.add(label),
        reestablishOrbit: () async {
          fail('bounded recovery is not needed once the invite is projected');
        },
        maximumPolls: 3,
        recoveryPoll: 3,
        pollInterval: Duration.zero,
      );

      expect(observed, 'Pending Group Invites');
      expect(reads, 3);
      expect(openedReviewLabels, ['Open introductions review, 1 new']);
    },
  );

  test('invite wait keeps an empty review pending through its bound', () async {
    var recoveries = 0;

    final observed = await fixture_driver.waitForPendingGroupInviteProjection(
      groupName: 'TC292Group',
      readUiDump: () async =>
          _node(contentDescription: 'Open introductions review'),
      openReview: (_) async => fail('an empty review must not be opened'),
      reestablishOrbit: () async => recoveries += 1,
      maximumPolls: 4,
      recoveryPoll: 2,
      pollInterval: Duration.zero,
    );

    expect(observed, isNull);
    expect(recoveries, 1);
  });

  test(
    'Plan 330 group lookup leaves the Intros filter for Inner Circle',
    () async {
      var dump =
          _node(contentDescription: 'Show inner circle') +
          _node(text: 'Pending Group Invites');
      final taps = <(int, int)>[];

      final center = await fixture_driver
          .findPlan330OrbitGroupWithInnerCircleRecovery(
            groupName: 'Plan330A-fixture',
            readUiDump: () async => dump,
            tapSemanticNode: (value) async {
              taps.add(value);
              dump =
                  _node(contentDescription: 'Show all chats') +
                  _node(contentDescription: 'Open group Plan330A-fixture');
            },
            retryDelay: Duration.zero,
          );

      expect(center, (50, 50));
      expect(taps, [(50, 50)]);
    },
  );

  test(
    'Plan 330 group lookup keeps an existing Inner Circle surface',
    () async {
      final dump =
          _node(contentDescription: 'Show all chats') +
          _node(contentDescription: 'Open group Plan330A-fixture');
      var taps = 0;

      final center = await fixture_driver
          .findPlan330OrbitGroupWithInnerCircleRecovery(
            groupName: 'Plan330A-fixture',
            readUiDump: () async => dump,
            tapSemanticNode: (_) async => taps += 1,
            retryDelay: Duration.zero,
          );

      expect(center, (50, 50));
      expect(taps, 0);
    },
  );

  test(
    'Plan 330 group lookup falls back to All Chats when Inner Circle omits it',
    () async {
      var surface = 0;
      final taps = <(int, int)>[];

      final center = await fixture_driver
          .findPlan330OrbitGroupWithInnerCircleRecovery(
            groupName: 'Plan330A-fixture',
            readUiDump: () async => switch (surface) {
              0 =>
                _node(contentDescription: 'Show inner circle') +
                    _node(contentDescription: 'Open group Plan330A-fixture'),
              1 => _node(contentDescription: 'Show all chats'),
              _ =>
                _node(contentDescription: 'Show inner circle') +
                    _node(contentDescription: 'Open group Plan330A-fixture'),
            },
            tapSemanticNode: (value) async {
              taps.add(value);
              surface += 1;
            },
            maximumInnerCirclePolls: 1,
            retryDelay: Duration.zero,
          );

      expect(center, (50, 50));
      expect(taps, [(50, 50), (50, 50)]);
    },
  );

  test(
    'Plan 330 Inner Circle recovery retries two intercepted toggles',
    () async {
      var dump = _node(contentDescription: 'Show inner circle');
      var taps = 0;

      final center = await fixture_driver
          .findPlan330OrbitGroupWithInnerCircleRecovery(
            groupName: 'Plan330A-fixture',
            readUiDump: () async => dump,
            tapSemanticNode: (_) async {
              taps += 1;
              if (taps == 3) {
                dump =
                    _node(contentDescription: 'Show all chats') +
                    _node(contentDescription: 'Open group Plan330A-fixture');
              }
            },
            retryDelay: Duration.zero,
          );

      expect(center, (50, 50));
      expect(taps, 3);
    },
  );

  test('Plan 330 group lookup never taps unrelated Orbit semantics', () async {
    var taps = 0;

    final center = await fixture_driver
        .findPlan330OrbitGroupWithInnerCircleRecovery(
          groupName: 'Plan330A-fixture',
          readUiDump: () async =>
              _node(contentDescription: 'Open group unrelated'),
          tapSemanticNode: (_) async => taps += 1,
          maximumPolls: 2,
          retryDelay: Duration.zero,
        );

    expect(center, isNull);
    expect(taps, 0);
  });

  test(
    'transient fixture cleanup is idempotent and attempts every action',
    () async {
      final calls = <String>[];
      final cleanup =
          fixture_driver.GroupFixtureTransientCleanup(<Future<void> Function()>[
            () async => calls.add('config'),
            () async => calls.add('result'),
            () async => calls.add('statusbar'),
            () async => calls.add('pending-proof'),
          ]);

      await cleanup.run();
      await cleanup.run();

      expect(calls, ['config', 'result', 'statusbar', 'pending-proof']);
      expect(cleanup.completed, isTrue);
    },
  );

  test('outer campaign retains authoritative app-state cleanup in finally', () {
    final source = File(
      'integration_test/scripts/run_group_reaction_notification_sims.dart',
    ).readAsStringSync();
    final finallyIndex = source.indexOf('} finally {');
    final restoreIndex = source.indexOf('await stateGuard.restoreAll();');

    expect(finallyIndex, greaterThanOrEqualTo(0));
    expect(restoreIndex, greaterThan(finallyIndex));
  });
}

String _node({String text = '', String contentDescription = ''}) =>
    '<node text="$text" content-desc="$contentDescription" '
    'bounds="[0,0][100,100]" />';
