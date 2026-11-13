import '../models/delivery_receipt_outbox_entry.dart';

abstract interface class DeliveryReceiptOutboxRepository {
  /// Keeps an existing pending payload, timestamp, expiry and retry schedule.
  Future<DeliveryReceiptOutboxEntry> stage(DeliveryReceiptOutboxEntry entry);

  Future<List<DeliveryReceiptOutboxEntry>> loadDue({
    required int nowMs,
    int limit = 50,
  });

  /// One atomic exact-snapshot claim, committed before any network attempt.
  Future<DeliveryReceiptOutboxEntry?> claimAttempt({
    required DeliveryReceiptOutboxEntry expected,
    required int nowMs,
    required int nextAttemptAtMs,
  });

  Future<bool> deleteIfExact(DeliveryReceiptOutboxEntry expected);
  Future<void> deleteExpired({required int nowMs});
}
