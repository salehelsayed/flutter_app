// ignore_for_file: file_names
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Local custody for existing delivery_receipt v1 envelopes only.
Future<void> runDeliveryReceiptOutboxMigration(Database database) async {
  await database.execute('''
    CREATE TABLE IF NOT EXISTS delivery_receipt_outbox (
      receipt_key TEXT PRIMARY KEY NOT NULL CHECK (length(receipt_key) = 64),
      recipient_peer_id TEXT NOT NULL CHECK (length(trim(recipient_peer_id)) > 0),
      receipt_payload TEXT NOT NULL CHECK (length(receipt_payload) > 0),
      created_at_ms INTEGER NOT NULL,
      expires_at_ms INTEGER NOT NULL
        CHECK (expires_at_ms > created_at_ms
          AND expires_at_ms <= created_at_ms + 604800000),
      next_attempt_at_ms INTEGER NOT NULL,
      attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0)
    )
  ''');
  await database.execute('''
    CREATE INDEX IF NOT EXISTS idx_delivery_receipt_outbox_due
    ON delivery_receipt_outbox(next_attempt_at_ms, created_at_ms, receipt_key)
  ''');
}
