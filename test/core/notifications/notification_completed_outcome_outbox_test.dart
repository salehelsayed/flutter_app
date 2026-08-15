import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/notification_completed_outcome_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/116_notification_completed_outcome_outbox.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_outbox_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('TC-369-06 outcome repository is bounded and revision exact', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'notification_completed_outcome_repository_',
    );
    final databasePath = p.join(tempDir.path, 'identity.db');
    var db = await _openCurrent(databasePath);
    addTearDown(() async {
      if (db.isOpen) await db.close();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    var clock = DateTime.utc(2026, 8, 15, 12);
    final repository = NotificationCompletedOutcomeOutboxRepository(
      database: db,
      now: () => clock,
    );
    final first = _candidate(eventKey: 'direct-message-a', completedAt: clock);
    expect(
      await db.transaction(
        (txn) => dbInsertNotificationCompletedOutcomeWithinTransaction(
          txn,
          candidate: first,
          now: clock,
          capacity: 2,
        ),
      ),
      NotificationCompletedOutcomeInsertResult.inserted,
    );
    expect(
      await db.transaction(
        (txn) => dbInsertNotificationCompletedOutcomeWithinTransaction(
          txn,
          candidate: first,
          now: clock,
          capacity: 2,
        ),
      ),
      NotificationCompletedOutcomeInsertResult.existingSame,
    );
    expect(
      await db.transaction(
        (txn) => dbInsertNotificationCompletedOutcomeWithinTransaction(
          txn,
          candidate: NotificationCompletedOutcomeCandidate(
            physicalPeerId: first.physicalPeerId,
            producerKind: first.producerKind,
            eventKey: first.eventKey,
            outcome: NotificationCompletedOutcomeCategory.inChat,
            completedAt: clock,
          ),
          now: clock,
          capacity: 2,
        ),
      ),
      NotificationCompletedOutcomeInsertResult.existingDifferent,
      reason: 'the immutable first completed category wins a replay race',
    );

    final second = _candidate(eventKey: 'direct-message-b', completedAt: clock);
    expect(
      await db.transaction(
        (txn) => dbInsertNotificationCompletedOutcomeWithinTransaction(
          txn,
          candidate: second,
          now: clock,
          capacity: 2,
        ),
      ),
      NotificationCompletedOutcomeInsertResult.inserted,
    );
    expect(
      await db.transaction(
        (txn) => dbInsertNotificationCompletedOutcomeWithinTransaction(
          txn,
          candidate: _candidate(
            eventKey: 'direct-message-capacity',
            completedAt: clock,
          ),
          now: clock,
          capacity: 2,
        ),
      ),
      NotificationCompletedOutcomeInsertResult.capacity,
    );
    expect(
      await db.transaction(
        (txn) => dbInsertNotificationCompletedOutcomeWithinTransaction(
          txn,
          candidate: _candidate(
            eventKey: ' invalid-authority',
            completedAt: clock,
          ),
          now: clock,
          capacity: 3,
        ),
      ),
      NotificationCompletedOutcomeInsertResult.invalid,
    );

    var ready = await repository.loadReady(limit: 500);
    expect(ready, hasLength(2));
    expect(
      ready.map((entry) => entry.outcome).toSet(),
      <NotificationCompletedOutcomeCategory>{
        NotificationCompletedOutcomeCategory.osPosted,
      },
    );
    expect(
      ready.every(
        (entry) =>
            entry.expiresAt.difference(entry.completedAt) ==
            kNotificationCompletedOutcomeRetention,
      ),
      isTrue,
    );
    final expected = ready.singleWhere(
      (entry) => entry.wakeCorrelation != ready.last.wakeCorrelation,
      orElse: () => ready.first,
    );
    final stale = NotificationCompletedOutcomeOutboxEntry.fromMap(
      <String, Object?>{...expected.toMap(), 'revision': 999},
    );
    expect(
      await repository.recordRetryIfExact(
        expected: stale,
        lastErrorCode: 'relay_retryable',
        nextAttemptAt: clock.add(const Duration(minutes: 5)),
      ),
      isFalse,
    );
    expect(
      await repository.recordRetryIfExact(
        expected: expected,
        lastErrorCode: 'relay_retryable',
        nextAttemptAt: clock.add(const Duration(minutes: 5)),
      ),
      isTrue,
    );
    var retried = await repository.loadExact(expected.wakeCorrelation);
    expect(retried, isNotNull);
    expect(retried!.revision, expected.revision + 1);
    expect(retried.retryCount, expected.retryCount + 1);
    expect(retried.lastErrorCode, 'relay_retryable');
    expect(
      await repository.completeIfExact(expected),
      isFalse,
      reason: 'a pre-retry revision cannot remove the durable row',
    );

    await db.execute('''
CREATE TRIGGER fail_outcome_delete
BEFORE DELETE ON $kNotificationCompletedOutcomeOutboxTable
WHEN OLD.wake_correlation = '${retried.wakeCorrelation}'
BEGIN
  SELECT RAISE(ABORT, 'forced repository fault');
END
''');
    await expectLater(
      repository.completeIfExact(retried),
      throwsA(isA<DatabaseException>()),
    );
    expect(await repository.loadExact(retried.wakeCorrelation), isNotNull);
    await db.execute('DROP TRIGGER fail_outcome_delete');
    expect(await repository.completeIfExact(retried), isTrue);
    expect(await repository.completeIfExact(retried), isFalse);

    clock = clock
        .add(kNotificationCompletedOutcomeRetention)
        .add(const Duration(seconds: 1));
    ready = await repository.loadReady();
    expect(ready, isEmpty, reason: 'expired authority is pruned before load');
    expect(await db.query(kNotificationCompletedOutcomeOutboxTable), isEmpty);
    expect(
      await db.transaction(
        (txn) => dbInsertNotificationCompletedOutcomeWithinTransaction(
          txn,
          candidate: _candidate(
            eventKey: 'direct-message-after-expiry',
            completedAt: clock,
          ),
          now: clock,
          capacity: 1,
        ),
      ),
      NotificationCompletedOutcomeInsertResult.inserted,
    );

    await db.close();
    db = await _openCurrent(databasePath);
    final reopened = NotificationCompletedOutcomeOutboxRepository(
      database: db,
      now: () => clock,
    );
    expect(await reopened.loadReady(), hasLength(1));
  });
}

NotificationCompletedOutcomeCandidate _candidate({
  required String eventKey,
  required DateTime completedAt,
}) => NotificationCompletedOutcomeCandidate(
  physicalPeerId: '12D3KooWA4WHZmYAWGCJbRwU41DwZLtCpoUW6NMWRcmWzEzbnuye',
  producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
  eventKey: eventKey,
  outcome: NotificationCompletedOutcomeCategory.osPosted,
  completedAt: completedAt,
);

Future<Database> _openCurrent(String path) => openDatabase(
  path,
  version: currentIdentityDatabaseVersion,
  singleInstance: false,
  onCreate: runProductionOnCreate,
  onUpgrade: runProductionOnUpgrade,
  onDowngrade: onDatabaseVersionChangeError,
);
