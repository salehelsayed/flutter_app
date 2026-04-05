import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/052_groups_dissolve_columns.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await db.execute('''
      CREATE TABLE groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('chat','announcement','qa')),
        topic_name TEXT NOT NULL UNIQUE,
        description TEXT,
        avatar_blob_id TEXT,
        avatar_mime TEXT,
        avatar_path TEXT,
        created_at TEXT NOT NULL,
        created_by TEXT NOT NULL,
        my_role TEXT NOT NULL CHECK(my_role IN ('admin','member')),
        is_muted INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        archived_at TEXT,
        last_metadata_event_at TEXT
      )
    ''');
  });

  tearDown(() async {
    await db.close();
  });

  group('Migration 052: groups dissolve columns', () {
    test('adds dissolve columns to groups', () async {
      await runGroupsDissolveColumnsMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(groups)');
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('is_dissolved'));
      expect(columnNames, contains('dissolved_at'));
      expect(columnNames, contains('dissolved_by'));
    });

    test('existing rows get non-dissolved defaults on upgrade', () async {
      await db.insert('groups', {
        'id': 'group-1',
        'name': 'Test Group',
        'type': 'chat',
        'topic_name': '/mknoon/groups/group-1',
        'description': 'desc',
        'created_at': '2026-04-05T12:00:00.000Z',
        'created_by': 'peer-admin',
        'my_role': 'admin',
        'is_muted': 0,
        'is_archived': 0,
        'archived_at': null,
      });

      await runGroupsDissolveColumnsMigration(db);

      final rows = await db.query(
        'groups',
        where: 'id = ?',
        whereArgs: ['group-1'],
      );
      expect(rows.first['is_dissolved'], 0);
      expect(rows.first['dissolved_at'], isNull);
      expect(rows.first['dissolved_by'], isNull);
    });

    test('can store dissolved state after migration', () async {
      await runGroupsDissolveColumnsMigration(db);

      await db.insert('groups', {
        'id': 'group-2',
        'name': 'Dissolved Group',
        'type': 'chat',
        'topic_name': '/mknoon/groups/group-2',
        'description': 'desc',
        'created_at': '2026-04-05T12:00:00.000Z',
        'created_by': 'peer-admin',
        'my_role': 'admin',
        'is_muted': 0,
        'is_dissolved': 1,
        'dissolved_at': '2026-04-05T13:30:00.000Z',
        'dissolved_by': 'peer-admin',
        'is_archived': 0,
        'archived_at': null,
      });

      final rows = await db.query(
        'groups',
        where: 'id = ?',
        whereArgs: ['group-2'],
      );
      expect(rows.first['is_dissolved'], 1);
      expect(rows.first['dissolved_at'], '2026-04-05T13:30:00.000Z');
      expect(rows.first['dissolved_by'], 'peer-admin');
    });

    test('is idempotent', () async {
      await runGroupsDissolveColumnsMigration(db);
      await runGroupsDissolveColumnsMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(groups)');
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('is_dissolved'));
      expect(columnNames, contains('dissolved_at'));
      expect(columnNames, contains('dissolved_by'));
    });
  });
}
