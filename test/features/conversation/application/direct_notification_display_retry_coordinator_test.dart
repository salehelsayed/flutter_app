import 'dart:async';

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
          return DirectNotificationDisplayRetryDisposition.completed;
        },
        complete: (row) async => rows.remove(row),
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
            ? DirectNotificationDisplayRetryDisposition.retryLater
            : DirectNotificationDisplayRetryDisposition.completed,
        complete: (row) async {
          completed.add(row);
          rows.remove(row);
        },
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
        return DirectNotificationDisplayRetryDisposition.completed;
      },
      complete: (_) async => completions++,
      recordFailure: (_, _) async {},
    );

    final running = coordinator.retryNow();
    await started.future;
    coordinator.dispose();
    release.complete();
    await running;

    expect(completions, 0);
  });
}
