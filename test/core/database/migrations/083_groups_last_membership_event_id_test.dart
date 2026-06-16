// ignore_for_file: file_names

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/083_groups_last_membership_event_id.dart';

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

  Future<List<String>> groupColumns() async {
    final columns = await db.rawQuery('PRAGMA table_info(groups)');
    return columns.map((column) => column['name'] as String).toList();
  }

  test('adds nullable last_membership_event_id to groups', () async {
    expect(await groupColumns(), isNot(contains('last_membership_event_id')));

    await runGroupsLastMembershipEventIdMigration(db);

    expect(await groupColumns(), contains('last_membership_event_id'));
  });

  test('preserves existing rows with null last_membership_event_id', () async {
    await db.insert('groups', {
      'id': 'legacy-group',
      'name': 'Legacy Group',
      'type': 'chat',
      'topic_name': 'topic-legacy',
      'created_at': '2026-05-01T05:00:00.000Z',
      'created_by': 'peer-admin',
      'my_role': 'admin',
    });

    await runGroupsLastMembershipEventIdMigration(db);

    final row = (await db.query(
      'groups',
      where: 'id = ?',
      whereArgs: ['legacy-group'],
    )).single;
    expect(row['name'], 'Legacy Group');
    expect(row['last_membership_event_id'], isNull);
  });

  test('is idempotent', () async {
    await runGroupsLastMembershipEventIdMigration(db);
    await runGroupsLastMembershipEventIdMigration(db);

    final idColumns = (await groupColumns())
        .where((name) => name == 'last_membership_event_id')
        .toList();
    expect(idColumns, hasLength(1));
  });
}
