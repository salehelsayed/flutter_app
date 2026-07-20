// ignore_for_file: file_names
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/073_group_message_last_send_attempt_at.dart';

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

  test('adds nullable last_send_attempt_at to group_messages', () async {
    expect(
      await groupMessageColumns(),
      isNot(contains('last_send_attempt_at')),
    );

    await runGroupMessageLastSendAttemptAtMigration(db);

    expect(await groupMessageColumns(), contains('last_send_attempt_at'));
  });

  test('preserves existing rows with null last_send_attempt_at', () async {
    await db.insert('group_messages', {
      'id': 'legacy-group-message',
      'group_id': 'group-1',
      'sender_peer_id': 'peer-alice',
      'sender_username': 'Alice',
      'text': 'legacy row',
      'timestamp': '2026-05-01T05:00:00.000Z',
      'key_generation': 0,
      'status': 'sending',
      'is_incoming': 0,
      'created_at': '2026-05-01T05:00:00.000Z',
    });

    await runGroupMessageLastSendAttemptAtMigration(db);

    final row = (await db.query(
      'group_messages',
      where: 'id = ?',
      whereArgs: ['legacy-group-message'],
    )).single;
    expect(row['text'], 'legacy row');
    expect(row['last_send_attempt_at'], isNull);
  });

  test('is idempotent', () async {
    await runGroupMessageLastSendAttemptAtMigration(db);
    await runGroupMessageLastSendAttemptAtMigration(db);

    final lastSendAttemptColumns = (await groupMessageColumns())
        .where((name) => name == 'last_send_attempt_at')
        .toList();
    expect(lastSendAttemptColumns, hasLength(1));
  });
}
