import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';

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

  group('Migration 010: media_attachments', () {
    test('creates media_attachments table', () async {
      await runMediaAttachmentsMigration(db);

      // Verify table exists by querying it
      final rows = await db.query('media_attachments');
      expect(rows, isEmpty);
    });

    test('table has correct columns', () async {
      await runMediaAttachmentsMigration(db);

      // Insert a full row to verify all columns exist and have correct types
      await db.insert('media_attachments', {
        'id': 'test-id',
        'message_id': 'msg-id',
        'mime': 'image/jpeg',
        'size': 245000,
        'media_type': 'image',
        'width': 1920,
        'height': 1080,
        'duration_ms': null,
        'local_path': '/path/to/file.jpg',
        'download_status': 'done',
        'created_at': '2026-02-20T10:00:00.000Z',
      });

      final rows = await db.query('media_attachments');
      expect(rows.length, 1);
      expect(rows[0]['id'], 'test-id');
      expect(rows[0]['message_id'], 'msg-id');
      expect(rows[0]['mime'], 'image/jpeg');
      expect(rows[0]['size'], 245000);
      expect(rows[0]['media_type'], 'image');
      expect(rows[0]['width'], 1920);
      expect(rows[0]['height'], 1080);
      expect(rows[0]['duration_ms'], isNull);
      expect(rows[0]['local_path'], '/path/to/file.jpg');
      expect(rows[0]['download_status'], 'done');
      expect(rows[0]['created_at'], '2026-02-20T10:00:00.000Z');
    });

    test('id is primary key', () async {
      await runMediaAttachmentsMigration(db);

      await db.insert('media_attachments', {
        'id': 'dup-id',
        'message_id': 'msg-1',
        'mime': 'image/jpeg',
        'size': 100,
        'media_type': 'image',
        'download_status': 'pending',
        'created_at': '2026-02-20T10:00:00.000Z',
      });

      // Inserting with same ID via REPLACE should work
      await db.insert(
        'media_attachments',
        {
          'id': 'dup-id',
          'message_id': 'msg-2',
          'mime': 'video/mp4',
          'size': 200,
          'media_type': 'video',
          'download_status': 'done',
          'created_at': '2026-02-20T11:00:00.000Z',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final rows = await db.query('media_attachments');
      expect(rows.length, 1);
      expect(rows[0]['message_id'], 'msg-2');
    });

    test('size defaults to 0', () async {
      await runMediaAttachmentsMigration(db);

      await db.rawInsert(
        'INSERT INTO media_attachments (id, message_id, mime, media_type, download_status, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['blob-default', 'msg-1', 'image/jpeg', 'image', 'pending', '2026-02-20T10:00:00.000Z'],
      );

      final rows = await db.query('media_attachments',
          where: 'id = ?', whereArgs: ['blob-default']);
      expect(rows[0]['size'], 0);
    });

    test('download_status defaults to pending', () async {
      await runMediaAttachmentsMigration(db);

      await db.rawInsert(
        'INSERT INTO media_attachments (id, message_id, mime, size, media_type, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['blob-default-status', 'msg-1', 'image/jpeg', 100, 'image', '2026-02-20T10:00:00.000Z'],
      );

      final rows = await db.query('media_attachments',
          where: 'id = ?', whereArgs: ['blob-default-status']);
      expect(rows[0]['download_status'], 'pending');
    });

    test('creates index on message_id', () async {
      await runMediaAttachmentsMigration(db);

      // Verify index exists by querying SQLite master table
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='media_attachments'",
      );
      final indexNames = indexes.map((r) => r['name'] as String).toList();
      expect(indexNames, contains('idx_media_attachments_message'));
    });

    test('is idempotent — running twice does not throw', () async {
      await runMediaAttachmentsMigration(db);
      // Running again should not throw (CREATE TABLE IF NOT EXISTS)
      await runMediaAttachmentsMigration(db);

      // Table should still work
      final rows = await db.query('media_attachments');
      expect(rows, isEmpty);
    });

    test('is idempotent — data is preserved on re-run', () async {
      await runMediaAttachmentsMigration(db);

      await db.insert('media_attachments', {
        'id': 'preserved-blob',
        'message_id': 'msg-1',
        'mime': 'image/jpeg',
        'size': 100,
        'media_type': 'image',
        'download_status': 'pending',
        'created_at': '2026-02-20T10:00:00.000Z',
      });

      // Run migration again
      await runMediaAttachmentsMigration(db);

      // Data should still be there
      final rows = await db.query('media_attachments');
      expect(rows.length, 1);
      expect(rows[0]['id'], 'preserved-blob');
    });
  });
}
