import 'dart:async';

import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/features/groups/application/group_notification_display_retry_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TC-330-07 concurrent triggers coalesce and mid-pass work gets one follow-up',
    () async {
      final rows = <int>[1];
      final projected = <int>[];
      final completed = <int>[];
      final firstProjection = Completer<void>();
      final releaseFirst = Completer<void>();
      var loads = 0;

      late final GroupNotificationDisplayRetryCoordinator<int> coordinator;
      coordinator = GroupNotificationDisplayRetryCoordinator<int>(
        batchSize: 2,
        maxBatchesPerRun: 3,
        loadReady: ({required limit}) async {
          loads++;
          return rows.take(limit).toList(growable: false);
        },
        project: (row) async {
          projected.add(row);
          if (row == 1 && !firstProjection.isCompleted) {
            firstProjection.complete();
            await releaseFirst.future;
          }
          return const GroupNotificationDisplayProjectionResult.completed();
        },
        completeWithOutcome: (row, outcome) async {
          expect(outcome, isNull);
          completed.add(row);
          rows.remove(row);
        },
        retire: (_) async {},
        recordFailure: (_, _) async {},
      );

      final first = coordinator.retryNow();
      await firstProjection.future;
      rows.add(2);
      final concurrent = coordinator.retryNow();
      releaseFirst.complete();
      await Future.wait([first, concurrent]);

      expect(projected, [1, 2]);
      expect(completed, [1, 2]);
      expect(rows, isEmpty);
      expect(loads, inInclusiveRange(2, 3));
    },
  );

  test(
    'TC-330-07 errors and overflow remain durable for a later bounded trigger',
    () async {
      final rows = <int>[1, 2, 3, 4, 5];
      final failures = <int>[];
      var failTwo = true;
      var delayedRetries = 0;

      final coordinator = GroupNotificationDisplayRetryCoordinator<int>(
        batchSize: 2,
        maxBatchesPerRun: 2,
        loadReady: ({required limit}) async =>
            rows.take(limit).toList(growable: false),
        project: (row) async {
          if (row == 2 && failTwo) throw StateError('plugin unavailable');
          return const GroupNotificationDisplayProjectionResult.completed();
        },
        completeWithOutcome: (row, outcome) async {
          expect(outcome, isNull);
          rows.remove(row);
        },
        retire: (_) async {},
        recordFailure: (row, _) async => failures.add(row),
        scheduleRetry: (_) => delayedRetries++,
      );

      await coordinator.retryNow();
      expect(rows, containsAll(<int>[2, 5]));
      expect(failures, [2]);
      expect(delayedRetries, 1);

      failTwo = false;
      await coordinator.retryNow();
      expect(rows, isEmpty);
    },
  );

  test('TC-330-07 retryable disposition never completes custody', () async {
    final rows = <int>[7];
    var completed = false;
    var delayedRetries = 0;
    final coordinator = GroupNotificationDisplayRetryCoordinator<int>(
      loadReady: ({required limit}) async => rows,
      project: (_) async =>
          const GroupNotificationDisplayProjectionResult.retryLater(),
      completeWithOutcome: (_, _) async => completed = true,
      retire: (_) async {},
      recordFailure: (_, _) async {},
      scheduleRetry: (_) => delayedRetries++,
    );

    await coordinator.retryNow();

    expect(completed, isFalse);
    expect(rows, [7]);
    expect(delayedRetries, 1);
  });

  test(
    'dispose fences completion after an already in-flight projection',
    () async {
      final projectionStarted = Completer<void>();
      final releaseProjection = Completer<void>();
      var completions = 0;
      var failures = 0;
      final coordinator = GroupNotificationDisplayRetryCoordinator<int>(
        loadReady: ({required limit}) async => <int>[1],
        project: (_) async {
          projectionStarted.complete();
          await releaseProjection.future;
          return const GroupNotificationDisplayProjectionResult.completed();
        },
        completeWithOutcome: (_, _) async => completions++,
        retire: (_) async {},
        recordFailure: (_, _) async => failures++,
      );

      final retry = coordinator.retryNow();
      await projectionStarted.future;
      coordinator.dispose();
      releaseProjection.complete();
      await retry;

      expect(completions, 0);
      expect(failures, 0);
    },
  );

  test(
    'TC-330-P1 retryable oldest row does not starve later ready custody',
    () async {
      final now = DateTime.utc(2026, 8, 3, 13);
      final retryAt = now.add(const Duration(seconds: 37));
      final rowIds = <int>[1, 2];
      final projected = <int>[];
      final completed = <int>[];
      final failed = <int>[];
      final scheduled = <Duration>[];
      var loads = 0;

      final coordinator =
          GroupNotificationDisplayRetryCoordinator<_NotificationRetryRow>(
            nowUtc: () => now,
            batchSize: 1,
            maxBatchesPerRun: 3,
            loadReady: ({required limit}) async {
              loads++;
              return rowIds
                  .take(limit)
                  .map(_NotificationRetryRow.new)
                  .toList(growable: false);
            },
            entryIdentity: (row) => row.id,
            loadEarliestNextAttemptAt: () async => retryAt,
            project: (row) async {
              projected.add(row.id);
              return row.id == 1
                  ? const GroupNotificationDisplayProjectionResult.retryLater()
                  : const GroupNotificationDisplayProjectionResult.completed();
            },
            completeWithOutcome: (row, outcome) async {
              expect(outcome, isNull);
              completed.add(row.id);
              rowIds.remove(row.id);
            },
            retire: (_) async {},
            recordFailure: (row, _) async => failed.add(row.id),
            scheduleRetry: scheduled.add,
          );

      await coordinator.retryNow();

      expect(projected, [1, 2]);
      expect(completed, [2]);
      expect(failed, [1]);
      expect(rowIds, [1]);
      expect(scheduled, [const Duration(seconds: 37)]);
      expect(loads, 3);
    },
  );

  test(
    'TC-330-P1 restart arms the earliest durable due time and never projects early',
    () async {
      var now = DateTime.utc(2026, 8, 3, 12);
      final nextAttemptAt = now.add(const Duration(seconds: 41));
      final durableRows = <({int id, DateTime nextAttemptAt})>[
        (id: 9, nextAttemptAt: nextAttemptAt),
      ];
      final projected = <int>[];
      final scheduled = <Duration>[];

      // A fresh coordinator models process restart: only the durable row and
      // its persisted next-attempt timestamp survive.
      final restarted =
          GroupNotificationDisplayRetryCoordinator<
            ({int id, DateTime nextAttemptAt})
          >(
            nowUtc: () => now,
            loadReady: ({required limit}) async => durableRows
                .where((row) => !row.nextAttemptAt.isAfter(now))
                .take(limit)
                .toList(growable: false),
            loadEarliestNextAttemptAt: () async => durableRows.isEmpty
                ? null
                : durableRows
                      .map((row) => row.nextAttemptAt)
                      .reduce(
                        (left, right) => left.isBefore(right) ? left : right,
                      ),
            project: (row) async {
              projected.add(row.id);
              return const GroupNotificationDisplayProjectionResult.completed();
            },
            completeWithOutcome: (row, outcome) async {
              expect(outcome, isNull);
              durableRows.remove(row);
            },
            retire: (_) async {},
            recordFailure: (_, _) async {},
            scheduleRetry: scheduled.add,
          );

      await restarted.retryNow();

      expect(projected, isEmpty);
      expect(scheduled, [const Duration(seconds: 41)]);

      now = nextAttemptAt.subtract(const Duration(milliseconds: 1));
      await restarted.retryNow();
      expect(projected, isEmpty);

      now = nextAttemptAt;
      await restarted.retryNow();
      expect(projected, [9]);
      expect(durableRows, isEmpty);
    },
  );

  test(
    'TC-330-P1 an actually empty outbox does not arm a polling timer',
    () async {
      final scheduled = <Duration>[];
      final coordinator = GroupNotificationDisplayRetryCoordinator<int>(
        loadReady: ({required limit}) async => const <int>[],
        loadEarliestNextAttemptAt: () async => null,
        project: (_) async =>
            const GroupNotificationDisplayProjectionResult.completed(),
        completeWithOutcome: (_, _) async {},
        retire: (_) async {},
        recordFailure: (_, _) async {},
        scheduleRetry: scheduled.add,
      );

      await coordinator.retryNow();

      expect(scheduled, isEmpty);
    },
  );

  test(
    'TC-330-P1 due-time lookup failure releases single-flight state',
    () async {
      var lookupFails = true;
      var loads = 0;
      final coordinator = GroupNotificationDisplayRetryCoordinator<int>(
        loadReady: ({required limit}) async {
          loads++;
          return const <int>[];
        },
        loadEarliestNextAttemptAt: () async {
          if (lookupFails) throw StateError('deadline store unavailable');
          return null;
        },
        project: (_) async =>
            const GroupNotificationDisplayProjectionResult.completed(),
        completeWithOutcome: (_, _) async {},
        retire: (_) async {},
        recordFailure: (_, _) async {},
        scheduleRetry: (_) {},
      );

      await expectLater(coordinator.retryNow(), throwsA(isA<StateError>()));
      expect(coordinator.isRunning, isFalse);

      lookupFails = false;
      await coordinator.retryNow();
      expect(loads, 2);
      expect(coordinator.isRunning, isFalse);
    },
  );

  test(
    'TC-330-P1 completion and retry CAS misses arm an immediate replacement pass',
    () async {
      final rows = <int>[12];
      final failures = <Object>[];
      final scheduled = <Duration>[];
      final coordinator = GroupNotificationDisplayRetryCoordinator<int>(
        loadReady: ({required limit}) async => rows.take(limit).toList(),
        loadEarliestNextAttemptAt: () async => null,
        project: (_) async =>
            const GroupNotificationDisplayProjectionResult.completed(),
        completeWithOutcome: (_, _) async {
          // The loaded generation was replaced before completion.
          throw const GroupNotificationDisplayRetryableException();
        },
        retire: (_) async {},
        recordFailure: (_, error) async {
          failures.add(error);
          // No durable deadline models recordRetryIfExact == false against
          // the replacement generation.
        },
        scheduleRetry: scheduled.add,
      );

      await coordinator.retryNow();

      expect(rows, [12]);
      expect(
        failures.single,
        isA<GroupNotificationDisplayRetryableException>(),
      );
      expect(scheduled, [Duration.zero]);
      expect(coordinator.isRunning, isFalse);
    },
  );

  test(
    'TC-330-P1 retry recording exception still clears and schedules the pass',
    () async {
      final scheduled = <Duration>[];
      final coordinator = GroupNotificationDisplayRetryCoordinator<int>(
        loadReady: ({required limit}) async => const <int>[13],
        loadEarliestNextAttemptAt: () async => null,
        project: (_) async => throw StateError('projection failed'),
        completeWithOutcome: (_, _) async {},
        retire: (_) async {},
        recordFailure: (_, _) async =>
            throw StateError('retry CAS unavailable'),
        scheduleRetry: scheduled.add,
      );

      await expectLater(coordinator.retryNow(), throwsA(isA<StateError>()));

      expect(scheduled, [Duration.zero]);
      expect(coordinator.isRunning, isFalse);
    },
  );

  test(
    'typed completion preserves outcomes while retired custody uses its own callback',
    () async {
      final rows = <int>[1, 2];
      final candidate = NotificationCompletedOutcomeCandidate(
        physicalPeerId: 'peer-physical',
        producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
        eventKey: 'logical-delivery-1',
        outcome: NotificationCompletedOutcomeCategory.osPosted,
        completedAt: DateTime.utc(2026, 8, 15, 12),
      );
      NotificationCompletedOutcomeCandidate? completedOutcome;
      final completed = <int>[];
      final retired = <int>[];
      final coordinator = GroupNotificationDisplayRetryCoordinator<int>(
        batchSize: 2,
        loadReady: ({required limit}) async => rows.take(limit).toList(),
        project: (row) async => row == 1
            ? GroupNotificationDisplayProjectionResult.completed(
                outcomeCandidate: candidate,
              )
            : const GroupNotificationDisplayProjectionResult.retired(),
        completeWithOutcome: (row, outcome) async {
          completed.add(row);
          completedOutcome = outcome;
          rows.remove(row);
        },
        retire: (row) async {
          retired.add(row);
          rows.remove(row);
        },
        recordFailure: (_, _) async {},
      );

      await coordinator.retryNow();

      expect(completed, <int>[1]);
      expect(completedOutcome, same(candidate));
      expect(retired, <int>[2]);
      expect(rows, isEmpty);
    },
  );
}

final class _NotificationRetryRow {
  const _NotificationRetryRow(this.id);

  final int id;
}
