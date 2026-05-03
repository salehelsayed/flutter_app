import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/061_group_message_transport_peer_id.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runGroupMessagesTablesMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> groupMessageColumns() async {
    final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
    return columns.map((column) => column['name'] as String).toList();
  }

  test('adds nullable transport_peer_id to group_messages', () async {
    expect(await groupMessageColumns(), isNot(contains('transport_peer_id')));

    await runGroupMessageTransportPeerIdMigration(db);

    expect(await groupMessageColumns(), contains('transport_peer_id'));
    await db.insert('group_messages', {
      'id': 'ms002-legacy-message',
      'group_id': 'group-1',
      'sender_peer_id': 'peer-alice',
      'sender_username': 'Alice',
      'text': 'legacy row',
      'timestamp': '2026-05-01T05:00:00.000Z',
      'key_generation': 0,
      'status': 'delivered',
      'is_incoming': 1,
      'created_at': '2026-05-01T05:00:00.000Z',
    });

    final row = (await db.query('group_messages')).single;
    expect(row['transport_peer_id'], isNull);
  });

  test('is idempotent', () async {
    await runGroupMessageTransportPeerIdMigration(db);
    await runGroupMessageTransportPeerIdMigration(db);

    final transportColumns = (await groupMessageColumns())
        .where((name) => name == 'transport_peer_id')
        .toList();
    expect(transportColumns, hasLength(1));
  });
}
