import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/074_group_message_logical_delivery_id.dart';

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

  Future<List<String>> groupMessageIndexes() async {
    final indexes = await db.rawQuery('PRAGMA index_list(group_messages)');
    return indexes.map((index) => index['name'] as String).toList();
  }

  test('adds nullable logical_delivery_id and lookup index', () async {
    expect(await groupMessageColumns(), isNot(contains('logical_delivery_id')));

    await runGroupMessageLogicalDeliveryIdMigration(db);

    expect(await groupMessageColumns(), contains('logical_delivery_id'));
    expect(
      await groupMessageIndexes(),
      contains('idx_group_messages_logical_delivery'),
    );
  });

  test('preserves existing rows with null logical_delivery_id', () async {
    await db.insert('group_messages', {
      'id': 'legacy-logical-delivery-row',
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

    await runGroupMessageLogicalDeliveryIdMigration(db);

    final row = (await db.query(
      'group_messages',
      where: 'id = ?',
      whereArgs: ['legacy-logical-delivery-row'],
    )).single;
    expect(row['text'], 'legacy row');
    expect(row['logical_delivery_id'], isNull);
  });

  test('is idempotent', () async {
    await runGroupMessageLogicalDeliveryIdMigration(db);
    await runGroupMessageLogicalDeliveryIdMigration(db);

    final columns = (await groupMessageColumns())
        .where((name) => name == 'logical_delivery_id')
        .toList();
    expect(columns, hasLength(1));
    expect(
      (await groupMessageIndexes()).where(
        (name) => name == 'idx_group_messages_logical_delivery',
      ),
      hasLength(1),
    );
  });
}
