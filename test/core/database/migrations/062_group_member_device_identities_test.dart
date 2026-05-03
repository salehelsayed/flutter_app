import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/062_group_member_device_identities.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runGroupsTablesMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> groupMemberColumns() async {
    final columns = await db.rawQuery('PRAGMA table_info(group_members)');
    return columns.map((column) => column['name'] as String).toList();
  }

  test('adds nullable devices_json without changing existing rows', () async {
    await db.insert('group_members', {
      'group_id': 'group-1',
      'peer_id': 'member-b',
      'username': 'Bob',
      'role': 'writer',
      'public_key': 'member-pk',
      'ml_kem_public_key': 'legacy-mlkem',
      'joined_at': '2026-05-01T05:00:00.000Z',
    });

    expect(await groupMemberColumns(), isNot(contains('devices_json')));

    await runGroupMemberDeviceIdentitiesMigration(db);

    expect(await groupMemberColumns(), contains('devices_json'));
    final row = (await db.query('group_members')).single;
    expect(row['peer_id'], 'member-b');
    expect(row['devices_json'], isNull);
  });

  test('is idempotent', () async {
    await runGroupMemberDeviceIdentitiesMigration(db);
    await runGroupMemberDeviceIdentitiesMigration(db);

    final deviceColumns = (await groupMemberColumns())
        .where((name) => name == 'devices_json')
        .toList();
    expect(deviceColumns, hasLength(1));
  });
}
