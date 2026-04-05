import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/050_groups_mute_column.dart';

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
        is_archived INTEGER NOT NULL DEFAULT 0,
        archived_at TEXT,
        last_metadata_event_at TEXT
      )
    ''');
  });

  tearDown(() async {
    await db.close();
  });

  group('Migration 050: groups.is_muted', () {
    test('adds is_muted column to groups', () async {
      await runGroupsMuteColumnMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(groups)');
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('is_muted'));
    });

    test('existing rows get is_muted = 0 on upgrade', () async {
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

      await runGroupsMuteColumnMigration(db);

      final rows = await db.query(
        'groups',
        where: 'id = ?',
        whereArgs: ['group-1'],
      );
      expect(rows.first['is_muted'], 0);
    });

    test('can store muted state after migration', () async {
      await runGroupsMuteColumnMigration(db);

      await db.insert('groups', {
        'id': 'group-2',
        'name': 'Muted Group',
        'type': 'chat',
        'topic_name': '/mknoon/groups/group-2',
        'description': 'desc',
        'created_at': '2026-04-05T12:00:00.000Z',
        'created_by': 'peer-admin',
        'my_role': 'admin',
        'is_muted': 1,
        'is_archived': 0,
        'archived_at': null,
      });

      final rows = await db.query(
        'groups',
        where: 'id = ?',
        whereArgs: ['group-2'],
      );
      expect(rows.first['is_muted'], 1);
    });

    test('is idempotent', () async {
      await runGroupsMuteColumnMigration(db);
      await runGroupsMuteColumnMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(groups)');
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('is_muted'));
    });
  });
}
