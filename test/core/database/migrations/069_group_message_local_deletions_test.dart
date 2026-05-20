// ignore_for_file: file_names

import 'package:flutter_app/core/database/migrations/069_group_message_local_deletions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  group('Migration 069: group_message_local_deletions', () {
    test('IR-020 creates local deletion tombstone table and index', () async {
      await runGroupMessageLocalDeletionsMigration(db);

      final columns = await db.rawQuery(
        "PRAGMA table_info('group_message_local_deletions')",
      );
      expect(
        columns.map((row) => row['name']).toSet(),
        containsAll(['message_id', 'group_id', 'deleted_at', 'created_at']),
      );

      final indexes = await db.rawQuery(
        "PRAGMA index_list('group_message_local_deletions')",
      );
      expect(
        indexes.map((row) => row['name']).toSet(),
        contains('idx_group_message_local_deletions_group'),
      );
    });

    test(
      'IR-020 is idempotent and keeps one tombstone per message id',
      () async {
        await runGroupMessageLocalDeletionsMigration(db);
        await runGroupMessageLocalDeletionsMigration(db);

        await db.insert('group_message_local_deletions', {
          'message_id': 'msg-ir020',
          'group_id': 'group-1',
          'deleted_at': '2026-05-14T09:00:00.000Z',
          'created_at': '2026-05-14T09:00:00.000Z',
        });
        await db.insert(
          'group_message_local_deletions',
          {
            'message_id': 'msg-ir020',
            'group_id': 'group-1',
            'deleted_at': '2026-05-14T09:05:00.000Z',
            'created_at': '2026-05-14T09:05:00.000Z',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        final rows = await db.query('group_message_local_deletions');
        expect(rows, hasLength(1));
        expect(rows.single['message_id'], 'msg-ir020');
        expect(rows.single['deleted_at'], '2026-05-14T09:05:00.000Z');
      },
    );
  });
}
