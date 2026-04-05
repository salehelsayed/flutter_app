import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/053_groups_backlog_retention_columns.dart';

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
        is_dissolved INTEGER NOT NULL DEFAULT 0,
        dissolved_at TEXT,
        dissolved_by TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0,
        archived_at TEXT,
        last_membership_event_at TEXT,
        last_metadata_event_at TEXT
      )
    ''');
  });

  tearDown(() async {
    await db.close();
  });

  group('Migration 053: groups backlog retention columns', () {
    test('adds backlog retention columns to groups', () async {
      await runGroupsBacklogRetentionColumnsMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(groups)');
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('last_backlog_expired_at'));
      expect(columnNames, contains('last_backlog_retained_at'));
    });

    test(
      'existing rows get null backlog retention defaults on upgrade',
      () async {
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
          'is_dissolved': 0,
          'dissolved_at': null,
          'dissolved_by': null,
          'is_archived': 0,
          'archived_at': null,
          'last_membership_event_at': null,
          'last_metadata_event_at': null,
        });

        await runGroupsBacklogRetentionColumnsMigration(db);

        final rows = await db.query(
          'groups',
          where: 'id = ?',
          whereArgs: ['group-1'],
        );
        expect(rows.first['last_backlog_expired_at'], isNull);
        expect(rows.first['last_backlog_retained_at'], isNull);
      },
    );

    test('can store backlog retention state after migration', () async {
      await runGroupsBacklogRetentionColumnsMigration(db);

      await db.insert('groups', {
        'id': 'group-2',
        'name': 'Retention Group',
        'type': 'chat',
        'topic_name': '/mknoon/groups/group-2',
        'description': 'desc',
        'created_at': '2026-04-05T12:00:00.000Z',
        'created_by': 'peer-admin',
        'my_role': 'admin',
        'is_muted': 0,
        'is_dissolved': 0,
        'dissolved_at': null,
        'dissolved_by': null,
        'is_archived': 0,
        'archived_at': null,
        'last_membership_event_at': null,
        'last_metadata_event_at': null,
        'last_backlog_expired_at': '2026-04-01T09:00:00.000Z',
        'last_backlog_retained_at': '2026-04-03T10:15:00.000Z',
      });

      final rows = await db.query(
        'groups',
        where: 'id = ?',
        whereArgs: ['group-2'],
      );
      expect(rows.first['last_backlog_expired_at'], '2026-04-01T09:00:00.000Z');
      expect(
        rows.first['last_backlog_retained_at'],
        '2026-04-03T10:15:00.000Z',
      );
    });

    test('is idempotent', () async {
      await runGroupsBacklogRetentionColumnsMigration(db);
      await runGroupsBacklogRetentionColumnsMigration(db);

      final columns = await db.rawQuery('PRAGMA table_info(groups)');
      final columnNames = columns.map((col) => col['name'] as String).toList();
      expect(columnNames, contains('last_backlog_expired_at'));
      expect(columnNames, contains('last_backlog_retained_at'));
    });
  });
}
