import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/063_group_pending_key_repairs.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> columns() async {
    final rows = await db.rawQuery(
      'PRAGMA table_info(group_pending_key_repairs)',
    );
    return rows.map((row) => row['name'] as String).toList();
  }

  test('creates durable pending group key repair queue schema', () async {
    await runGroupPendingKeyRepairsMigration(db);

    expect(
      await columns(),
      containsAll([
        'id',
        'group_id',
        'message_id',
        'sender_peer_id',
        'transport_peer_id',
        'payload_type',
        'key_epoch',
        'replay_envelope_json',
        'status',
        'trigger_count',
        'attempts',
        'last_error',
        'created_at',
        'updated_at',
        'finalized_at',
      ]),
    );

    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='group_pending_key_repairs'",
    );
    expect(
      indexes.map((row) => row['name'] as String),
      containsAll([
        'idx_group_pending_key_repairs_group_epoch_status',
        'idx_group_pending_key_repairs_group_message',
      ]),
    );
  });

  test('is idempotent', () async {
    await runGroupPendingKeyRepairsMigration(db);
    await runGroupPendingKeyRepairsMigration(db);

    final idColumns = (await columns()).where((name) => name == 'id').toList();
    expect(idColumns, hasLength(1));
  });
}
