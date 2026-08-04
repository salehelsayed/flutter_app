import '../models/direct_notification_reconciliation_outbox_entry.dart';

abstract class DirectNotificationReconciliationOutboxRepository {
  Future<List<DirectNotificationReconciliationOutboxEntry>> loadEligible({
    int limit = 20,
  });

  Future<DateTime?> loadEarliestNextAttemptAt();

  Future<bool> recordFailureIfExact({
    required DirectNotificationReconciliationOutboxEntry expected,
    required DateTime nextAttemptAt,
  });

  Future<bool> completeIfExact(
    DirectNotificationReconciliationOutboxEntry expected,
  );
}
