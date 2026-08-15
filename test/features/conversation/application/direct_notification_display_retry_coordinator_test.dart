import 'dart:async';

import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/features/conversation/application/direct_notification_display_retry_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TC-331-08 concurrent triggers coalesce and later custody drains in the same bounded run',
    () async {
      final rows = <int>[1];
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final projected = <int>[];
      late final DirectNotificationDisplayRetryCoordinator<int> coordinator;
      coordinator = DirectNotificationDisplayRetryCoordinator<int>(
        batchSize: 2,
        maxBatchesPerRun: 3,
        loadReady: ({required limit}) async =>
            rows.take(limit).toList(growable: false),
        project: (row) async {
          projected.add(row);
          if (row == 1 && !firstStarted.isCompleted) {
            firstStarted.complete();
            await releaseFirst.future;
          }
          return const DirectNotificationDisplayProjectionResult.completed();
        },
        completeWithOutcome: (row, outcome) async {
          expect(outcome, isNull);
          rows.remove(row);
        },
        retire: (_) async {},
        recordFailure: (_, _) async {},
      );

      final first = coordinator.retryNow();
      await firstStarted.future;
      rows.add(2);
      final joined = coordinator.retryNow();
      releaseFirst.complete();
      await Future.wait(<Future<void>>[first, joined]);

      expect(projected, <int>[1, 2]);
      expect(rows, isEmpty);
    },
  );

  test(
    'retryable custody remains durable and arms exact persisted deadline',
    () async {
      final now = DateTime.utc(2026, 8, 3, 12);
      final due = now.add(const Duration(seconds: 41));
      final rows = <int>[1, 2];
      final completed = <int>[];
      final scheduled = <Duration>[];
      final coordinator = DirectNotificationDisplayRetryCoordinator<int>(
        nowUtc: () => now,
        batchSize: 1,
        maxBatchesPerRun: 3,
        loadReady: ({required limit}) async =>
            rows.take(limit).toList(growable: false),
        entryIdentity: (row) => row,
        loadEarliestNextAttemptAt: () async => due,
        project: (row) async => row == 1
            ? const DirectNotificationDisplayProjectionResult.retryLater()
            : const DirectNotificationDisplayProjectionResult.completed(),
        completeWithOutcome: (row, outcome) async {
          expect(outcome, isNull);
          completed.add(row);
          rows.remove(row);
        },
        retire: (_) async {},
        recordFailure: (_, _) async {},
        scheduleRetry: scheduled.add,
      );

      await coordinator.retryNow();

      expect(completed, <int>[2]);
      expect(rows, <int>[1]);
      expect(scheduled, <Duration>[const Duration(seconds: 41)]);
    },
  );

  test('dispose fences completion after an in-flight projection', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var completions = 0;
    final coordinator = DirectNotificationDisplayRetryCoordinator<int>(
      loadReady: ({required limit}) async => const <int>[1],
      project: (_) async {
        started.complete();
        await release.future;
        return const DirectNotificationDisplayProjectionResult.completed();
      },
      completeWithOutcome: (_, _) async => completions++,
      retire: (_) async {},
      recordFailure: (_, _) async {},
    );

    final running = coordinator.retryNow();
    await started.future;
    coordinator.dispose();
    release.complete();
    await running;

    expect(completions, 0);
  });

  test(
    'completed projection carries its immutable outcome candidate',
    () async {
      final rows = <int>[1];
      final candidate = NotificationCompletedOutcomeCandidate(
        physicalPeerId: 'peer-physical',
        producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
        eventKey: 'message-1',
        outcome: NotificationCompletedOutcomeCategory.osPosted,
        completedAt: DateTime.utc(2026, 8, 15, 12),
      );
      NotificationCompletedOutcomeCandidate? completedOutcome;
      final coordinator = DirectNotificationDisplayRetryCoordinator<int>(
        loadReady: ({required limit}) async => rows.take(limit).toList(),
        project: (_) async =>
            DirectNotificationDisplayProjectionResult.completed(
              outcomeCandidate: candidate,
            ),
        completeWithOutcome: (row, outcome) async {
          completedOutcome = outcome;
          rows.remove(row);
        },
        retire: (_) async => fail('completed custody must not retire'),
        recordFailure: (_, _) async {},
      );

      await coordinator.retryNow();

      expect(completedOutcome, same(candidate));
      expect(rows, isEmpty);
    },
  );
}
