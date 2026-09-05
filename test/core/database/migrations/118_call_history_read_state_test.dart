import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/117_call_history.dart';
import 'package:flutter_app/core/database/migrations/118_call_history_read_state.dart';

/// 410: a missed call is unread until the user opens that conversation.
///
/// Messages already carry read state; calls had none, so the badge could only
/// ever describe half the conversation. `read_at` is nullable and defaults to
/// NULL, so every row that already exists starts out unread — which is the
/// truthful state for a call the user has not seen.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> open() async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await runCallHistoryMigration(db);
    return db;
  }

  test('TC-410-01 the migration adds a nullable read_at', () async {
    final db = await open();
    addTearDown(db.close);

    await runCallHistoryReadStateMigration(db);

    final columns = await db.rawQuery('PRAGMA table_info($kCallHistoryTable)');
    final readAt = columns.firstWhere((c) => c['name'] == 'read_at');
    expect(readAt['notnull'], 0);
    expect(readAt['dflt_value'], isNull);
  });

  test('TC-410-02 rows that already exist start unread', () async {
    final db = await open();
    addTearDown(db.close);
    await db.insert(kCallHistoryTable, _row());

    await runCallHistoryReadStateMigration(db);

    final rows = await db.query(kCallHistoryTable);
    expect(
      rows.single['read_at'],
      isNull,
      reason: 'a call the user has not seen is unread, not silently read',
    );
  });

  test('TC-410-03 the migration is idempotent', () async {
    final db = await open();
    addTearDown(db.close);

    await runCallHistoryReadStateMigration(db);
    await runCallHistoryReadStateMigration(db);

    final columns = await db.rawQuery('PRAGMA table_info($kCallHistoryTable)');
    expect(columns.where((c) => c['name'] == 'read_at'), hasLength(1));
  });

  test('TC-410-04 read_at only accepts a parseable timestamp', () async {
    final db = await open();
    addTearDown(db.close);
    await runCallHistoryReadStateMigration(db);
    await db.insert(kCallHistoryTable, _row());

    await expectLater(
      db.update(kCallHistoryTable, <String, Object?>{'read_at': 'not-a-time'}),
      throwsA(anything),
      reason: 'the table guards every other timestamp the same way',
    );
  });
}

Map<String, Object?> _row() => <String, Object?>{
  'call_id': 'a2f0a1d6-0000-4000-8000-000000000410',
  'contact_account_peer_id': '12D3KooWTestPeerId1234567890',
  'direction': 'incoming',
  'terminal_reason': 'caller_cancelled',
  'status': 'missed',
  'started_at': '2026-02-09T15:30:00.000Z',
  'connected_at': null,
  'ended_at': '2026-02-09T15:30:20.000Z',
  'transport_route_class': null,
  'created_at': '2026-02-09T15:30:20.000Z',
  'updated_at': '2026-02-09T15:30:20.000Z',
};
