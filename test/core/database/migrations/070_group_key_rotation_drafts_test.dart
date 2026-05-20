// ignore_for_file: file_names

import 'package:flutter_app/core/database/migrations/070_group_key_rotation_drafts.dart';
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

  group('Migration 070: group_key_rotation_drafts', () {
    test('creates pending rotation draft table and index', () async {
      await runGroupKeyRotationDraftsMigration(db);

      final columns = await db.rawQuery(
        "PRAGMA table_info('group_key_rotation_drafts')",
      );
      expect(
        columns.map((row) => row['name']).toSet(),
        containsAll([
          'group_id',
          'key_generation',
          'encrypted_key',
          'created_at',
        ]),
      );

      final indexes = await db.rawQuery(
        "PRAGMA index_list('group_key_rotation_drafts')",
      );
      expect(
        indexes.map((row) => row['name']).toSet(),
        contains('idx_group_key_rotation_drafts_group_epoch'),
      );
    });

    test('is idempotent', () async {
      await runGroupKeyRotationDraftsMigration(db);
      await runGroupKeyRotationDraftsMigration(db);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'group_key_rotation_drafts'",
      );
      expect(tables, isNotEmpty);
    });

    test('keeps one draft per group', () async {
      await runGroupKeyRotationDraftsMigration(db);

      await db.insert('group_key_rotation_drafts', {
        'group_id': 'group-1',
        'key_generation': 2,
        'encrypted_key': 'draft-key-2',
        'created_at': '2026-05-13T09:00:00.000Z',
      });
      await db.insert('group_key_rotation_drafts', {
        'group_id': 'group-1',
        'key_generation': 3,
        'encrypted_key': 'draft-key-3',
        'created_at': '2026-05-13T09:05:00.000Z',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final rows = await db.query('group_key_rotation_drafts');
      expect(rows, hasLength(1));
      expect(rows.single['key_generation'], 3);
      expect(rows.single['encrypted_key'], 'draft-key-3');
    });
  });
}
