import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/077_message_relay_custody.dart';

/// 115 Phase 1.5 — migration 077: relay custody columns on `messages`.
///
/// `relay_expires_at` (INTEGER, ms epoch — relay-stamped custody expiry) and
/// `custody_checked_at` (TEXT, ISO-8601 — last custody-sweep touch) back the
/// 'inboxed' status foundation (doc 115 G-B) and the Phase 3 custody sweep.
/// Both nullable: live-acked and historical rows never carry them.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runMessagesTableMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> messageColumns() async {
    final columns = await db.rawQuery('PRAGMA table_info(messages)');
    return columns.map((column) => column['name'] as String).toList();
  }

  test(
    'migration 077 adds nullable relay_expires_at and custody_checked_at columns to messages',
    () async {
      expect(await messageColumns(), isNot(contains('relay_expires_at')));
      expect(await messageColumns(), isNot(contains('custody_checked_at')));

      await runMessageRelayCustodyMigration(db);

      expect(await messageColumns(), contains('relay_expires_at'));
      expect(await messageColumns(), contains('custody_checked_at'));
    },
  );

  test('preserves existing rows with null custody columns', () async {
    await db.insert('messages', {
      'id': 'legacy-msg-1',
      'contact_peer_id': 'peer-a',
      'sender_peer_id': 'peer-a',
      'text': 'pre-077 row',
      'timestamp': '2026-06-01T10:00:00.000Z',
      'status': 'delivered',
      'is_incoming': 0,
      'created_at': '2026-06-01T10:00:00.000Z',
    });

    await runMessageRelayCustodyMigration(db);

    final row = (await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: ['legacy-msg-1'],
    )).single;
    expect(row['text'], 'pre-077 row');
    expect(row['relay_expires_at'], isNull);
    expect(row['custody_checked_at'], isNull);
  });

  test('is idempotent', () async {
    await runMessageRelayCustodyMigration(db);
    await runMessageRelayCustodyMigration(db);

    final expiryColumns = (await messageColumns())
        .where((name) => name == 'relay_expires_at')
        .toList();
    expect(expiryColumns, hasLength(1));
  });
}
