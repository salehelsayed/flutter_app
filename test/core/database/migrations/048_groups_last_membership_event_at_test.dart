import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/048_groups_last_membership_event_at.dart';

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

  group('Migration 048: groups.last_membership_event_at', () {
    Future<void> runPrerequisites() async {
      await runGroupsTablesMigration(db);
    }

    test('adds last_membership_event_at column to groups', () async {
      await runPrerequisites();
      await runGroupsLastMembershipEventAtMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(groups)');
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('last_membership_event_at'));
    });

    test('existing rows get null last_membership_event_at on upgrade', () async {
      await runPrerequisites();
      await db.insert('groups', {
        'id': 'group-1',
        'name': 'Test Group',
        'type': 'chat',
        'topic_name': '/mknoon/groups/group-1',
        'description': 'desc',
        'created_at': '2026-04-05T12:00:00.000Z',
        'created_by': 'peer-admin',
        'my_role': 'admin',
        'is_archived': 0,
        'archived_at': null,
      });

      await runGroupsLastMembershipEventAtMigration(db);

      final rows = await db.query(
        'groups',
        where: 'id = ?',
        whereArgs: ['group-1'],
      );
      expect(rows.first['last_membership_event_at'], isNull);
    });

    test('can store a membership-event watermark after migration', () async {
      await runPrerequisites();
      await runGroupsLastMembershipEventAtMigration(db);

      await db.insert('groups', {
        'id': 'group-2',
        'name': 'Test Group',
        'type': 'chat',
        'topic_name': '/mknoon/groups/group-2',
        'description': 'desc',
        'created_at': '2026-04-05T12:00:00.000Z',
        'created_by': 'peer-admin',
        'my_role': 'admin',
        'is_archived': 0,
        'archived_at': null,
        'last_membership_event_at': '2026-04-05T12:10:00.000Z',
      });

      final rows = await db.query(
        'groups',
        where: 'id = ?',
        whereArgs: ['group-2'],
      );
      expect(
        rows.first['last_membership_event_at'],
        '2026-04-05T12:10:00.000Z',
      );
    });

    test('is idempotent', () async {
      await runPrerequisites();
      await runGroupsLastMembershipEventAtMigration(db);
      await runGroupsLastMembershipEventAtMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(groups)');
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('last_membership_event_at'));
    });
  });
}
