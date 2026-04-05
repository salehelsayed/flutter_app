import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/049_groups_metadata_columns.dart';

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

  group('Migration 049: groups metadata columns', () {
    Future<void> runPrerequisites() async {
      await runGroupsTablesMigration(db);
    }

    test('adds avatar and metadata watermark columns to groups', () async {
      await runPrerequisites();
      await runGroupsMetadataColumnsMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(groups)');
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('avatar_blob_id'));
      expect(columnNames, contains('avatar_mime'));
      expect(columnNames, contains('avatar_path'));
      expect(columnNames, contains('last_metadata_event_at'));
    });

    test('existing rows get null metadata columns on upgrade', () async {
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

      await runGroupsMetadataColumnsMigration(db);

      final rows = await db.query(
        'groups',
        where: 'id = ?',
        whereArgs: ['group-1'],
      );
      expect(rows.first['avatar_blob_id'], isNull);
      expect(rows.first['avatar_mime'], isNull);
      expect(rows.first['avatar_path'], isNull);
      expect(rows.first['last_metadata_event_at'], isNull);
    });

    test('can store metadata fields after migration', () async {
      await runPrerequisites();
      await runGroupsMetadataColumnsMigration(db);

      await db.insert('groups', {
        'id': 'group-2',
        'name': 'Test Group',
        'type': 'chat',
        'topic_name': '/mknoon/groups/group-2',
        'description': 'desc',
        'avatar_blob_id': 'blob-2',
        'avatar_mime': 'image/jpeg',
        'avatar_path': 'media/group_avatars/group-2.jpg',
        'created_at': '2026-04-05T12:00:00.000Z',
        'created_by': 'peer-admin',
        'my_role': 'admin',
        'is_archived': 0,
        'archived_at': null,
        'last_metadata_event_at': '2026-04-05T12:20:00.000Z',
      });

      final rows = await db.query(
        'groups',
        where: 'id = ?',
        whereArgs: ['group-2'],
      );
      expect(rows.first['avatar_blob_id'], 'blob-2');
      expect(rows.first['avatar_mime'], 'image/jpeg');
      expect(rows.first['avatar_path'], 'media/group_avatars/group-2.jpg');
      expect(rows.first['last_metadata_event_at'], '2026-04-05T12:20:00.000Z');
    });

    test('is idempotent', () async {
      await runPrerequisites();
      await runGroupsMetadataColumnsMigration(db);
      await runGroupsMetadataColumnsMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(groups)');
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('avatar_blob_id'));
      expect(columnNames, contains('avatar_mime'));
      expect(columnNames, contains('avatar_path'));
      expect(columnNames, contains('last_metadata_event_at'));
    });
  });
}
