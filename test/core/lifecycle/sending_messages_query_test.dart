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

  tearDown(() async => db.close());

  Map<String, Object?> makeRow({
    required String id,
    required String status,
    int isIncoming = 0,
    String? wireEnvelope,
  }) =>
      {
        'id': id,
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'my-peer-id',
        'text': 'Hello',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'status': status,
        'is_incoming': isIncoming,
        'created_at': '2026-01-01T00:00:00.000Z',
        'wire_envelope': wireEnvelope,
      };

  group('dbLoadSendingOutgoingMessages', () {
    test('returns empty list when no messages exist', () async {
      final rows = await dbLoadSendingOutgoingMessages(db);
      expect(rows, isEmpty);
    });

    test('returns only sending outgoing messages', () async {
      await dbInsertMessage(db, makeRow(id: 'msg-s', status: 'sending'));
      await dbInsertMessage(db, makeRow(id: 'msg-f', status: 'failed'));
      await dbInsertMessage(db, makeRow(id: 'msg-d', status: 'delivered'));
      await dbInsertMessage(
        db,
        makeRow(id: 'msg-in', status: 'sending', isIncoming: 1),
      );

      final rows = await dbLoadSendingOutgoingMessages(db);

      expect(rows.length, 1);
      expect(rows.first['id'], 'msg-s');
    });

    test('returns all sending outgoing messages when multiple exist', () async {
      for (var i = 1; i <= 4; i++) {
        await dbInsertMessage(db, makeRow(id: 'msg-$i', status: 'sending'));
      }
      await dbInsertMessage(db, makeRow(id: 'msg-ok', status: 'sent'));

      final rows = await dbLoadSendingOutgoingMessages(db);

      expect(rows.length, 4);
      expect(
        rows.map((r) => r['id']).toSet(),
        containsAll(['msg-1', 'msg-2', 'msg-3', 'msg-4']),
      );
    });

    test('includes wire_envelope column in returned rows', () async {
      const envelope = '{"version":"2","encrypted":{}}';
      await dbInsertMessage(
        db,
        makeRow(id: 'msg-e', status: 'sending', wireEnvelope: envelope),
      );

      final rows = await dbLoadSendingOutgoingMessages(db);

      expect(rows.first['wire_envelope'], envelope);
    });

    test('returns rows ordered by timestamp ASC', () async {
      await dbInsertMessage(db, {
        ...makeRow(id: 'msg-late', status: 'sending'),
        'timestamp': '2026-01-03T00:00:00.000Z',
      });
      await dbInsertMessage(db, {
        ...makeRow(id: 'msg-early', status: 'sending'),
        'timestamp': '2026-01-01T00:00:00.000Z',
      });

      final rows = await dbLoadSendingOutgoingMessages(db);

      expect(rows.first['id'], 'msg-early');
      expect(rows.last['id'], 'msg-late');
    });
  });

  group('dbConditionalTransitionStatus', () {
    test('transitions status when current status matches fromStatus',
        () async {
      await dbInsertMessage(db, makeRow(id: 'msg-ct', status: 'sending'));

      final count = await dbConditionalTransitionStatus(
        db,
        'msg-ct',
        fromStatus: 'sending',
        toStatus: 'failed',
      );

      expect(count, 1);
      final rows =
          await db.query('messages', where: 'id = ?', whereArgs: ['msg-ct']);
      expect(rows.single['status'], 'failed');
    });

    test('returns 0 and does not update when current status does not match',
        () async {
      await dbInsertMessage(db, makeRow(id: 'msg-ct2', status: 'delivered'));

      final count = await dbConditionalTransitionStatus(
        db,
        'msg-ct2',
        fromStatus: 'sending',
        toStatus: 'failed',
      );

      expect(count, 0);
      final rows =
          await db.query('messages', where: 'id = ?', whereArgs: ['msg-ct2']);
      expect(rows.single['status'], 'delivered');
    });

    test('returns 0 for non-existent message ID', () async {
      final count = await dbConditionalTransitionStatus(
        db,
        'no-such-id',
        fromStatus: 'sending',
        toStatus: 'failed',
      );

      expect(count, 0);
    });

    test('preserves wire_envelope when transitioning status', () async {
      const envelope = '{"version":"2","encrypted":{}}';
      await dbInsertMessage(
        db,
        makeRow(id: 'msg-ct3', status: 'sending', wireEnvelope: envelope),
      );

      await dbConditionalTransitionStatus(
        db,
        'msg-ct3',
        fromStatus: 'sending',
        toStatus: 'failed',
      );

      final rows =
          await db.query('messages', where: 'id = ?', whereArgs: ['msg-ct3']);
      expect(rows.single['wire_envelope'], envelope);
    });
  });
}
