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
  });

  tearDown(() async {
    await db.close();
  });

  group('dbLoadStuckSendingOutgoingMessages', () {
    test('returns empty list when table is empty', () async {
      final rows = await dbLoadStuckSendingOutgoingMessages(
        db,
        olderThan: DateTime.now().toUtc(),
      );
      expect(rows, isEmpty);
    });

    test('returns row with status=sending older than threshold', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      await db.insert('messages', {
        'id': 'msg-stuck',
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
      final rows = await dbLoadStuckSendingOutgoingMessages(
        db,
        olderThan: threshold,
      );
      expect(rows.length, 1);
      expect(rows.first['id'], 'msg-stuck');
    });

    test('excludes sending row newer than threshold', () async {
      final recentTs = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 5))
          .toIso8601String();
      await db.insert('messages', {
        'id': 'msg-recent',
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
      final rows = await dbLoadStuckSendingOutgoingMessages(
        db,
        olderThan: threshold,
      );
      expect(rows, isEmpty);
    });

    test('excludes incoming sending rows', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      await db.insert('messages', {
        'id': 'msg-incoming',
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
      final rows = await dbLoadStuckSendingOutgoingMessages(
        db,
        olderThan: threshold,
      );
      expect(rows, isEmpty);
    });

    test('respects limit parameter', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      for (var i = 0; i < 5; i++) {
        await db.insert('messages', {
          'id': 'msg-$i',
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
      final rows = await dbLoadStuckSendingOutgoingMessages(
        db,
        olderThan: threshold,
        limit: 3,
      );
      expect(rows.length, 3);
    });
  });
}
