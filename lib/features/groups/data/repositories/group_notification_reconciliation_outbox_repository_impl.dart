import '../../domain/models/group_notification_reconciliation_outbox_entry.dart';
import '../../domain/repositories/group_notification_reconciliation_outbox_repository.dart';

class GroupNotificationReconciliationOutboxRepositoryImpl
    implements GroupNotificationReconciliationOutboxRepository {
  final Future<List<Map<String, Object?>>> Function({
    int limit,
    required String eligibleAt,
  })
  dbLoadEligible;
  final Future<String?> Function() dbLoadEarliestNextAttemptAt;
  final Future<bool> Function({
    required String groupId,
    required String expectedIncarnationId,
    required int expectedRevision,
    required String lastAttemptAt,
    required String nextAttemptAt,
    required String updatedAt,
  })
  dbRecordFailureIfExact;
  final Future<bool> Function({
    required String groupId,
    required String expectedIncarnationId,
    required int expectedRevision,
  })
  dbCompleteIfExact;
  final DateTime Function() now;

  GroupNotificationReconciliationOutboxRepositoryImpl({
    required this.dbLoadEligible,
    required this.dbLoadEarliestNextAttemptAt,
    required this.dbRecordFailureIfExact,
    required this.dbCompleteIfExact,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  @override
  Future<List<GroupNotificationReconciliationOutboxEntry>> loadEligible({
    int limit = 20,
  }) async {
    final rows = await dbLoadEligible(
      limit: limit,
      eligibleAt: now().toUtc().toIso8601String(),
    );
    return rows
        .map(GroupNotificationReconciliationOutboxEntry.fromMap)
        .toList(growable: false);
  }

  @override
  Future<DateTime?> loadEarliestNextAttemptAt() async {
    final encoded = await dbLoadEarliestNextAttemptAt();
    return encoded == null ? null : DateTime.parse(encoded).toUtc();
  }

  @override
  Future<bool> recordFailureIfExact({
    required GroupNotificationReconciliationOutboxEntry expected,
    required DateTime nextAttemptAt,
  }) {
    final timestamp = now().toUtc().toIso8601String();
    return dbRecordFailureIfExact(
      groupId: expected.groupId,
      expectedIncarnationId: expected.incarnationId,
      expectedRevision: expected.revision,
      lastAttemptAt: timestamp,
      nextAttemptAt: nextAttemptAt.toUtc().toIso8601String(),
      updatedAt: timestamp,
    );
  }

  @override
  Future<bool> completeIfExact(
    GroupNotificationReconciliationOutboxEntry expected,
  ) {
    return dbCompleteIfExact(
      groupId: expected.groupId,
      expectedIncarnationId: expected.incarnationId,
      expectedRevision: expected.revision,
    );
  }
}
