import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/004_nullify_secret_columns.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/006_read_at_column.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';
import 'package:flutter_app/core/database/migrations/009_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/012_transport_column.dart';
import 'package:flutter_app/core/database/migrations/014_wire_envelope_column.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runIdentityTableMigration(db);
    await runMessagesTableMigration(db);
    await runMlKemKeysMigration(db);
    await runNullifySecretColumnsMigration(db);
    await runSecretNullChecksMigration(db);
    await runReadAtColumnMigration(db);
    await runArchiveColumnsMigration(db);
    await runBlockColumnsMigration(db);
    await runQuotedMessageIdMigration(db);
    await runTransportColumnMigration(db);
    await runWireEnvelopeMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('dbRecoverStuckSendingMessages', () {
    test('returns 0 when no messages exist', () async {
      final count = await dbRecoverStuckSendingMessages(
        db,
        olderThan: DateTime.now().toUtc(),
      );
      expect(count, 0);
    });

    test('returns 0 when no sending messages exist', () async {
      await db.insert('messages', {
        'id': 'msg-delivered',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'me',
        'text': 'Hi',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'status': 'delivered',
        'is_incoming': 0,
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      final count = await dbRecoverStuckSendingMessages(
        db,
        olderThan: DateTime.now().toUtc(),
      );
      expect(count, 0);
    });

    test('does not update sending message younger than threshold', () async {
      // timestamp is 10 seconds ago — threshold is 30 seconds ago
      final recentTs = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 10))
          .toIso8601String();
      await db.insert('messages', {
        'id': 'msg-recent-sending',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'me',
        'text': 'Hi',
        'timestamp': recentTs,
        'status': 'sending',
        'is_incoming': 0,
        'created_at': recentTs,
      });
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final count =
          await dbRecoverStuckSendingMessages(db, olderThan: threshold);
      expect(count, 0);

      final row = (await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-recent-sending'])).first;
      expect(row['status'], 'sending');
    });

    test('updates sending message older than threshold to failed', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      await db.insert('messages', {
        'id': 'msg-old-sending',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'me',
        'text': 'Hi',
        'timestamp': oldTs,
        'status': 'sending',
        'is_incoming': 0,
        'created_at': oldTs,
      });
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final count =
          await dbRecoverStuckSendingMessages(db, olderThan: threshold);
      expect(count, 1);

      final row = (await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-old-sending'])).first;
      expect(row['status'], 'failed');
    });

    test('only updates outgoing messages (is_incoming = 0)', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      // Incoming row with status=sending (pathological, but should not be touched)
      await db.insert('messages', {
        'id': 'msg-incoming-sending',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'them',
        'text': 'Hi',
        'timestamp': oldTs,
        'status': 'sending',
        'is_incoming': 1,
        'created_at': oldTs,
      });
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final count =
          await dbRecoverStuckSendingMessages(db, olderThan: threshold);
      expect(count, 0);
    });

    test('updates multiple stuck sending messages in one call', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      for (var i = 0; i < 3; i++) {
        await db.insert('messages', {
          'id': 'msg-stuck-$i',
          'contact_peer_id': 'peer-a',
          'sender_peer_id': 'me',
          'text': 'msg $i',
          'timestamp': oldTs,
          'status': 'sending',
          'is_incoming': 0,
          'created_at': oldTs,
        });
      }
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final count =
          await dbRecoverStuckSendingMessages(db, olderThan: threshold);
      expect(count, 3);

      final rows = await db.query('messages',
          where: "status = 'failed' AND is_incoming = 0");
      expect(rows.length, 3);
    });

    // NOTE: This test seeds wire_envelope on a 'sending' row to verify the
    // DB helper preserves it during the status transition. In practice, most
    // stuck 'sending' rows will have wireEnvelope = null — see audit fix below.
    test('preserves wire_envelope when transitioning to failed', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      const envelope = '{"type":"chat_message","version":"2","encrypted":{}}';
      await db.insert('messages', {
        'id': 'msg-env-sending',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'me',
        'text': 'Hi',
        'timestamp': oldTs,
        'status': 'sending',
        'is_incoming': 0,
        'created_at': oldTs,
        'wire_envelope': envelope,
      });
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      await dbRecoverStuckSendingMessages(db, olderThan: threshold);

      final row = (await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-env-sending'])).first;
      expect(row['status'], 'failed');
      expect(row['wire_envelope'], envelope);
    });

    test('does not disturb non-sending statuses', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      for (final status in ['sent', 'delivered', 'failed']) {
        await db.insert('messages', {
          'id': 'msg-$status',
          'contact_peer_id': 'peer-a',
          'sender_peer_id': 'me',
          'text': 'msg',
          'timestamp': oldTs,
          'status': status,
          'is_incoming': 0,
          'created_at': oldTs,
        });
      }
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final count =
          await dbRecoverStuckSendingMessages(db, olderThan: threshold);
      expect(count, 0);
    });
  });
}
