import 'dart:async';

import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
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

  test(
    'TC-372-06 direct durable SQL A retains custody through settlement and SQL B retires it',
    () async {
      final rows = <int>[1];
      final order = <String>[];
      const correlation =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const authority = DirectNotificationDurableEffectAuthority(
        currentOpaqueBinding:
            'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        physicalPeerId: '12D3KooWphysical-direct',
        outcomeProducerKind:
            NotificationCompletedOutcomeProducerKind.directMessage,
        eventKey: 'message-direct-raw',
        receipt: DurableLocalNotificationEffectReceipt(
          eventCorrelation: correlation,
          recordRevision: 7,
          presentationState: LocalNotificationPresentationState.osPosted,
        ),
      );
      final coordinator = DirectNotificationDisplayRetryCoordinator<int>(
        loadReady: ({required limit}) async => rows.take(limit).toList(),
        project: (_) async =>
            const DirectNotificationDisplayProjectionResult.completed(
              durableEffectAuthority: authority,
            ),
        completeWithOutcome: (_, _) async =>
            fail('durable completion must use the exact SQL handoff'),
        completeDurableSqlHandoff: (row, outcome, exactAuthority) async {
          expect(exactAuthority, same(authority));
          expect(rows, contains(row));
          order.add('sql-a');
          return DurableLocalNotificationSqlHandoffResult.committed;
        },
        settleDurableEffect: (_, exactAuthority) async {
          expect(
            rows,
            isNotEmpty,
            reason: 'raw READY custody spans file-ledger settlement',
          );
          expect(exactAuthority.receipt.recordRevision, 7);
          order.add('settle');
        },
        afterDurableSettlement: (row, exactAuthority) async {
          expect(exactAuthority, same(authority));
          rows.remove(row);
          order.add('sql-b');
        },
        retire: (_) async => fail('completed custody must not retire'),
        recordFailure: (_, _) async => fail('successful handoff must not fail'),
      );

      await coordinator.retryNow();

      expect(rows, isEmpty);
      expect(order, const <String>['sql-a', 'settle', 'sql-b']);
    },
  );

  test(
    'TC-372-06 direct SQL mismatch retains effect terminal and never settles',
    () async {
      final rows = <int>[1];
      var settlements = 0;
      var failures = 0;
      const authority = DirectNotificationDurableEffectAuthority(
        currentOpaqueBinding:
            'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        physicalPeerId: '12D3KooWphysical-direct',
        outcomeProducerKind:
            NotificationCompletedOutcomeProducerKind.directReaction,
        eventKey: 'raw-reaction-id-that-is-not-a-bounded-alias',
        receipt: DurableLocalNotificationEffectReceipt(
          eventCorrelation:
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          recordRevision: 11,
          presentationState: LocalNotificationPresentationState.inChat,
        ),
      );
      final coordinator = DirectNotificationDisplayRetryCoordinator<int>(
        maxBatchesPerRun: 1,
        loadReady: ({required limit}) async => rows.take(limit).toList(),
        project: (_) async =>
            const DirectNotificationDisplayProjectionResult.completed(
              durableEffectAuthority: authority,
            ),
        completeWithOutcome: (_, _) async {},
        completeDurableSqlHandoff: (_, _, _) async =>
            DurableLocalNotificationSqlHandoffResult.retryableMismatch,
        settleDurableEffect: (_, _) async => settlements++,
        retire: (_) async {},
        recordFailure: (_, _) async => failures++,
      );

      await coordinator.retryNow();

      expect(rows, const <int>[1]);
      expect(settlements, 0);
      expect(failures, 1);
    },
  );

  test(
    'TC-372-06 settle failure re-verifies SQL without a second projection effect',
    () async {
      final rows = <int>[1];
      var projections = 0;
      var handoffs = 0;
      var settlements = 0;
      var postSettlementNotifications = 0;
      var failures = 0;
      var sqlCommitted = false;
      final scheduled = <Duration>[];
      const authority = DirectNotificationDurableEffectAuthority(
        currentOpaqueBinding:
            'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        physicalPeerId: '12D3KooWphysical-direct',
        outcomeProducerKind:
            NotificationCompletedOutcomeProducerKind.directMessage,
        eventKey: 'message-receipt-only-retry',
        receipt: DurableLocalNotificationEffectReceipt(
          eventCorrelation:
              'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
          recordRevision: 13,
          presentationState: LocalNotificationPresentationState.osPosted,
        ),
      );
      final coordinator = DirectNotificationDisplayRetryCoordinator<int>(
        durableSettlementRetryDelay: const Duration(seconds: 17),
        loadReady: ({required limit}) async => rows.take(limit).toList(),
        project: (_) async {
          projections++;
          return const DirectNotificationDisplayProjectionResult.completed(
            durableEffectAuthority: authority,
          );
        },
        completeWithOutcome: (_, _) async {},
        completeDurableSqlHandoff: (row, _, _) async {
          handoffs++;
          expect(rows, contains(row));
          if (!sqlCommitted) {
            sqlCommitted = true;
            return DurableLocalNotificationSqlHandoffResult.committed;
          }
          return DurableLocalNotificationSqlHandoffResult.alreadyCommitted;
        },
        settleDurableEffect: (_, _) async {
          settlements++;
          if (settlements == 1) {
            throw StateError('injected ledger write outage');
          }
        },
        afterDurableSettlement: (row, _) async {
          rows.remove(row);
          postSettlementNotifications++;
        },
        retire: (_) async {},
        recordFailure: (_, _) async => failures++,
        scheduleRetry: scheduled.add,
      );

      await coordinator.retryNow();
      expect(projections, 1);
      expect(rows, const <int>[1]);
      expect(failures, 0, reason: 'receipt-only retry keeps READY revision');
      expect(scheduled, const <Duration>[Duration(seconds: 17)]);

      await coordinator.retryNow();
      expect(projections, 1, reason: 'receipt-only retry must not re-alert');
      expect(handoffs, 2, reason: 'second handoff verifies already committed');
      expect(settlements, 2);
      expect(postSettlementNotifications, 1);
      expect(rows, isEmpty);
      expect(failures, 0);
    },
  );

  test(
    'TC-372-06 SQL B failure retries receipt-only without advancing READY',
    () async {
      final rows = <int>[1];
      var projections = 0;
      var handoffs = 0;
      var settlements = 0;
      var retireAttempts = 0;
      var failures = 0;
      final scheduled = <Duration>[];
      const authority = DirectNotificationDurableEffectAuthority(
        currentOpaqueBinding:
            'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        physicalPeerId: '12D3KooWphysical-direct',
        outcomeProducerKind:
            NotificationCompletedOutcomeProducerKind.directMessage,
        eventKey: 'message-sql-b-retry',
        receipt: DurableLocalNotificationEffectReceipt(
          eventCorrelation:
              'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
          recordRevision: 17,
          presentationState: LocalNotificationPresentationState.cancelled,
        ),
      );
      final coordinator = DirectNotificationDisplayRetryCoordinator<int>(
        durableSettlementRetryDelay: const Duration(seconds: 19),
        loadReady: ({required limit}) async => rows.take(limit).toList(),
        entryIdentity: (row) => row,
        project: (_) async {
          projections++;
          return const DirectNotificationDisplayProjectionResult.completed(
            durableEffectAuthority: authority,
          );
        },
        completeWithOutcome: (_, _) async {},
        completeDurableSqlHandoff: (_, _, _) async {
          handoffs++;
          return handoffs == 1
              ? DurableLocalNotificationSqlHandoffResult.committed
              : DurableLocalNotificationSqlHandoffResult.alreadyCommitted;
        },
        settleDurableEffect: (_, _) async => settlements++,
        afterDurableSettlement: (row, _) async {
          retireAttempts++;
          if (retireAttempts == 1) {
            throw StateError('injected SQL B outage');
          }
          rows.remove(row);
        },
        retire: (_) async {},
        recordFailure: (_, _) async => failures++,
        scheduleRetry: scheduled.add,
      );

      await coordinator.retryNow();
      expect(rows, const <int>[1]);
      expect(projections, 1);
      expect(handoffs, 1);
      expect(settlements, 1);
      expect(retireAttempts, 1);
      expect(failures, 0, reason: 'SQL B owns retry without revising READY');
      expect(scheduled, const <Duration>[Duration(seconds: 19)]);

      await coordinator.retryNow();
      expect(rows, isEmpty);
      expect(projections, 1, reason: 'settled receipt never re-enters effect');
      expect(handoffs, 2, reason: 'SQL A is re-verified idempotently');
      expect(settlements, 2, reason: 'ledger settlement is idempotent');
      expect(retireAttempts, 2);
      expect(failures, 0);
    },
  );
}
