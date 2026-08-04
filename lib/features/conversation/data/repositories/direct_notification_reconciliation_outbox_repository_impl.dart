import '../../domain/models/direct_notification_reconciliation_outbox_entry.dart';
import '../../domain/repositories/direct_notification_reconciliation_outbox_repository.dart';

class DirectNotificationReconciliationOutboxRepositoryImpl
    implements DirectNotificationReconciliationOutboxRepository {
  final Future<List<Map<String, Object?>>> Function({
    int limit,
    required String eligibleAt,
  })
  dbLoadEligible;
  final Future<String?> Function() dbLoadEarliestNextAttemptAt;
  final Future<bool> Function({
    required String peerId,
    required String expectedIncarnationId,
    required int expectedRevision,
    required String lastAttemptAt,
    required String nextAttemptAt,
    required String updatedAt,
  })
  dbRecordFailureIfExact;
  final Future<bool> Function({
    required String peerId,
    required String expectedIncarnationId,
    required int expectedRevision,
  })
  dbCompleteIfExact;
  final DateTime Function() now;

  DirectNotificationReconciliationOutboxRepositoryImpl({
    required this.dbLoadEligible,
    required this.dbLoadEarliestNextAttemptAt,
    required this.dbRecordFailureIfExact,
    required this.dbCompleteIfExact,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  @override
  Future<List<DirectNotificationReconciliationOutboxEntry>> loadEligible({
    int limit = 20,
  }) async =>
      (await dbLoadEligible(
            limit: limit,
            eligibleAt: now().toUtc().toIso8601String(),
          ))
          .map(DirectNotificationReconciliationOutboxEntry.fromMap)
          .toList(growable: false);

  @override
  Future<DateTime?> loadEarliestNextAttemptAt() async {
    final encoded = await dbLoadEarliestNextAttemptAt();
    return encoded == null ? null : DateTime.parse(encoded).toUtc();
  }

  @override
  Future<bool> recordFailureIfExact({
    required DirectNotificationReconciliationOutboxEntry expected,
    required DateTime nextAttemptAt,
  }) {
    final timestamp = now().toUtc().toIso8601String();
    return dbRecordFailureIfExact(
      peerId: expected.peerId,
      expectedIncarnationId: expected.incarnationId,
      expectedRevision: expected.revision,
      lastAttemptAt: timestamp,
      nextAttemptAt: nextAttemptAt.toUtc().toIso8601String(),
      updatedAt: timestamp,
    );
  }

  @override
  Future<bool> completeIfExact(
    DirectNotificationReconciliationOutboxEntry expected,
  ) => dbCompleteIfExact(
    peerId: expected.peerId,
    expectedIncarnationId: expected.incarnationId,
    expectedRevision: expected.revision,
  );
}
