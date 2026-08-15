import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/notification_completed_outcome_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_drainer.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_outbox_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'TC-370-07 one persisted outcome drainer coalesces and retains partial relay failure across reopen',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'notification_completed_outcome_drain_',
      );
      final databasePath = p.join(tempDir.path, 'identity.db');
      var database = await _openCurrent(databasePath);
      addTearDown(() async {
        if (database.isOpen) await database.close();
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      var clock = DateTime.utc(2026, 8, 15, 12);
      var repository = NotificationCompletedOutcomeOutboxRepository(
        database: database,
        now: () => clock,
      );
      for (final eventKey in const <String>['event-a', 'event-b']) {
        expect(
          await database.transaction(
            (txn) => dbInsertNotificationCompletedOutcomeWithinTransaction(
              txn,
              candidate: NotificationCompletedOutcomeCandidate(
                physicalPeerId:
                    '12D3KooWA4WHZmYAWGCJbRwU41DwZLtCpoUW6NMWRcmWzEzbnuye',
                producerKind:
                    NotificationCompletedOutcomeProducerKind.directMessage,
                eventKey: eventKey,
                outcome: NotificationCompletedOutcomeCategory.osPosted,
                completedAt: clock,
              ),
              now: clock,
            ),
          ),
          NotificationCompletedOutcomeInsertResult.inserted,
        );
      }
      final initial = await repository.loadReady();
      expect(initial, hasLength(2));
      final terminalCorrelation = initial.first.wakeCorrelation;
      final retryableCorrelation = initial.last.wakeCorrelation;

      final disabledComposition = NotificationCompletedOutcomeDrainComposition(
        database: database,
        admissionEnabled: false,
        nowUtc: () => clock,
        sendOutcome: ({required correlation}) async => throw StateError(
          'default-off composition must not expose a drain callback',
        ),
      );
      expect(disabledComposition.drain, isNull);

      final firstSendEntered = Completer<void>();
      final secondSendEntered = Completer<void>();
      final releaseFirstSend = Completer<void>();
      final networkGateEntered = Completer<void>();
      final releaseNetworkGate = Completer<void>();
      var networkGateEntries = 0;
      var sendCount = 0;
      final composition = NotificationCompletedOutcomeDrainComposition(
        database: database,
        admissionEnabled: true,
        nowUtc: () => clock,
        runNetworkAction: (action) async {
          networkGateEntries++;
          if (!networkGateEntered.isCompleted) networkGateEntered.complete();
          await releaseNetworkGate.future;
          await action();
        },
        sendOutcome: ({required correlation}) async {
          sendCount++;
          if (!firstSendEntered.isCompleted) {
            firstSendEntered.complete();
            await releaseFirstSend.future;
          } else if (!secondSendEntered.isCompleted) {
            secondSendEntered.complete();
          }
          if (correlation == terminalCorrelation) {
            return <String, dynamic>{
              'ok': true,
              'allParticipantsTerminal': true,
              'participantCount': 2,
              'acceptedCount': 1,
              'unsupportedCount': 1,
              'retryableCount': 0,
            };
          }
          return <String, dynamic>{
            'ok': false,
            'allParticipantsTerminal': false,
            'participantCount': 2,
            'acceptedCount': 1,
            'unsupportedCount': 0,
            'retryableCount': 1,
            'errorCode': 'INBOX_WAKE_OUTCOME_RETRYABLE',
          };
        },
      );

      final firstDrain = composition.drain!();
      await networkGateEntered.future;
      final overlappingDrain = composition.drain!();
      expect(
        identical(firstDrain, overlappingDrain),
        isTrue,
        reason:
            'the public callback must coalesce outside the async account gate',
      );
      expect(networkGateEntries, 1);
      releaseNetworkGate.complete();
      await firstSendEntered.future;
      final midPassDrain = composition.drain!();
      expect(identical(firstDrain, midPassDrain), isTrue);
      await secondSendEntered.future.timeout(const Duration(seconds: 1));
      expect(
        sendCount,
        2,
        reason: 'one slow relay row cannot head-of-line block the next outcome',
      );
      releaseFirstSend.complete();
      await Future.wait(<Future<void>>[
        firstDrain,
        overlappingDrain,
        midPassDrain,
      ]);

      expect(
        sendCount,
        2,
        reason: 'an overlapping kick cannot duplicate sends',
      );
      expect(
        networkGateEntries,
        2,
        reason:
            'overlapping public kicks share one Future and request one bounded '
            'outer follow-up after the production gate',
      );
      expect(await repository.loadExact(terminalCorrelation), isNull);
      final retained = await repository.loadExact(retryableCorrelation);
      expect(retained, isNotNull);
      expect(retained!.retryCount, 1);
      expect(retained.lastErrorCode, 'wake_outcome_retryable');

      await database.close();
      database = await _openCurrent(databasePath);
      clock = clock.add(const Duration(seconds: 6));
      repository = NotificationCompletedOutcomeOutboxRepository(
        database: database,
        now: () => clock,
      );
      final reopenedComposition = NotificationCompletedOutcomeDrainComposition(
        database: database,
        admissionEnabled: true,
        nowUtc: () => clock,
        runNetworkAction: (action) => action(),
        sendOutcome: ({required correlation}) async => <String, dynamic>{
          'ok': true,
          'allParticipantsTerminal': true,
          'participantCount': 1,
          'acceptedCount': 1,
          'unsupportedCount': 0,
          'retryableCount': 0,
        },
      );
      await reopenedComposition.drain!();
      expect(
        await repository.loadExact(retryableCorrelation),
        isNull,
        reason: 'the same durable row converges after process/database reopen',
      );

      final teardownCandidate = NotificationCompletedOutcomeCandidate(
        physicalPeerId: '12D3KooWA4WHZmYAWGCJbRwU41DwZLtCpoUW6NMWRcmWzEzbnuye',
        producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
        eventKey: 'event-committed-during-network-teardown',
        outcome: NotificationCompletedOutcomeCategory.osPosted,
        completedAt: clock,
      );
      var insertedDuringTeardown = false;
      var teardownSendCount = 0;
      Future<void>? teardownJoined;
      late final NotificationCompletedOutcomeDrainComposition
      teardownComposition;
      teardownComposition = NotificationCompletedOutcomeDrainComposition(
        database: database,
        admissionEnabled: true,
        nowUtc: () => clock,
        runNetworkAction: (action) async {
          await action();
          if (insertedDuringTeardown) return;
          insertedDuringTeardown = true;
          expect(
            await database.transaction(
              (txn) => dbInsertNotificationCompletedOutcomeWithinTransaction(
                txn,
                candidate: teardownCandidate,
                now: clock,
              ),
            ),
            NotificationCompletedOutcomeInsertResult.inserted,
          );
          teardownJoined = teardownComposition.drain!();
        },
        sendOutcome: ({required correlation}) async {
          teardownSendCount++;
          return <String, dynamic>{
            'ok': true,
            'allParticipantsTerminal': true,
            'participantCount': 1,
            'acceptedCount': 1,
            'unsupportedCount': 0,
            'retryableCount': 0,
          };
        },
      );
      final teardownDrain = teardownComposition.drain!();
      await teardownDrain;
      expect(identical(teardownJoined, teardownDrain), isTrue);
      expect(teardownSendCount, 1);
      expect(
        await repository.loadReady(),
        isEmpty,
        reason:
            'a row committed after the inner drain but before the outer gate '
            'returns must be consumed by the joined public Future',
      );

      var boundedGateEntries = 0;
      var activeBoundedGates = 0;
      var maximumActiveBoundedGates = 0;
      final thirdGateEntered = Completer<void>();
      final releaseThirdGate = Completer<void>();
      final thirdGateFinished = Completer<void>();
      Future<void>? firstPassKick;
      Future<void>? secondPassKick;
      late final NotificationCompletedOutcomeDrainComposition
      boundedComposition;
      boundedComposition = NotificationCompletedOutcomeDrainComposition(
        database: database,
        admissionEnabled: true,
        nowUtc: () => clock,
        runNetworkAction: (action) async {
          boundedGateEntries++;
          final pass = boundedGateEntries;
          activeBoundedGates++;
          if (activeBoundedGates > maximumActiveBoundedGates) {
            maximumActiveBoundedGates = activeBoundedGates;
          }
          try {
            if (pass == 3) {
              thirdGateEntered.complete();
              await releaseThirdGate.future;
            }
            await action();
            if (pass == 1) {
              firstPassKick = boundedComposition.drain!();
            } else if (pass == 2) {
              secondPassKick = boundedComposition.drain!();
            }
          } finally {
            activeBoundedGates--;
            if (pass == 3) thirdGateFinished.complete();
          }
        },
        sendOutcome: ({required correlation}) async => throw StateError(
          'the bounded empty-pass proof must not send an outcome',
        ),
      );
      final boundedFirstRun = boundedComposition.drain!();
      await thirdGateEntered.future.timeout(const Duration(seconds: 1));
      await boundedFirstRun.timeout(const Duration(seconds: 1));
      expect(identical(firstPassKick, boundedFirstRun), isTrue);
      expect(identical(secondPassKick, boundedFirstRun), isTrue);
      expect(boundedGateEntries, 3);
      expect(
        maximumActiveBoundedGates,
        1,
        reason:
            'a kick on the second joined pass transfers to a separate owner '
            'without overlapping account/network gates',
      );
      releaseThirdGate.complete();
      await thirdGateFinished.future.timeout(const Duration(seconds: 1));
    },
  );
}

Future<Database> _openCurrent(String path) => openDatabase(
  path,
  version: currentIdentityDatabaseVersion,
  singleInstance: false,
  onCreate: runProductionOnCreate,
  onUpgrade: runProductionOnUpgrade,
  onDowngrade: onDatabaseVersionChangeError,
);
