import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/089_media_attachment_download_retry_column.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runMediaAttachmentsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('adds download_retry_count to media_attachments and defaults to 0',
      () async {
    await runMediaAttachmentDownloadRetryColumnMigration(db);

    final columns = await db.rawQuery('PRAGMA table_info(media_attachments)');
    final names = columns.map((row) => row['name'] as String).toSet();
    expect(names, contains('download_retry_count'));

    await db.insert('media_attachments', {
      'id': 'blob-1',
      'message_id': 'msg-1',
      'mime': 'image/jpeg',
      'size': 123,
      'media_type': 'image',
      'download_status': 'pending',
      'created_at': '2026-06-17T00:00:00.000Z',
    });

    final row = (await db.query('media_attachments',
            where: 'id = ?', whereArgs: ['blob-1']))
        .single;
    expect(row['download_retry_count'], 0);
  });

  test('is idempotent when the column already exists', () async {
    await runMediaAttachmentDownloadRetryColumnMigration(db);
    // Second run must be a no-op (ALTER guarded by PRAGMA), not throw.
    await runMediaAttachmentDownloadRetryColumnMigration(db);

    final columns = await db.rawQuery('PRAGMA table_info(media_attachments)');
    final names = columns.map((row) => row['name'] as String).toSet();
    expect(names, contains('download_retry_count'));
  });
}
