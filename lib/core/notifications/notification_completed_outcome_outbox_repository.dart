import 'package:sqflite_sqlcipher/sqflite.dart';

import '../database/helpers/notification_completed_outcome_outbox_db_helpers.dart';
import 'notification_completed_outcome.dart';

class NotificationCompletedOutcomeOutboxRepository {
  final Database database;
  final DateTime Function() now;

  NotificationCompletedOutcomeOutboxRepository({
    required this.database,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  Future<List<NotificationCompletedOutcomeOutboxEntry>> loadReady({
    int limit = 20,
  }) async =>
      (await dbLoadReadyNotificationCompletedOutcomeOutboxEntries(
            database,
            now: now(),
            limit: limit,
          ))
          .map(NotificationCompletedOutcomeOutboxEntry.fromMap)
          .toList(growable: false);

  Future<NotificationCompletedOutcomeOutboxEntry?> loadExact(
    String wakeCorrelation,
  ) async {
    final row = await dbLoadExactNotificationCompletedOutcomeOutboxEntry(
      database,
      wakeCorrelation: wakeCorrelation,
    );
    return row == null
        ? null
        : NotificationCompletedOutcomeOutboxEntry.fromMap(row);
  }

  Future<bool> recordRetryIfExact({
    required NotificationCompletedOutcomeOutboxEntry expected,
    required String lastErrorCode,
    required DateTime nextAttemptAt,
  }) => dbRecordNotificationCompletedOutcomeRetryIfExact(
    database,
    wakeCorrelation: expected.wakeCorrelation,
    expectedRevision: expected.revision,
    expectedOutcome: expected.outcome.wireValue,
    lastErrorCode: lastErrorCode,
    lastAttemptAt: now(),
    nextAttemptAt: nextAttemptAt,
  );

  Future<bool> completeIfExact(
    NotificationCompletedOutcomeOutboxEntry expected,
  ) => dbCompleteNotificationCompletedOutcomeIfExact(
    database,
    wakeCorrelation: expected.wakeCorrelation,
    expectedRevision: expected.revision,
    expectedOutcome: expected.outcome.wireValue,
  );
}
