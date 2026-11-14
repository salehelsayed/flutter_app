/// An immutable receipt envelope plus its persisted retry schedule.
class DeliveryReceiptOutboxEntry {
  const DeliveryReceiptOutboxEntry({
    required this.receiptKey,
    required this.recipientPeerId,
    required this.receiptPayload,
    required this.createdAtMs,
    required this.expiresAtMs,
    required this.nextAttemptAtMs,
    required this.attemptCount,
  });

  final String receiptKey;
  final String recipientPeerId;
  final String receiptPayload;
  final int createdAtMs;
  final int expiresAtMs;
  final int nextAttemptAtMs;
  final int attemptCount;

  factory DeliveryReceiptOutboxEntry.fromMap(Map<String, Object?> row) =>
      DeliveryReceiptOutboxEntry(
        receiptKey: row['receipt_key'] as String,
        recipientPeerId: row['recipient_peer_id'] as String,
        receiptPayload: row['receipt_payload'] as String,
        createdAtMs: row['created_at_ms'] as int,
        expiresAtMs: row['expires_at_ms'] as int,
        nextAttemptAtMs: row['next_attempt_at_ms'] as int,
        attemptCount: row['attempt_count'] as int,
      );

  Map<String, Object?> toMap() => {
    'receipt_key': receiptKey,
    'recipient_peer_id': recipientPeerId,
    'receipt_payload': receiptPayload,
    'created_at_ms': createdAtMs,
    'expires_at_ms': expiresAtMs,
    'next_attempt_at_ms': nextAttemptAtMs,
    'attempt_count': attemptCount,
  };
}
