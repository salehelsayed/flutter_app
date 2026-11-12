import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../domain/models/delivery_receipt_outbox_entry.dart';
import '../../domain/repositories/delivery_receipt_outbox_repository.dart';

/// The account database owns receipt custody independently of message rows.
class SqlDeliveryReceiptOutboxRepository
    implements DeliveryReceiptOutboxRepository {
  SqlDeliveryReceiptOutboxRepository(this.database);

  final Database database;
  static const _table = 'delivery_receipt_outbox';
  static const _exact =
      'receipt_key = ? AND recipient_peer_id = ? AND receipt_payload = ? '
      'AND created_at_ms = ? AND expires_at_ms = ? '
      'AND next_attempt_at_ms = ? AND attempt_count = ?';

  List<Object?> _arguments(DeliveryReceiptOutboxEntry entry) => [
    entry.receiptKey,
    entry.recipientPeerId,
    entry.receiptPayload,
    entry.createdAtMs,
    entry.expiresAtMs,
    entry.nextAttemptAtMs,
    entry.attemptCount,
  ];

  @override
  Future<DeliveryReceiptOutboxEntry> stage(
    DeliveryReceiptOutboxEntry entry,
  ) async {
    await database.insert(
      _table,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final rows = await database.query(
      _table,
      where: 'receipt_key = ?',
      whereArgs: [entry.receiptKey],
      limit: 1,
    );
    return DeliveryReceiptOutboxEntry.fromMap(rows.single);
  }

  @override
  Future<List<DeliveryReceiptOutboxEntry>> loadDue({
    required int nowMs,
    int limit = 50,
  }) async => (await database.query(
    _table,
    where: 'next_attempt_at_ms <= ? AND expires_at_ms > ?',
    whereArgs: [nowMs, nowMs],
    orderBy: 'next_attempt_at_ms, created_at_ms, receipt_key',
    limit: limit.clamp(1, 50),
  )).map(DeliveryReceiptOutboxEntry.fromMap).toList(growable: false);

  @override
  Future<DeliveryReceiptOutboxEntry?> claimAttempt({
    required DeliveryReceiptOutboxEntry expected,
    required int nowMs,
    required int nextAttemptAtMs,
  }) async {
    final next = DeliveryReceiptOutboxEntry(
      receiptKey: expected.receiptKey,
      recipientPeerId: expected.recipientPeerId,
      receiptPayload: expected.receiptPayload,
      createdAtMs: expected.createdAtMs,
      expiresAtMs: expected.expiresAtMs,
      nextAttemptAtMs: nextAttemptAtMs,
      attemptCount: expected.attemptCount + 1,
    );
    final changed = await database.update(
      _table,
      {
        'next_attempt_at_ms': next.nextAttemptAtMs,
        'attempt_count': next.attemptCount,
      },
      where: '$_exact AND next_attempt_at_ms <= ? AND expires_at_ms > ?',
      whereArgs: [..._arguments(expected), nowMs, nowMs],
    );
    return changed == 1 ? next : null;
  }

  @override
  Future<bool> deleteIfExact(DeliveryReceiptOutboxEntry expected) async =>
      await database.delete(
        _table,
        where: _exact,
        whereArgs: _arguments(expected),
      ) ==
      1;

  @override
  Future<void> deleteExpired({required int nowMs}) async {
    await database.delete(
      _table,
      where: 'expires_at_ms <= ?',
      whereArgs: [nowMs],
    );
  }
}
