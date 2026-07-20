// ignore_for_file: file_names
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/081_group_pending_reactions.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // 081 creates the table from scratch; no prerequisite migration.
  });

  tearDown(() async {
    await db.close();
  });

  Future<bool> tableExists(String name) async {
    final rows = await db.query(
      'sqlite_master',
      where: "type = 'table' AND name = ?",
      whereArgs: [name],
    );
    return rows.isNotEmpty;
  }

  Future<bool> indexExists(String name) async {
    final rows = await db.query(
      'sqlite_master',
      where: "type = 'index' AND name = ?",
      whereArgs: [name],
    );
    return rows.isNotEmpty;
  }

  test('081 creates the group_pending_reactions table and indexes', () async {
    expect(await tableExists('group_pending_reactions'), isFalse);

    await runGroupPendingReactionsMigration(db);

    expect(await tableExists('group_pending_reactions'), isTrue);
    expect(
      await indexExists('idx_group_pending_reactions_group_message'),
      isTrue,
    );
    expect(
      await indexExists('idx_group_pending_reactions_group_received'),
      isTrue,
    );
  });

  test('081 table has the expected columns', () async {
    await runGroupPendingReactionsMigration(db);
    final columns = await db.rawQuery(
      'PRAGMA table_info(group_pending_reactions)',
    );
    final names = columns.map((c) => c['name'] as String).toSet();
    expect(
      names,
      containsAll(<String>[
        'id',
        'group_id',
        'message_id',
        'sender_peer_id',
        'transport_peer_id',
        'sender_device_id',
        'sender_public_key',
        'reaction_json',
        'received_at',
        'created_at',
        'updated_at',
      ]),
    );
  });

  test('081 is idempotent on re-run', () async {
    await runGroupPendingReactionsMigration(db);
    await runGroupPendingReactionsMigration(db);

    expect(await tableExists('group_pending_reactions'), isTrue);
  });
}
