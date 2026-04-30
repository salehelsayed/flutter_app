import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/057_group_member_permissions.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupsTablesMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('adds permissions_json to group_members idempotently', () async {
    await runGroupMemberPermissionsMigration(db);
    await runGroupMemberPermissionsMigration(db);

    final columns = await db.rawQuery('PRAGMA table_info(group_members)');
    expect(
      columns.where((column) => column['name'] == 'permissions_json'),
      hasLength(1),
    );

    await db.insert('groups', {
      'id': 'group-1',
      'name': 'Group',
      'type': 'chat',
      'topic_name': '/mknoon/group/group-1',
      'created_at': '2026-04-29T12:00:00.000Z',
      'created_by': 'peer-admin',
      'my_role': 'admin',
    });
    await db.insert('group_members', {
      'group_id': 'group-1',
      'peer_id': 'peer-writer',
      'username': 'Writer',
      'role': 'writer',
      'permissions_json': '{"inviteMembers":true}',
      'joined_at': '2026-04-29T12:00:00.000Z',
    });

    final row = (await db.query('group_members')).single;
    expect(row['permissions_json'], '{"inviteMembers":true}');
  });
}
