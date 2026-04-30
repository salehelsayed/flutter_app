import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/060_group_event_log.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
  });

  tearDown(() async {
    await db.close();
  });

  test('creates group event log table and indexes idempotently', () async {
    await runGroupEventLogMigration(db);
    await runGroupEventLogMigration(db);

    final columns = await db.rawQuery('PRAGMA table_info(group_event_log)');
    final names = columns.map((column) => column['name']).toList();
    expect(
      names,
      containsAll([
        'id',
        'group_id',
        'sequence',
        'event_type',
        'source_peer_id',
        'source_event_id',
        'source_timestamp',
        'canonical_payload',
        'previous_entry_hash',
        'entry_hash',
        'created_at',
      ]),
    );

    final indexes = await db.rawQuery('PRAGMA index_list(group_event_log)');
    final indexNames = indexes.map((index) => index['name']).toSet();
    expect(indexNames, contains('idx_group_event_log_group_sequence'));
    expect(indexNames, contains('idx_group_event_log_event_type'));

    await db.insert('group_event_log', {
      'id': 'entry-1',
      'group_id': 'group-1',
      'sequence': 1,
      'event_type': 'message',
      'source_peer_id': 'peer-a',
      'source_event_id': 'msg-1',
      'source_timestamp': '2026-04-30T12:00:00.000Z',
      'canonical_payload': '{"messageId":"msg-1"}',
      'previous_entry_hash': null,
      'entry_hash': 'hash-1',
      'created_at': '2026-04-30T12:00:01.000Z',
    });

    final row = (await db.query('group_event_log')).single;
    expect(row['group_id'], 'group-1');
    expect(row['source_event_id'], 'msg-1');
  });
}
