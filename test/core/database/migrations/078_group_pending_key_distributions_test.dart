// ignore_for_file: file_names
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/078_group_pending_key_distributions.dart';

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
      'PRAGMA table_info(group_pending_key_distributions)',
    );
    return rows.map((row) => row['name'] as String).toList();
  }

  test('creates durable pending group key distribution queue schema', () async {
    await runGroupPendingKeyDistributionsMigration(db);

    expect(
      await columns(),
      containsAll([
        'id',
        'group_id',
        'peer_id',
        'transport_peer_id',
        'device_id',
        'key_epoch',
        'status',
        'attempts',
        'last_error',
        'created_at',
        'updated_at',
        'finalized_at',
      ]),
    );

    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='group_pending_key_distributions'",
    );
    expect(
      indexes.map((row) => row['name'] as String),
      containsAll([
        'idx_group_pending_key_distributions_group_status',
        'idx_group_pending_key_distributions_peer_status',
      ]),
    );
  });

  test('is idempotent', () async {
    await runGroupPendingKeyDistributionsMigration(db);
    await runGroupPendingKeyDistributionsMigration(db);

    final idColumns = (await columns()).where((name) => name == 'id').toList();
    expect(idColumns, hasLength(1));
  });

  test('enforces UNIQUE(group_id, peer_id)', () async {
    await runGroupPendingKeyDistributionsMigration(db);

    Future<void> insert(String id) =>
        db.insert('group_pending_key_distributions', {
          'id': id,
          'group_id': 'group-1',
          'peer_id': 'peer-carol',
          'key_epoch': 2,
          'status': 'pending',
          'attempts': 0,
          'created_at': '2026-06-16T00:00:00.000Z',
          'updated_at': '2026-06-16T00:00:00.000Z',
        });

    await insert('dist-1');
    await expectLater(insert('dist-2'), throwsA(isA<DatabaseException>()));
  });
}
