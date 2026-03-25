import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/010_media_attachments.dart';
import 'package:flutter_app/core/database/migrations/042_media_attachment_reliability_columns.dart';

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

  test('adds upload_retry_count to media_attachments and defaults to 0',
      () async {
    await runMediaAttachmentReliabilityColumnsMigration(db);

    final columns = await db.rawQuery('PRAGMA table_info(media_attachments)');
    final names = columns.map((row) => row['name'] as String).toSet();
    expect(names, contains('upload_retry_count'));

    await db.insert('media_attachments', {
      'id': 'blob-1',
      'message_id': 'msg-1',
      'mime': 'image/jpeg',
      'size': 123,
      'media_type': 'image',
      'download_status': 'upload_pending',
      'created_at': '2026-03-25T00:00:00.000Z',
    });

    final row = (await db.query('media_attachments', where: 'id = ?', whereArgs: ['blob-1'])).single;
    expect(row['upload_retry_count'], 0);
  });
}
