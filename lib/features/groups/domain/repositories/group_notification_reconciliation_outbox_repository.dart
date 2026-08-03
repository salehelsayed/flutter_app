import '../models/group_notification_reconciliation_outbox_entry.dart';

abstract class GroupNotificationReconciliationOutboxRepository {
  Future<List<GroupNotificationReconciliationOutboxEntry>> loadEligible({
    int limit = 20,
  });

  Future<DateTime?> loadEarliestNextAttemptAt();

  Future<bool> recordFailureIfExact({
    required GroupNotificationReconciliationOutboxEntry expected,
    required DateTime nextAttemptAt,
  });

  /// Removes only the exact loaded incarnation/revision. A false result means
  /// newer work replaced or coalesced the entry and must remain durable.
  Future<bool> completeIfExact(
    GroupNotificationReconciliationOutboxEntry expected,
  );
}
