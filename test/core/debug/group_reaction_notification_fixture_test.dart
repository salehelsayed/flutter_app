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
